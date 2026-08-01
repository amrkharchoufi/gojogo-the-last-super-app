package com.gojogo.partner.internal;

import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * The applicant's endpoints. Everything here is scoped to the caller's own
 * application; the review side lives in {@link PartnerAdminController}.
 */
@RestController
class PartnerController {

    private final PartnerService partners;
    private final PartnerCurrentProfile current;

    PartnerController(PartnerService partners, PartnerCurrentProfile current) {
        this.partners = partners;
        this.current = current;
    }

    /** {@code {"account": null}} until they've applied — the app's gate. */
    @GetMapping("/v1/partner/me")
    MyPartnerResponse mine(@AuthenticationPrincipal Jwt jwt,
                           @RequestParam(defaultValue = "RESTAURANT") String kind) {
        return partners.mine(current.require(jwt).id(), kind);
    }

    /** Create or edit — one upsert, since there is at most one application per
     *  person per kind and the client shouldn't have to know which it is. */
    @PostMapping("/v1/partner/applications")
    PartnerAccountDto save(@AuthenticationPrincipal Jwt jwt,
                           @Valid @RequestBody SavePartnerApplicationRequest request) {
        return partners.save(current.require(jwt).id(), request);
    }

    /** A private place to PUT one document. The bytes never pass through here. */
    @PostMapping("/v1/partner/applications/{accountId}/documents/presign")
    DocumentUploadResponse presignDocument(@AuthenticationPrincipal Jwt jwt,
                                           @PathVariable UUID accountId,
                                           @Valid @RequestBody DocumentUploadRequest request) {
        return partners.presignDocument(current.require(jwt).id(), accountId, request);
    }

    @PutMapping("/v1/partner/applications/{accountId}/documents")
    PartnerAccountDto attachDocument(@AuthenticationPrincipal Jwt jwt,
                                     @PathVariable UUID accountId,
                                     @Valid @RequestBody AttachDocumentRequest request) {
        return partners.attachDocument(current.require(jwt).id(), accountId, request);
    }

    @DeleteMapping("/v1/partner/applications/{accountId}/documents/{documentId}")
    PartnerAccountDto deleteDocument(@AuthenticationPrincipal Jwt jwt,
                                     @PathVariable UUID accountId,
                                     @PathVariable UUID documentId) {
        return partners.deleteDocument(current.require(jwt).id(), accountId, documentId);
    }

    // MARK: The stake and the vehicles (Phase 3 M2)

    /**
     * Locks the $30. A 402 carrying the shortfall when the wallet won't cover
     * it, which is what turns "you can't afford this" into a top-up for the
     * right amount rather than a dead end.
     */
    @PostMapping("/v1/partner/applications/{accountId}/stake")
    PartnerAccountDto payStake(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID accountId) {
        return partners.payStake(current.require(jwt).id(), accountId);
    }

    /** Adds a vehicle. The first one becomes the one you're driving — making
     *  that a separate step only produces applications blocked for a reason
     *  nobody can see. */
    @PostMapping("/v1/partner/applications/{accountId}/vehicles")
    VehicleDto addVehicle(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID accountId,
                          @Valid @RequestBody SaveVehicleRequest request) {
        return partners.saveVehicle(current.require(jwt).id(), accountId, null, request);
    }

    @PutMapping("/v1/partner/applications/{accountId}/vehicles/{vehicleId}")
    VehicleDto editVehicle(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID accountId,
                           @PathVariable UUID vehicleId,
                           @Valid @RequestBody SaveVehicleRequest request) {
        return partners.saveVehicle(current.require(jwt).id(), accountId, vehicleId, request);
    }

    /** Which car you're driving today. Allowed after approval too — it is the
     *  one field dispatch matches on, and it changes more often than anything
     *  else on an application. */
    @PostMapping("/v1/partner/applications/{accountId}/vehicles/{vehicleId}/activate")
    VehicleDto activateVehicle(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID accountId,
                               @PathVariable UUID vehicleId) {
        return partners.activateVehicle(current.require(jwt).id(), accountId, vehicleId);
    }

    @DeleteMapping("/v1/partner/applications/{accountId}/vehicles/{vehicleId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void retireVehicle(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID accountId,
                       @PathVariable UUID vehicleId) {
        partners.retireVehicle(current.require(jwt).id(), accountId, vehicleId);
    }

    @PostMapping("/v1/partner/applications/{accountId}/vehicles/{vehicleId}/documents/presign")
    DocumentUploadResponse presignVehicleDocument(
            @AuthenticationPrincipal Jwt jwt, @PathVariable UUID accountId,
            @PathVariable UUID vehicleId, @Valid @RequestBody DocumentUploadRequest request) {
        return partners.presignVehicleDocument(current.require(jwt).id(), accountId,
            vehicleId, request);
    }

    @PutMapping("/v1/partner/applications/{accountId}/vehicles/{vehicleId}/documents")
    VehicleDto attachVehicleDocument(
            @AuthenticationPrincipal Jwt jwt, @PathVariable UUID accountId,
            @PathVariable UUID vehicleId, @Valid @RequestBody AttachDocumentRequest request) {
        return partners.attachVehicleDocument(current.require(jwt).id(), accountId,
            vehicleId, request);
    }

    @PostMapping("/v1/partner/applications/{accountId}/submit")
    PartnerAccountDto submit(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID accountId) {
        return partners.submit(current.require(jwt).id(), accountId);
    }

    @PostMapping("/v1/partner/applications/{accountId}/withdraw")
    PartnerAccountDto withdraw(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID accountId) {
        return partners.withdraw(current.require(jwt).id(), accountId);
    }
}
