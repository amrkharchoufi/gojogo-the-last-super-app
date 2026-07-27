package com.gojogo.partner.internal;

import com.gojogo.delivery.MerchantProvisioningApi;
import com.gojogo.delivery.MerchantRegistration;
import com.gojogo.media.MediaApi;
import com.gojogo.media.MediaDocumentApi;
import com.gojogo.partner.PartnerReviewed;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Applications, their documents, and the review that decides them.
 *
 * <p>Approval is a <em>human</em> act, and there is no admin role in this app
 * (the same constraint that left the music catalog without an ingest endpoint),
 * so the review surface is a token-guarded controller outside the JWT chain —
 * see {@link PartnerAdminController}. Nothing auto-approves: KYC that a machine
 * waves through is not KYC.
 */
@Service
class PartnerService {

    private static final Set<PartnerStatus> QUEUE_DEFAULT = EnumSet.of(PartnerStatus.SUBMITTED);

    private final PartnerAccountRepository accounts;
    private final PartnerDocumentRepository documents;
    private final MerchantProvisioningApi merchants;
    private final MediaDocumentApi privateMedia;
    private final MediaApi media;
    private final ApplicationEventPublisher events;

    PartnerService(PartnerAccountRepository accounts, PartnerDocumentRepository documents,
                   MerchantProvisioningApi merchants, MediaDocumentApi privateMedia,
                   MediaApi media, ApplicationEventPublisher events) {
        this.accounts = accounts;
        this.documents = documents;
        this.merchants = merchants;
        this.privateMedia = privateMedia;
        this.media = media;
        this.events = events;
    }

    // MARK: The applicant's side

    /**
     * The caller's application, or null. Multiple kinds are possible in the
     * schema (one restaurant, one driver), but the app only ever asks about one
     * at a time, so the caller names it.
     */
    @Transactional(readOnly = true)
    MyPartnerResponse mine(UUID me, String kindName) {
        PartnerKind kind = parseKind(kindName);
        return new MyPartnerResponse(accounts.findByUserIdAndKind(me, kind)
            .map(this::toDto)
            .orElse(null));
    }

    /**
     * Creates the application or edits it in place. One upsert rather than a
     * POST/PUT pair: there is at most one application per person per kind, so
     * the client never has to know whether it already exists.
     */
    @Transactional
    PartnerAccountDto save(UUID me, SavePartnerApplicationRequest request) {
        PartnerKind kind = parseKind(request.kind());
        PartnerAccount account = accounts.findByUserIdAndKind(me, kind)
            .orElseGet(() -> accounts.save(
                new PartnerAccount(me, kind, request.businessName().trim())));
        if (!account.getStatus().isEditable()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, editBlockedMessage(account));
        }
        account.apply(request.businessName().trim(), request.category(), request.description(),
            request.logoUrl(), request.contactName(), request.contactPhone(),
            request.contactEmail(), request.country(), request.city(), request.addressLine(),
            request.latitude(), request.longitude());
        // The logo is ordinary public media (it ends up on the storefront), so
        // it goes through the normal reference tracking; the KYC papers do not.
        // (Collections.singletonList, not List.of — the logo is optional.)
        media.markReferenced(Collections.singletonList(request.logoUrl()));
        return toDto(account);
    }

    /** Somewhere private to put one paper. Nothing is recorded until the client
     *  comes back with the key, so an abandoned upload leaves no row. */
    @Transactional(readOnly = true)
    DocumentUploadResponse presignDocument(UUID me, UUID accountId, DocumentUploadRequest request) {
        PartnerAccount account = requireEditable(me, accountId);
        parseDocumentKind(request.kind());
        MediaDocumentApi.DocumentUpload upload =
            privateMedia.presignDocumentUpload(account.getUserId(), "partner", request.contentType());
        return new DocumentUploadResponse(upload.uploadUrl(), upload.objectKey(),
            upload.contentType(), upload.expiresSeconds());
    }

    /**
     * Records an uploaded paper against the application. Re-uploading a kind
     * replaces it — and deletes the object it replaced, since nothing else
     * sweeps the private prefix.
     */
    @Transactional
    PartnerAccountDto attachDocument(UUID me, UUID accountId, AttachDocumentRequest request) {
        PartnerAccount account = requireEditable(me, accountId);
        DocumentKind kind = parseDocumentKind(request.kind());
        // The key must be one we minted for this applicant — otherwise an
        // attach could point the reviewer at any object in the bucket.
        String expectedPrefix = "private/partner/" + account.getUserId() + "/";
        if (!request.objectKey().startsWith(expectedPrefix)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "That upload isn't yours");
        }
        documents.findByAccountIdAndKind(account.getId(), kind).ifPresentOrElse(existing -> {
            String previous = existing.getObjectKey();
            existing.replaceWith(request.objectKey(), request.contentType());
            if (!previous.equals(request.objectKey())) {
                privateMedia.deleteDocument(previous);
            }
        }, () -> documents.save(new PartnerDocument(account.getId(), kind,
            request.objectKey(), request.contentType())));
        return toDto(account);
    }

    @Transactional
    PartnerAccountDto deleteDocument(UUID me, UUID accountId, UUID documentId) {
        PartnerAccount account = requireEditable(me, accountId);
        PartnerDocument document = documents.findById(documentId)
            .filter(d -> d.getAccountId().equals(account.getId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such document"));
        documents.delete(document);
        privateMedia.deleteDocument(document.getObjectKey());
        documents.flush();
        return toDto(account);
    }

    /**
     * Hands the application to a reviewer. The completeness check runs here and
     * only here — the app's checklist is a rendering of {@code missingDocuments},
     * not a second implementation of the rule.
     */
    @Transactional
    PartnerAccountDto submit(UUID me, UUID accountId) {
        PartnerAccount account = requireEditable(me, accountId);
        List<String> missing = missingFields(account);
        if (!missing.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Still missing: " + String.join(", ", missing));
        }
        Set<DocumentKind> uploaded = uploadedKinds(account.getId());
        Set<DocumentKind> required = new TreeSet<>(account.getKind().requiredDocuments());
        required.removeAll(uploaded);
        if (!required.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Upload your " + required.stream().map(PartnerService::label)
                    .collect(Collectors.joining(", ")));
        }
        account.submit(OffsetDateTime.now());
        return toDto(account);
    }

    /** Pulls it back out of the queue so it can be edited again. */
    @Transactional
    PartnerAccountDto withdraw(UUID me, UUID accountId) {
        PartnerAccount account = require(me, accountId);
        if (account.getStatus() != PartnerStatus.SUBMITTED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Only an application under review can be withdrawn");
        }
        account.withdraw();
        return toDto(account);
    }

    // MARK: The reviewer's side

    @Transactional(readOnly = true)
    List<ReviewApplicationDto> queue(String statusName, int limit) {
        Collection<PartnerStatus> statuses = statusName == null || statusName.isBlank()
            ? QUEUE_DEFAULT
            : List.of(parseStatus(statusName));
        List<PartnerAccount> page = accounts.findByStatusInOrderBySubmittedAtAscCreatedAtAsc(
            statuses, PageRequest.of(0, Math.clamp(limit, 1, 100)));
        Map<UUID, List<PartnerDocument>> byAccount = documents
            .findByAccountIdInOrderByKindAsc(page.stream().map(PartnerAccount::getId).toList())
            .stream().collect(Collectors.groupingBy(PartnerDocument::getAccountId));
        return page.stream()
            .map(a -> new ReviewApplicationDto(toDto(a), byAccount
                .getOrDefault(a.getId(), List.of()).stream()
                .map(this::toReviewDocument)
                .toList()))
            .toList();
    }

    /** One application in full, with a freshly signed link per document. */
    @Transactional(readOnly = true)
    ReviewApplicationDto review(UUID accountId) {
        return toReview(requireExisting(accountId));
    }

    /**
     * Approves an application and provisions whatever its kind earns. The
     * provisioning call is idempotent, so a retried approval — or a reviewer who
     * clicks twice — cannot leave a partner with two restaurants.
     */
    @Transactional
    ReviewApplicationDto approve(UUID accountId) {
        PartnerAccount account = requireExisting(accountId);
        if (account.getStatus() == PartnerStatus.SUSPENDED) {
            account.restore(OffsetDateTime.now());
            merchants.setMerchantSuspended(account.getProvisionedRefId(), false);
            publish(account);
            return toReview(account);
        }
        if (account.getStatus() != PartnerStatus.SUBMITTED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Only a submitted application can be approved (this one is "
                    + account.getStatus() + ")");
        }
        if (!account.getKind().isProvisionable()) {
            // Better a plain refusal than an approval that provisions nothing:
            // the applicant would see "approved" and find no way to work.
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                account.getKind() + " partners can't be provisioned yet — that "
                    + "needs the dispatch module (Phase 3)");
        }
        UUID refId = merchants.provisionMerchant(new MerchantRegistration(
            account.getUserId(), account.getBusinessName(), account.getCategory(),
            account.getLogoUrl(), account.getLatitude(), account.getLongitude()));
        account.approve(refId, OffsetDateTime.now());
        publish(account);
        return toReview(account);
    }

    @Transactional
    ReviewApplicationDto reject(UUID accountId, String note) {
        PartnerAccount account = requireExisting(accountId);
        if (account.getStatus() != PartnerStatus.SUBMITTED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Only a submitted application can be rejected (this one is "
                    + account.getStatus() + ")");
        }
        account.reject(note, OffsetDateTime.now());
        publish(account);
        return toReview(account);
    }

    /** Blocks an approved partner without deleting anything: the restaurant
     *  leaves the catalog, its menu stays, and approving again brings it back. */
    @Transactional
    ReviewApplicationDto suspend(UUID accountId, String note) {
        PartnerAccount account = requireExisting(accountId);
        if (account.getStatus() != PartnerStatus.APPROVED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Only an approved partner can be suspended (this one is "
                    + account.getStatus() + ")");
        }
        account.suspend(note, OffsetDateTime.now());
        merchants.setMerchantSuspended(account.getProvisionedRefId(), true);
        publish(account);
        return toReview(account);
    }

    private void publish(PartnerAccount account) {
        events.publishEvent(new PartnerReviewed(account.getId(), account.getUserId(),
            account.getKind().name(), account.getBusinessName(), account.getStatus().name(),
            account.getProvisionedRefId(), account.getReviewNote(), account.getReviewedAt()));
    }

    // MARK: Lookups + validation

    /** 404 rather than 403 for someone else's application — don't confirm it exists. */
    private PartnerAccount require(UUID me, UUID accountId) {
        return accounts.findById(accountId)
            .filter(a -> a.getUserId().equals(me))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such application"));
    }

    private PartnerAccount requireEditable(UUID me, UUID accountId) {
        PartnerAccount account = require(me, accountId);
        if (!account.getStatus().isEditable()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, editBlockedMessage(account));
        }
        return account;
    }

    private PartnerAccount requireExisting(UUID accountId) {
        return accounts.findById(accountId).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.NOT_FOUND, "No such application"));
    }

    private static String editBlockedMessage(PartnerAccount account) {
        return account.getStatus() == PartnerStatus.SUBMITTED
            ? "Your application is being reviewed — withdraw it first to make changes"
            : "An approved partner's details are managed from your dashboard";
    }

    /** The business facts a reviewer can't work without. Documents are checked
     *  separately so the two failures read differently to the applicant. */
    private static List<String> missingFields(PartnerAccount account) {
        List<String> missing = new ArrayList<>();
        if (account.getBusinessName().isBlank()) missing.add("business name");
        if (account.getCategory().isBlank()) missing.add("category");
        if (account.getContactName().isBlank()) missing.add("contact name");
        if (account.getContactPhone().isBlank()) missing.add("contact phone");
        if (account.getAddressLine().isBlank()) missing.add("address");
        if (account.getCity().isBlank()) missing.add("city");
        return missing;
    }

    private Set<DocumentKind> uploadedKinds(UUID accountId) {
        return documents.findByAccountIdOrderByKindAsc(accountId).stream()
            .map(PartnerDocument::getKind)
            .collect(Collectors.toCollection(() -> EnumSet.noneOf(DocumentKind.class)));
    }

    private static PartnerKind parseKind(String name) {
        try {
            return PartnerKind.valueOf(name.trim().toUpperCase());
        } catch (RuntimeException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown partner kind; use one of " + EnumSet.allOf(PartnerKind.class));
        }
    }

    private static PartnerStatus parseStatus(String name) {
        try {
            return PartnerStatus.valueOf(name.trim().toUpperCase());
        } catch (RuntimeException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown status; use one of " + EnumSet.allOf(PartnerStatus.class));
        }
    }

    private static DocumentKind parseDocumentKind(String name) {
        try {
            return DocumentKind.valueOf(name.trim().toUpperCase());
        } catch (RuntimeException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown document kind; use one of " + EnumSet.allOf(DocumentKind.class));
        }
    }

    /** "ID_FRONT" → "ID front", for a message the applicant reads. */
    private static String label(DocumentKind kind) {
        String words = kind.name().replace('_', ' ').toLowerCase();
        return kind.name().startsWith("ID") ? "ID" + words.substring(2) : words;
    }

    // MARK: Mapping

    private ReviewApplicationDto toReview(PartnerAccount account) {
        return new ReviewApplicationDto(toDto(account),
            documents.findByAccountIdOrderByKindAsc(account.getId()).stream()
                .map(this::toReviewDocument)
                .toList());
    }

    private ReviewDocumentDto toReviewDocument(PartnerDocument document) {
        return new ReviewDocumentDto(document.getId(), document.getKind().name(),
            document.getContentType(), privateMedia.presignDocumentRead(document.getObjectKey()),
            document.getUploadedAt());
    }

    private PartnerAccountDto toDto(PartnerAccount account) {
        List<PartnerDocument> uploaded = documents.findByAccountIdOrderByKindAsc(account.getId());
        Set<DocumentKind> have = uploaded.stream()
            .map(PartnerDocument::getKind)
            .collect(Collectors.toCollection(() -> EnumSet.noneOf(DocumentKind.class)));
        List<String> required = account.getKind().requiredDocuments().stream()
            .map(Enum::name).toList();
        List<String> missing = account.getKind().requiredDocuments().stream()
            .filter(kind -> !have.contains(kind))
            .map(Enum::name).toList();
        boolean editable = account.getStatus().isEditable();
        return new PartnerAccountDto(
            account.getId(), account.getKind().name(), account.getStatus().name(),
            account.getBusinessName(), account.getCategory(), account.getDescription(),
            account.getLogoUrl(), account.getContactName(), account.getContactPhone(),
            account.getContactEmail(), account.getCountry(), account.getCity(),
            account.getAddressLine(), account.getLatitude(), account.getLongitude(),
            account.getReviewNote(), account.getProvisionedRefId(),
            uploaded.stream()
                .map(d -> new PartnerDocumentDto(d.getId(), d.getKind().name(),
                    d.getContentType(), d.getUploadedAt()))
                .toList(),
            required, missing,
            editable,
            editable && missing.isEmpty() && missingFields(account).isEmpty(),
            account.getSubmittedAt(), account.getReviewedAt(), account.getCreatedAt());
    }
}
