package com.gojogo.partner.internal;

import com.gojogo.delivery.MerchantProvisioningApi;
import com.gojogo.delivery.MerchantRegistration;
import com.gojogo.dispatch.CourierProvisioningApi;
import com.gojogo.dispatch.DriverProvisioningApi;
import com.gojogo.dispatch.VehicleRef;
import com.gojogo.dispatch.WorkerRegistration;
import com.gojogo.economy.SellerProvisioningApi;
import com.gojogo.economy.SellerRegistration;
import com.gojogo.services.ProviderProvisioningApi;
import com.gojogo.services.ProviderRegistration;
import com.gojogo.kyc.IdentityStatus;
import com.gojogo.kyc.IdentityVerificationApi;
import com.gojogo.media.MediaApi;
import com.gojogo.media.MediaDocumentApi;
import com.gojogo.partner.PartnerReviewed;
import com.gojogo.profile.ProfileApi;
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
import java.util.Optional;
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
 *
 * <p>That last sentence still holds with an IDV vendor in the picture, and it is
 * worth being precise about what changed. Sumsub answers <em>"is this person who
 * they say they are"</em> — a question a machine genuinely answers better than a
 * human squinting at a phone photo. It does not answer <em>"should this business
 * trade on our platform"</em>, which stays a human decision on the same review
 * surface. So a vendor verdict is a precondition for submission, never a
 * substitute for approval.
 */
@Service
class PartnerService {

    private static final Set<PartnerStatus> QUEUE_DEFAULT = EnumSet.of(PartnerStatus.SUBMITTED);

    private final PartnerAccountRepository accounts;
    private final PartnerDocumentRepository documents;
    private final MerchantProvisioningApi merchants;
    private final DriverProvisioningApi drivers;
    private final CourierProvisioningApi couriers;
    private final SellerProvisioningApi sellers;
    private final ProviderProvisioningApi providers;
    private final MediaDocumentApi privateMedia;
    private final MediaApi media;
    private final ProfileApi profiles;
    private final IdentityVerificationApi identity;
    private final VehicleService vehicles;
    private final PartnerStakeService stakes;
    private final ApplicationEventPublisher events;

    PartnerService(PartnerAccountRepository accounts, PartnerDocumentRepository documents,
                   MerchantProvisioningApi merchants, DriverProvisioningApi drivers,
                   CourierProvisioningApi couriers, SellerProvisioningApi sellers,
                   ProviderProvisioningApi providers, MediaDocumentApi privateMedia,
                   MediaApi media, ProfileApi profiles, IdentityVerificationApi identity,
                   VehicleService vehicles, PartnerStakeService stakes,
                   ApplicationEventPublisher events) {
        this.accounts = accounts;
        this.documents = documents;
        this.merchants = merchants;
        this.drivers = drivers;
        this.couriers = couriers;
        this.sellers = sellers;
        this.providers = providers;
        this.privateMedia = privateMedia;
        this.media = media;
        this.profiles = profiles;
        this.identity = identity;
        this.vehicles = vehicles;
        this.stakes = stakes;
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
        // Linking a business profile is an ownership claim, so it goes through
        // the same server-side check that guards acting as one (403 if not theirs).
        UUID businessProfileId = request.businessProfileId() == null ? null
            : profiles.requireActingProfile(me, request.businessProfileId());
        account.apply(request.businessName().trim(), request.category(), request.description(),
            request.logoUrl(), request.contactName(), request.contactPhone(),
            request.contactEmail(), request.country(), request.city(), request.addressLine(),
            request.latitude(), request.longitude(), businessProfileId);
        // The logo is ordinary public media (it ends up on the storefront), so
        // it goes through the normal reference tracking; the KYC papers do not.
        // (Collections.singletonList, not List.of — the logo is optional.)
        media.markReferenced(Collections.singletonList(request.logoUrl()));
        return toDto(account);
    }

    /**
     * Records the number printed on a driving licence.
     *
     * <p>Separate from {@link #save} because that is a whole-object upsert and
     * this is one field: an app calling save to record a number would blank the
     * address an operator typed. It is also the only part of the licence the
     * applicant types rather than photographs, which is why it can be written
     * before either photo arrives.
     */
    @Transactional
    PartnerAccountDto saveDriverLicense(UUID me, UUID accountId, SaveDriverLicenseRequest request) {
        PartnerAccount account = requireEditable(me, accountId);
        account.applyDriverLicenseNumber(request.number());
        return toDto(account);
    }

    /** Somewhere private to put one paper. Nothing is recorded until the client
     *  comes back with the key, so an abandoned upload leaves no row. */
    @Transactional(readOnly = true)
    DocumentUploadResponse presignDocument(UUID me, UUID accountId, DocumentUploadRequest request) {
        return presignDocumentFor(requireEditable(me, accountId), request);
    }

    private DocumentUploadResponse presignDocumentFor(PartnerAccount account,
                                                      DocumentUploadRequest request) {
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
        return attachDocumentTo(requireEditable(me, accountId), request);
    }

    private PartnerAccountDto attachDocumentTo(PartnerAccount account, AttachDocumentRequest request) {
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
        return deleteDocumentFrom(requireEditable(me, accountId), documentId);
    }

    private PartnerAccountDto deleteDocumentFrom(PartnerAccount account, UUID documentId) {
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
        return submitAccount(requireEditable(me, accountId), true);
    }

    /**
     * @param bySelf whether the applicant is submitting their own application,
     *               which only changes how a failure is worded — an operator
     *               reading "verify your identity" would reasonably think it
     *               meant theirs
     */
    private PartnerAccountDto submitAccount(PartnerAccount account, boolean bySelf) {
        List<String> missing = missingFields(account);
        if (!missing.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Still missing: " + String.join(", ", missing));
        }
        requireVerifiedIdentity(account, bySelf);
        Set<DocumentKind> uploaded = uploadedKinds(account.getId());
        Set<DocumentKind> required = new TreeSet<>(requiredDocuments(account));
        required.removeAll(uploaded);
        if (!required.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Upload your " + required.stream().map(PartnerService::label)
                    .collect(Collectors.joining(", ")));
        }
        // The stake is a precondition for submission, not for approval (SPECS
        // §4) — staking is what funds verification, so it happens before a
        // human spends time on this rather than after.
        if (stakes.isStakeRequired(account.getKind()) && !account.hasLiveStake()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Pay your stake before submitting");
        }
        vehicles.whatBlocksSubmission(account).ifPresent(blocker -> {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                (bySelf ? "Before you submit, " : "Before this can be submitted, ") + blocker);
        });
        boolean firstSubmission = account.getSubmittedAt() == null;
        account.submit(OffsetDateTime.now());
        // Charged after the state change so a submission that fails a check
        // above never costs anybody anything.
        stakes.chargeKycFee(account, firstSubmission);
        return toDto(account);
    }

    /**
     * Refuses to queue an application from someone who hasn't proved who they
     * are — the vendor-backed half of KYC.
     *
     * <p>Checked at submission rather than approval on purpose: a reviewer's
     * time is the scarce thing here, and an application that cannot possibly be
     * approved should never reach their queue. It is also the applicant's
     * interest — they find out at the moment they can still do something about
     * it, instead of days later.
     *
     * <p>The gate is scoped to the <em>owner</em>, not the business: identity is
     * a fact about a person, so someone verified as a courier does not verify
     * again to open a restaurant.
     *
     * <p><b>It applies to the admin-side create too</b>, and that is not an
     * oversight. An operator filing an application on a merchant's behalf can
     * type their address and upload their licence, but nobody can pass a liveness
     * check for somebody else — that is the whole thing an IDV vendor is for. So
     * the owner verifies in the app, once, and the operator's create waits on it.
     */
    private void requireVerifiedIdentity(PartnerAccount account, boolean bySelf) {
        if (!identity.isConfigured()) return;
        IdentityStatus status = identity.statusOf(account.getUserId()).status();
        if (status == IdentityStatus.VERIFIED) return;
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, bySelf
            ? switch (status) {
                case PENDING, IN_REVIEW -> "We're still checking your ID — you can "
                    + "submit as soon as that's done";
                case RESUBMISSION_REQUESTED -> "Your ID check needs another go before "
                    + "you can submit";
                case REJECTED -> "Your ID check didn't pass, so this application "
                    + "can't be submitted";
                default -> "Verify your identity before submitting";
            }
            : "The owner hasn't passed their ID check yet (" + status + ") — they "
                + "verify in the app, and nobody can do it for them");
    }

    /**
     * What this application still needs on paper — which depends on whether an
     * IDV vendor is answering the identity half (see
     * {@link PartnerKind#requiredDocuments(boolean)}) and, for a driver, on what
     * they drive.
     *
     * <p>The licence is added here rather than in the kind's own list because
     * the kind cannot answer it: {@code DRIVER} covers a car, a motorcycle and a
     * trottinette, and only the first two are something you need a licence for.
     */
    private Set<DocumentKind> requiredDocuments(PartnerAccount account) {
        Set<DocumentKind> required = account.getKind().requiredDocuments(identity.isConfigured());
        if (vehicles.isDriverLicenseRequired(account)) {
            required.add(DocumentKind.DRIVER_LICENSE_FRONT);
            required.add(DocumentKind.DRIVER_LICENSE_BACK);
        }
        return required;
    }

    // MARK: The stake and the vehicles

    /**
     * Locks the stake. A 402 with the shortfall when the wallet won't cover it,
     * so the app offers a top-up rather than a dead end.
     */
    @Transactional
    PartnerAccountDto payStake(UUID me, UUID accountId) {
        PartnerAccount account = requireEditable(me, accountId);
        if (!stakes.isStakeRequired(account.getKind())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                account.getKind() + " partners don't stake anything");
        }
        stakes.payStake(account);
        return toDto(account);
    }

    @Transactional
    VehicleDto saveVehicle(UUID me, UUID accountId, UUID vehicleId,
                           SaveVehicleRequest request) {
        return vehicles.save(requireEditable(me, accountId), vehicleId, request);
    }

    @Transactional
    VehicleDto activateVehicle(UUID me, UUID accountId, UUID vehicleId) {
        // Deliberately not gated on the application being editable: changing
        // which car you're driving is a thing an approved driver does every
        // week, and it is the one field dispatch reads.
        PartnerAccount account = require(me, accountId);
        VehicleDto activated = vehicles.activate(account, vehicleId);
        pushVehicleToDispatch(account);
        return activated;
    }

    @Transactional
    void retireVehicle(UUID me, UUID accountId, UUID vehicleId) {
        vehicles.retire(require(me, accountId), vehicleId);
    }

    @Transactional(readOnly = true)
    DocumentUploadResponse presignVehicleDocument(UUID me, UUID accountId, UUID vehicleId,
                                                  DocumentUploadRequest request) {
        return vehicles.presignDocument(require(me, accountId), vehicleId, request);
    }

    @Transactional
    VehicleDto attachVehicleDocument(UUID me, UUID accountId, UUID vehicleId,
                                     AttachDocumentRequest request) {
        return vehicles.attachDocument(require(me, accountId), vehicleId, request);
    }

    /** Flagging the vehicle somebody is driving takes them off the road, so the
     *  partner is suspended in the same breath — a flagged car that keeps
     *  receiving work is a flag that did nothing. */
    @Transactional
    ReviewApplicationDto reviewVehicle(UUID accountId, UUID vehicleId, boolean approved,
                                       String note) {
        PartnerAccount account = requireExisting(accountId);
        VehicleDto reviewed = vehicles.review(vehicleId, approved, note);
        if (!approved && reviewed.active() && account.getStatus() == PartnerStatus.APPROVED) {
            suspendForVehicle(account, note);
        }
        // An approval is the moment a car becomes one dispatch may send work in,
        // so the snapshot a rider identifies it by goes down with the verdict.
        pushVehicleToDispatch(account);
        return toReview(account);
    }

    /**
     * Takes a partner off the road because their vehicle's papers lapsed.
     *
     * <p>Separate from {@link #suspend} because it is not a judgement about the
     * person: the note says what expired, and re-uploading a certificate is what
     * fixes it. It still goes through the same status, because dispatch has one
     * idea of "not receiving work".
     */
    @Transactional
    void suspendForVehicle(PartnerAccount account, String note) {
        if (account.getStatus() != PartnerStatus.APPROVED) return;
        account.suspend(note == null || note.isBlank()
            ? "Your vehicle's papers are out of date" : note, OffsetDateTime.now());
        setProvisionedSuspended(account, true);
        setBusinessVerified(account, false);
        publish(account);
    }

    @Transactional(readOnly = true)
    Optional<PartnerAccount> accountOfVehicleOwner(UUID accountId) {
        return accounts.findById(accountId);
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
        // Somebody who has pulled their application is not going to work here
        // for now, and their money should not sit locked while they think about
        // it. Paying again is what resubmitting costs.
        stakes.releaseStake(account);
        return toDto(account);
    }

    // MARK: The reviewer's side

    /**
     * Creates or edits an application <em>on behalf of</em> a merchant — the
     * operator's own path, since every applicant endpoint is scoped to the
     * caller and restaurants are created in the admin tool (2026-07-27).
     *
     * <p>Deliberately the same {@link #save} the applicant would have used: one
     * write path, one set of rules. What the admin gets is the right to name
     * whose application it is.
     */
    @Transactional
    PartnerAccountDto adminSave(UUID ownerId, SavePartnerApplicationRequest request) {
        return save(ownerId, request);
    }

    /** Hands an application the operator filled in to the queue, so the same
     *  completeness rules apply to an admin-typed form as to a merchant's. */
    @Transactional
    PartnerAccountDto adminSubmit(UUID accountId) {
        PartnerAccount account = requireExisting(accountId);
        if (!account.getStatus().isEditable()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, editBlockedMessage(account));
        }
        return submitAccount(account, false);
    }

    @Transactional(readOnly = true)
    DocumentUploadResponse adminPresignDocument(UUID accountId, DocumentUploadRequest request) {
        return presignDocumentFor(requireEditableExisting(accountId), request);
    }

    @Transactional
    ReviewApplicationDto adminAttachDocument(UUID accountId, AttachDocumentRequest request) {
        PartnerAccount account = requireEditableExisting(accountId);
        attachDocumentTo(account, request);
        return toReview(account);
    }

    @Transactional
    ReviewApplicationDto adminDeleteDocument(UUID accountId, UUID documentId) {
        PartnerAccount account = requireEditableExisting(accountId);
        deleteDocumentFrom(account, documentId);
        return toReview(account);
    }

    /**
     * A fresh signed link to one paper. The queue payload carries links too,
     * but they expire in ten minutes — a console left open on a long review
     * needs to be able to ask again without re-reading the whole application.
     */
    @Transactional(readOnly = true)
    ReviewDocumentDto adminDocument(UUID accountId, UUID documentId) {
        PartnerAccount account = requireExisting(accountId);
        PartnerDocument document = documents.findById(documentId)
            .filter(d -> d.getAccountId().equals(account.getId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such document"));
        return toReviewDocument(document);
    }

    @Transactional(readOnly = true)
    List<ReviewApplicationDto> queue(String statusName, String kindName, int limit) {
        Collection<PartnerStatus> statuses = statusName == null || statusName.isBlank()
            ? QUEUE_DEFAULT
            : List.of(parseStatus(statusName));
        PartnerKind kind = kindName == null || kindName.isBlank() ? null : parseKind(kindName);
        List<PartnerAccount> page = accounts.findByStatusInOrderBySubmittedAtAscCreatedAtAsc(
            statuses, PageRequest.of(0, Math.clamp(limit, 1, 100))).stream()
            .filter(a -> kind == null || a.getKind() == kind)
            .toList();
        Map<UUID, List<PartnerDocument>> byAccount = documents
            .findByAccountIdInOrderByKindAsc(page.stream().map(PartnerAccount::getId).toList())
            .stream().collect(Collectors.groupingBy(PartnerDocument::getAccountId));
        return page.stream()
            .map(a -> new ReviewApplicationDto(toDto(a), byAccount
                .getOrDefault(a.getId(), List.of()).stream()
                .map(this::toReviewDocument)
                .toList(),
                vehicles.forReview(a.getId())))
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
            setProvisionedSuspended(account, false);
            setBusinessVerified(account, true);
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
                account.getKind() + " partners can't be provisioned yet");
        }
        account.approve(provision(account), OffsetDateTime.now());
        // A driver spends a token to accept a trip (Phase 3 M4), and a driver
        // with none is filtered out of every search — silently, which is correct
        // and invisible. So an approval hands over a first handful, or it hands
        // over a Driver Mode where nothing ever arrives.
        stakes.grantWelcomeTokens(account);
        // The verified badge is the KYC review's, not the owner's: this is the
        // only place it is granted (SPECS.md §8 — no paid verification).
        setBusinessVerified(account, true);
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
        // The stake goes back on a rejection, less whatever the ID check cost.
        // Keeping it would make refusing somebody profitable, which is not a
        // pressure a review queue should be under.
        stakes.releaseStake(account);
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
        setProvisionedSuspended(account, true);
        setBusinessVerified(account, false);
        publish(account);
        return toReview(account);
    }

    /**
     * Puts an approved partner where their kind belongs — the one place this
     * module names a vertical, and it names each of them exactly once.
     *
     * <p>Every branch is idempotent on the vertical's side, so a retried approval
     * or a reviewer who clicks twice cannot leave somebody with two restaurants
     * or two driver registrations.
     */
    private UUID provision(PartnerAccount account) {
        return switch (account.getKind()) {
            case RESTAURANT -> merchants.provisionMerchant(new MerchantRegistration(
                account.getUserId(), account.getBusinessName(), account.getCategory(),
                account.getLogoUrl(), account.getLatitude(), account.getLongitude()));
            case DRIVER -> drivers.provisionDriver(workerRegistration(account));
            case COURIER -> couriers.provisionCourier(workerRegistration(account));
            case SELLER -> sellers.provisionSeller(new SellerRegistration(
                account.getUserId(), account.getBusinessName(), account.getLogoUrl()));
            case SERVICE_PROVIDER -> providers.provisionProvider(new ProviderRegistration(
                account.getUserId(), account.getBusinessName(), account.getLogoUrl()));
        };
    }

    /**
     * What dispatch matches this worker on is the <b>active vehicle's</b>
     * category — the one they said they are driving, not the one they own most
     * of. A courier with no vehicle at all passes null, and dispatch fills in the
     * default for the kind, which is the honest answer for somebody on a bicycle.
     */
    private WorkerRegistration workerRegistration(PartnerAccount account) {
        return new WorkerRegistration(account.getUserId(), account.getId(),
            vehicles.activeSnapshot(account.getId()), account.getCity());
    }

    /**
     * Tells dispatch the driver switched cars.
     *
     * <p>The description and plate go down with the category because a rider on
     * a kerb identifies the car by those two things, and they live here — in a
     * vertical — so pushing them is the only direction that does not make
     * {@code travel} read across at somebody else's tables.
     *
     * <p>Only for a provisioned partner: before an approval there is no registry
     * row, and after a suspension there is one that must not receive work anyway.
     */
    void pushVehicleToDispatch(PartnerAccount account) {
        UUID refId = account.getProvisionedRefId();
        if (refId == null) return;
        VehicleRef active = vehicles.activeSnapshot(account.getId());
        switch (account.getKind()) {
            case DRIVER -> drivers.setDriverVehicle(refId, active);
            case COURIER -> couriers.setCourierVehicle(refId, active);
            case RESTAURANT, SELLER, SERVICE_PROVIDER -> { }
        }
    }

    private void setProvisionedSuspended(PartnerAccount account, boolean suspended) {
        UUID refId = account.getProvisionedRefId();
        // An application suspended before it was ever provisioned has nothing to
        // switch off — the status on the row is the whole block.
        if (refId == null) return;
        switch (account.getKind()) {
            case RESTAURANT -> merchants.setMerchantSuspended(refId, suspended);
            case DRIVER -> drivers.setDriverSuspended(refId, suspended);
            case COURIER -> couriers.setCourierSuspended(refId, suspended);
            case SELLER -> sellers.setSellerSuspended(refId, suspended);
            case SERVICE_PROVIDER -> providers.setProviderSuspended(refId, suspended);
        }
    }

    private void setBusinessVerified(PartnerAccount account, boolean verified) {
        if (account.getBusinessProfileId() != null) {
            profiles.setBusinessVerified(account.getBusinessProfileId(), verified);
        }
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

    /** The admin twin of {@link #requireEditable}: any application, but still
     *  only while it is open — an approved partner's details are theirs. */
    private PartnerAccount requireEditableExisting(UUID accountId) {
        PartnerAccount account = requireExisting(accountId);
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

    /**
     * The facts a reviewer can't work without. Documents are checked separately
     * so the two failures read differently to the applicant.
     *
     * <p>Only a business is asked for the business half, and this is the second
     * half of why the driver app's Submit button never worked. A driver has no
     * cuisine category, no trading address and no shop phone — they are a person
     * with a licence and a car, checked elsewhere — but every one of those was
     * demanded of them anyway, and the flow has no field for a single one. An
     * application that cannot be completed by any sequence of taps is not a
     * stricter check; it is a wall.
     *
     * <p>What is left for a driver is their name, which the app fills in from
     * the account, and the number off their licence — the one thing on that card
     * they type rather than photograph, and the thing a reviewer reads the
     * photograph against. Everything else weighed about them — the identity
     * verdict, the licence photos, the vehicle and its papers — is checked
     * further down {@code submitAccount}, and reaching them by phone is what the
     * account itself is for.
     */
    private List<String> missingFields(PartnerAccount account) {
        List<String> missing = new ArrayList<>();
        if (account.getBusinessName().isBlank()) missing.add("business name");
        if (account.getContactName().isBlank()) missing.add("contact name");
        if (vehicles.isDriverLicenseRequired(account)
            && account.getDriverLicenseNumber().isBlank()) {
            missing.add("licence number");
        }
        if (account.getKind() != PartnerKind.RESTAURANT) return missing;
        if (account.getContactPhone().isBlank()) missing.add("contact phone");
        if (account.getCategory().isBlank()) missing.add("category");
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
        return switch (kind) {
            case DRIVER_LICENSE_FRONT -> "driving licence (front)";
            case DRIVER_LICENSE_BACK -> "driving licence (back)";
            default -> {
                String words = kind.name().replace('_', ' ').toLowerCase();
                yield kind.name().startsWith("ID") ? "ID" + words.substring(2) : words;
            }
        };
    }

    // MARK: Mapping

    private ReviewApplicationDto toReview(PartnerAccount account) {
        return new ReviewApplicationDto(toDto(account),
            documents.findByAccountIdOrderByKindAsc(account.getId()).stream()
                .map(this::toReviewDocument)
                .toList(),
            vehicles.forReview(account.getId()));
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
        Set<DocumentKind> requiredKinds = requiredDocuments(account);
        List<DocumentKind> missingKinds = requiredKinds.stream()
            .filter(kind -> !have.contains(kind)).toList();
        List<String> required = requiredKinds.stream().map(Enum::name).toList();
        List<String> missing = missingKinds.stream().map(Enum::name).toList();
        boolean editable = account.getStatus().isEditable();
        // The identity check belongs to the person, so it is read per account
        // rather than stored on one: the same verdict decorates every
        // application this owner has.
        IdentityVerificationApi.IdentityCheck check = identity.statusOf(account.getUserId());
        boolean identityRequired = identity.isConfigured();
        boolean identityDone = !identityRequired
            || check.status() == IdentityStatus.VERIFIED;
        // Everything the submit path would refuse on, answered in advance — so
        // the app renders one checklist rather than discovering the rules one
        // 400 at a time.
        boolean stakeRequired = stakes.isStakeRequired(account.getKind());
        boolean stakeDone = !stakeRequired || account.hasLiveStake();
        String vehicleBlocker = vehicles.whatBlocksSubmission(account).orElse(null);
        // One sentence, in the order the applicant meets these: the stake page,
        // then the form, then the papers, then the car. Documents and fields
        // used to be left out of it entirely — so a driver whose only problem
        // was an unuploaded licence got a dead Submit button and no reason for
        // it, which is exactly how a checklist turns into a bug report.
        List<String> missingHere = missingFields(account);
        String blocker = !stakeDone ? "pay your stake"
            : !missingHere.isEmpty() ? "add your " + String.join(", ", missingHere)
            : !missingKinds.isEmpty() ? "upload your " + missingKinds.stream()
                .map(PartnerService::label).collect(Collectors.joining(", "))
            : vehicleBlocker;
        return new PartnerAccountDto(
            account.getId(), account.getKind().name(), account.getStatus().name(),
            account.getBusinessName(), account.getBusinessProfileId(),
            account.getCategory(), account.getDescription(),
            account.getLogoUrl(), account.getContactName(), account.getContactPhone(),
            account.getContactEmail(), account.getCountry(), account.getCity(),
            account.getAddressLine(), account.getLatitude(), account.getLongitude(),
            account.getDriverLicenseNumber(),
            account.getReviewNote(), account.getProvisionedRefId(),
            uploaded.stream()
                .map(d -> new PartnerDocumentDto(d.getId(), d.getKind().name(),
                    d.getContentType(), d.getUploadedAt()))
                .toList(),
            required, missing,
            identityRequired, check.status().name(), check.reason(),
            stakes.statusOf(account), vehicles.forAccount(account.getId()),
            vehicles.isVehicleRequired(account.getKind()), blocker,
            editable,
            editable && identityDone && blocker == null,
            account.getSubmittedAt(), account.getReviewedAt(), account.getCreatedAt());
    }
}
