package com.gojogo.partner.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.media.MediaApi;
import com.gojogo.media.MediaDocumentApi;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The car, and the papers a reviewer decides about it from.
 *
 * <p>Three rules do most of the work here, and each of them is the answer to a
 * way this could be gamed or simply get out of date:
 *
 * <ul>
 *   <li><b>Editing a plate un-approves the vehicle.</b> A driver who changes the
 *       registration on a car a reviewer already looked at has described a
 *       different car; keeping the old verdict is exactly the shape of the fraud
 *       this check exists to catch. Changing the colour is not, so only the
 *       identifying fields reset it.</li>
 *   <li><b>Exactly one vehicle is active</b>, enforced by a partial unique index
 *       rather than by this class — "activate this one" is two writes, and only
 *       the database can hold the invariant between them.</li>
 *   <li><b>Papers expire, and the vehicle knows when.</b> A registration that
 *       lapsed in March is not a registration, and nothing else in the system
 *       would ever have noticed.</li>
 * </ul>
 */
@Service
class VehicleService {

    private static final Set<VehicleState> ROADWORTHY =
        EnumSet.of(VehicleState.APPROVED, VehicleState.COMMUNITY_VERIFIED);

    private final VehicleRepository vehicles;
    private final VehicleDocumentRepository documents;
    private final VehiclePhotoRepository photos;
    private final MediaDocumentApi privateMedia;
    private final MediaApi media;
    private final ConfigApi config;

    VehicleService(VehicleRepository vehicles, VehicleDocumentRepository documents,
                   VehiclePhotoRepository photos, MediaDocumentApi privateMedia,
                   MediaApi media, ConfigApi config) {
        this.vehicles = vehicles;
        this.documents = documents;
        this.photos = photos;
        this.privateMedia = privateMedia;
        this.media = media;
        this.config = config;
    }

    // MARK: Reads

    @Transactional(readOnly = true)
    List<VehicleDto> forAccount(UUID accountId) {
        return vehicles.findByAccountIdOrderByCreatedAtAsc(accountId).stream()
            .map(this::toDto)
            .toList();
    }

    /** The queue's batched read — one round trip for a page of applications
     *  rather than one per vehicle. */
    @Transactional(readOnly = true)
    Map<UUID, List<VehicleDto>> forAccounts(List<UUID> accountIds) {
        if (accountIds.isEmpty()) return Map.of();
        return vehicles.findByAccountIdInOrderByCreatedAtAsc(accountIds).stream()
            .collect(Collectors.groupingBy(Vehicle::getAccountId,
                Collectors.mapping(this::toDto, Collectors.toList())));
    }

    Optional<Vehicle> activeVehicle(UUID accountId) {
        return vehicles.findByAccountIdAndActiveTrue(accountId);
    }

    /**
     * Why this application cannot be submitted on the vehicle's account, or
     * empty if it can.
     *
     * <p>Returned as a message rather than thrown so the caller can fold it in
     * with the document and identity checks and the applicant sees one list of
     * what is missing, not the first thing that failed.
     */
    Optional<String> whatBlocksSubmission(PartnerAccount account) {
        if (!isVehicleRequired(account.getKind())) return Optional.empty();
        Vehicle active = activeVehicle(account.getId()).orElse(null);
        if (active == null) {
            return Optional.of("add a vehicle and set it as the one you're driving");
        }
        if (active.getState() == VehicleState.FLAGGED) {
            return Optional.of("your vehicle is flagged"
                + (active.getReviewNote() == null ? "" : " — " + active.getReviewNote()));
        }
        if (active.getPlate().isBlank()) {
            return Optional.of("add your number plate");
        }
        Set<VehicleDocumentKind> have = documents
            .findByVehicleIdOrderByKindAsc(active.getId()).stream()
            .map(VehicleDocument::getKind)
            .collect(Collectors.toCollection(() -> EnumSet.noneOf(VehicleDocumentKind.class)));
        Set<VehicleDocumentKind> missing = EnumSet.allOf(VehicleDocumentKind.class);
        missing.removeAll(have);
        if (!missing.isEmpty()) {
            return Optional.of("upload your vehicle's " + missing.stream()
                .map(k -> k.name().toLowerCase())
                .collect(Collectors.joining(" and ")));
        }
        if (active.getRegistrationExpiresOn() == null || active.getInsuranceExpiresOn() == null) {
            return Optional.of("add the expiry dates on your registration and insurance");
        }
        if (active.papersExpiredOn(LocalDate.now())) {
            return Optional.of("your vehicle's papers have expired");
        }
        return Optional.empty();
    }

    /**
     * Whether a partner of this kind needs a vehicle at all.
     *
     * <p>Drivers do and couriers do not, and that asymmetry is deliberate: a
     * courier on a bicycle has no registration and no insurance certificate to
     * show, and demanding one would exclude the most common way this job is
     * actually done. A courier who <em>does</em> register a scooter still gets it
     * reviewed — it is optional, not ignored.
     */
    boolean isVehicleRequired(PartnerKind kind) {
        return kind == PartnerKind.DRIVER && config.flag("partner.vehicle.required.driver", true);
    }

    /** What dispatch should match this worker on: the active vehicle's category,
     *  or null to let dispatch fall back to the default for the kind. */
    Optional<VehicleCategory> activeCategory(UUID accountId) {
        return activeVehicle(accountId)
            .filter(v -> v.getState() != VehicleState.FLAGGED)
            .flatMap(v -> parseCategoryQuietly(v.getCategory()));
    }

    // MARK: Writes (the applicant's own, and the operator's — same path)

    @Transactional
    VehicleDto save(PartnerAccount account, UUID vehicleId, SaveVehicleRequest request) {
        VehicleCategory category = parseCategory(request.category());
        Vehicle vehicle = vehicleId == null
            ? vehicles.save(new Vehicle(account.getId(), account.getUserId(), category.name()))
            : require(account, vehicleId);
        if (vehicle.getState() == VehicleState.RETIRED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That vehicle has been retired");
        }
        vehicle.apply(category.name(), request.make(), request.model(), request.year(),
            request.color(), request.plate(), request.region(),
            parseDate(request.registrationExpiresOn(), "registration"),
            parseDate(request.insuranceExpiresOn(), "insurance"));
        // The first vehicle somebody adds is the one they're driving. Making
        // them say so separately is a step whose only outcome is an application
        // that can't be submitted for a reason nobody can see.
        if (vehicleId == null && activeVehicle(account.getId()).isEmpty()) {
            vehicle.setActive(true);
        }
        if (request.photoUrls() != null) {
            replacePhotos(vehicle, request.photoUrls());
        }
        vehicles.flush();
        return toDto(vehicle);
    }

    /**
     * Switches which vehicle is being driven.
     *
     * <p>Deactivate-then-activate in one transaction, and the partial unique
     * index is what makes the pair safe: two concurrent activations cannot both
     * land, and the loser is a plain conflict rather than a driver with two
     * active cars and a dispatch category picked at random.
     */
    @Transactional
    VehicleDto activate(PartnerAccount account, UUID vehicleId) {
        Vehicle vehicle = require(account, vehicleId);
        if (vehicle.getState() == VehicleState.RETIRED
            || vehicle.getState() == VehicleState.FLAGGED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "That vehicle can't be driven — it's " + vehicle.getState().name().toLowerCase());
        }
        activeVehicle(account.getId())
            .filter(current -> !current.getId().equals(vehicleId))
            .ifPresent(current -> current.setActive(false));
        vehicles.flush();
        vehicle.setActive(true);
        vehicles.flush();
        return toDto(vehicle);
    }

    @Transactional
    void retire(PartnerAccount account, UUID vehicleId) {
        Vehicle vehicle = require(account, vehicleId);
        vehicle.retire();
        // The papers go with it: nothing else sweeps the private prefix, and a
        // scrapped car's insurance certificate is not something to keep.
        documents.findByVehicleIdOrderByKindAsc(vehicleId).forEach(document -> {
            privateMedia.deleteDocument(document.getObjectKey());
            documents.delete(document);
        });
        vehicles.flush();
    }

    @Transactional(readOnly = true)
    DocumentUploadResponse presignDocument(PartnerAccount account, UUID vehicleId,
                                           DocumentUploadRequest request) {
        require(account, vehicleId);
        parseDocumentKind(request.kind());
        MediaDocumentApi.DocumentUpload upload = privateMedia.presignDocumentUpload(
            account.getUserId(), "partner", request.contentType());
        return new DocumentUploadResponse(upload.uploadUrl(), upload.objectKey(),
            upload.contentType(), upload.expiresSeconds());
    }

    @Transactional
    VehicleDto attachDocument(PartnerAccount account, UUID vehicleId,
                              AttachDocumentRequest request) {
        Vehicle vehicle = require(account, vehicleId);
        VehicleDocumentKind kind = parseDocumentKind(request.kind());
        // The key must be one we minted for this applicant, or an attach could
        // point a reviewer at any object in the bucket.
        String expectedPrefix = "private/partner/" + account.getUserId() + "/";
        if (!request.objectKey().startsWith(expectedPrefix)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "That upload isn't yours");
        }
        documents.findByVehicleIdAndKind(vehicleId, kind).ifPresentOrElse(existing -> {
            String previous = existing.getObjectKey();
            existing.replaceWith(request.objectKey(), request.contentType());
            if (!previous.equals(request.objectKey())) privateMedia.deleteDocument(previous);
        }, () -> documents.save(new VehicleDocument(vehicleId, kind,
            request.objectKey(), request.contentType())));
        // A fresh paper on a flagged vehicle is the driver answering the flag,
        // so it goes back into the queue rather than waiting for an operator to
        // notice. It does not approve itself.
        vehicle.resubmit();
        vehicles.flush();
        return toDto(vehicle);
    }

    // MARK: The reviewer's side

    @Transactional
    VehicleDto review(UUID vehicleId, boolean approved, String note) {
        Vehicle vehicle = vehicles.findById(vehicleId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such vehicle"));
        if (approved) {
            vehicle.approve(note);
        } else {
            vehicle.flag(note);
        }
        vehicles.flush();
        return toDto(vehicle);
    }

    /** One paper, freshly signed — a console left open past the ten-minute
     *  expiry needs to be able to ask again. */
    @Transactional(readOnly = true)
    ReviewDocumentDto document(UUID vehicleId, UUID documentId) {
        VehicleDocument document = documents.findById(documentId)
            .filter(d -> d.getVehicleId().equals(vehicleId))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such document"));
        return toReviewDocument(document);
    }

    // MARK: The expiry sweep

    @Transactional(readOnly = true)
    List<UUID> lapsedVehicleIds(int batch) {
        long grace = Math.max(0, config.number("partner.vehicle.expiry.grace.days", 7));
        LocalDate cutoff = LocalDate.now().minusDays(grace);
        return vehicles.lapsed(ROADWORTHY, cutoff,
                org.springframework.data.domain.PageRequest.of(0, batch)).stream()
            .map(Vehicle::getId)
            .toList();
    }

    /**
     * Flags one lapsed vehicle and says whether that took its driver off the
     * road — which is what the caller turns into a suspension.
     *
     * <p>Re-read and re-checked inside the transaction rather than trusted from
     * the sweep's list, because a driver may have uploaded a new certificate in
     * the seconds between.
     */
    @Transactional
    boolean flagIfStillLapsed(UUID vehicleId) {
        Vehicle vehicle = vehicles.findById(vehicleId).orElse(null);
        if (vehicle == null || !vehicle.getState().isRoadworthy()) return false;
        long grace = Math.max(0, config.number("partner.vehicle.expiry.grace.days", 7));
        if (!vehicle.papersExpiredOn(LocalDate.now().minusDays(grace))) return false;
        boolean wasActive = vehicle.isActive();
        vehicle.flag("Registration or insurance expired on " + vehicle.papersValidUntil());
        vehicles.flush();
        return wasActive;
    }

    // MARK: Helpers

    private void replacePhotos(Vehicle vehicle, List<String> urls) {
        int max = (int) Math.clamp(config.number("partner.vehicle.photos.max", 5), 1, 20);
        List<String> kept = new ArrayList<>(new LinkedHashSet<>(urls.stream()
            .filter(url -> url != null && !url.isBlank())
            .map(String::trim)
            .toList()));
        if (kept.size() > max) kept = kept.subList(0, max);
        photos.deleteByVehicleId(vehicle.getId());
        photos.flush();
        for (int i = 0; i < kept.size(); i++) {
            photos.save(new VehiclePhoto(vehicle.getId(), kept.get(i), i));
        }
        // Ordinary public media, so it goes through the normal reference
        // tracking that keeps the orphan sweep off it. The papers do not.
        media.markReferenced(kept);
    }

    /** 404 rather than 403 for another application's vehicle — don't confirm it
     *  exists. */
    private Vehicle require(PartnerAccount account, UUID vehicleId) {
        return vehicles.findById(vehicleId)
            .filter(v -> v.getAccountId().equals(account.getId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such vehicle"));
    }

    private static VehicleCategory parseCategory(String name) {
        return parseCategoryQuietly(name).orElseThrow(() ->
            new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown vehicle category; use one of "
                    + EnumSet.allOf(VehicleCategory.class)));
    }

    /** A stored value this build no longer knows is not an error on a read —
     *  a row outlives the enum that wrote it. */
    private static Optional<VehicleCategory> parseCategoryQuietly(String name) {
        if (name == null) return Optional.empty();
        String wanted = name.trim().toUpperCase();
        for (VehicleCategory candidate : VehicleCategory.values()) {
            if (candidate.name().equals(wanted)) return Optional.of(candidate);
        }
        return Optional.empty();
    }

    private static VehicleDocumentKind parseDocumentKind(String name) {
        try {
            return VehicleDocumentKind.valueOf(name.trim().toUpperCase());
        } catch (RuntimeException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown document kind; use one of "
                    + EnumSet.allOf(VehicleDocumentKind.class));
        }
    }

    private static LocalDate parseDate(String value, String what) {
        if (value == null || value.isBlank()) return null;
        try {
            return LocalDate.parse(value.trim());
        } catch (RuntimeException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "The " + what + " expiry date should look like 2027-04-30");
        }
    }

    // MARK: Mapping

    private VehicleDto toDto(Vehicle vehicle) {
        List<VehicleDocument> papers = documents.findByVehicleIdOrderByKindAsc(vehicle.getId());
        Set<VehicleDocumentKind> have = papers.stream().map(VehicleDocument::getKind)
            .collect(Collectors.toCollection(() -> EnumSet.noneOf(VehicleDocumentKind.class)));
        Set<VehicleDocumentKind> missing = EnumSet.allOf(VehicleDocumentKind.class);
        missing.removeAll(have);
        return new VehicleDto(vehicle.getId(), vehicle.getCategory(), vehicle.getMake(),
            vehicle.getModel(), vehicle.getYear(), vehicle.getColor(), vehicle.getPlate(),
            vehicle.getRegion(), vehicle.getState().name(), vehicle.isActive(),
            vehicle.getRegistrationExpiresOn() == null ? null
                : vehicle.getRegistrationExpiresOn().toString(),
            vehicle.getInsuranceExpiresOn() == null ? null
                : vehicle.getInsuranceExpiresOn().toString(),
            vehicle.papersExpiredOn(LocalDate.now()),
            vehicle.getReviewNote(),
            photos.findByVehicleIdOrderBySortOrderAsc(vehicle.getId()).stream()
                .map(VehiclePhoto::getUrl).toList(),
            papers.stream()
                .map(d -> new PartnerDocumentDto(d.getId(), d.getKind().name(),
                    d.getContentType(), d.getUploadedAt()))
                .toList(),
            missing.stream().map(Enum::name).toList(),
            vehicle.getCreatedAt());
    }

    /** The reviewer's view: the same vehicle, plus links to its papers. */
    @Transactional(readOnly = true)
    List<ReviewVehicleDto> forReview(UUID accountId) {
        return vehicles.findByAccountIdOrderByCreatedAtAsc(accountId).stream()
            .map(v -> new ReviewVehicleDto(toDto(v),
                documents.findByVehicleIdOrderByKindAsc(v.getId()).stream()
                    .map(this::toReviewDocument)
                    .toList()))
            .toList();
    }

    private ReviewDocumentDto toReviewDocument(VehicleDocument document) {
        return new ReviewDocumentDto(document.getId(), document.getKind().name(),
            document.getContentType(), privateMedia.presignDocumentRead(document.getObjectKey()),
            document.getUploadedAt());
    }
}
