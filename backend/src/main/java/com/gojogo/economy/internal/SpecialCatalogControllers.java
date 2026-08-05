package com.gojogo.economy.internal;

import com.gojogo.auth.PlatformAdminApi;
import com.gojogo.media.MediaDocumentApi;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * The Phase 5 M2 surfaces, three small controllers in one file: what a buyer
 * owns digitally, the transfer workflow's two parties, and the operator's
 * document checkpoint.
 */
class SpecialCatalogControllers {

    private SpecialCatalogControllers() {
    }
}

/** Digital shelf: what I own, and a fresh download link for one of it. */
@RestController
class EntitlementController {

    private final DigitalDeliveryService digital;
    private final EconomyCurrentProfile current;

    EntitlementController(DigitalDeliveryService digital, EconomyCurrentProfile current) {
        this.digital = digital;
        this.current = current;
    }

    @GetMapping("/v1/economy/entitlements")
    List<ProductDtos.EntitlementResponse> mine(@AuthenticationPrincipal Jwt jwt,
                                               @RequestParam(defaultValue = "50") int limit) {
        return digital.mine(current.require(jwt).id(), limit);
    }

    /** Minted per ask and never stored — an expired link is a link that can't
     *  leak, and the entitlement row is what makes the next one. */
    @PostMapping("/v1/economy/entitlements/{entitlementId}/download")
    ProductDtos.DownloadResponse download(@AuthenticationPrincipal Jwt jwt,
                                          @PathVariable UUID entitlementId) {
        return new ProductDtos.DownloadResponse(
            digital.downloadUrl(current.require(jwt).id(), entitlementId));
    }
}

/** The seller's digital-asset verbs, on the same /mine surface as the catalog. */
@RestController
class DigitalAssetController {

    private final DigitalDeliveryService digital;
    private final EconomyCurrentProfile current;

    DigitalAssetController(DigitalDeliveryService digital, EconomyCurrentProfile current) {
        this.digital = digital;
        this.current = current;
    }

    @PostMapping("/v1/economy/sellers/mine/digital-uploads")
    MediaDocumentApi.DocumentUpload presign(@AuthenticationPrincipal Jwt jwt,
                                            @RequestParam(defaultValue = "application/octet-stream")
                                            String contentType) {
        return digital.presignUpload(current.require(jwt).id(), contentType);
    }

    @PutMapping("/v1/economy/sellers/mine/products/{productId}/digital-asset")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void attach(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID productId,
                @Valid @RequestBody ProductDtos.AttachDigitalAssetRequest request) {
        digital.attach(current.require(jwt).id(), productId, request.objectKey(),
            request.fileName(), request.contentType(), request.entitlementKind());
    }
}

/** The two parties' side of an ownership transfer. */
@RestController
class OwnershipTransferController {

    private final OwnershipTransferService transfers;
    private final EconomyCurrentProfile current;

    OwnershipTransferController(OwnershipTransferService transfers,
                                EconomyCurrentProfile current) {
        this.transfers = transfers;
        this.current = current;
    }

    @PostMapping("/v1/economy/listings/{listingId}/transfer")
    @ResponseStatus(HttpStatus.CREATED)
    ProductDtos.TransferResponse inquire(@AuthenticationPrincipal Jwt jwt,
                                         @PathVariable UUID listingId) {
        return transfers.inquire(current.require(jwt).id(), listingId);
    }

    @GetMapping("/v1/economy/transfers")
    List<ProductDtos.TransferResponse> mine(@AuthenticationPrincipal Jwt jwt,
                                            @RequestParam(defaultValue = "50") int limit) {
        return transfers.mine(current.require(jwt).id(), limit);
    }

    @GetMapping("/v1/economy/transfers/{transferId}")
    ProductDtos.TransferResponse get(@AuthenticationPrincipal Jwt jwt,
                                     @PathVariable UUID transferId) {
        return transfers.get(current.require(jwt).id(), transferId);
    }

    @PostMapping("/v1/economy/transfers/{transferId}/accept")
    ProductDtos.TransferResponse accept(@AuthenticationPrincipal Jwt jwt,
                                        @PathVariable UUID transferId,
                                        @Valid @RequestBody ProductDtos.AcceptTransferRequest request) {
        return transfers.accept(current.require(jwt).id(), transferId, request.priceCents());
    }

    @PostMapping("/v1/economy/transfers/{transferId}/pay")
    ProductDtos.TransferResponse pay(@AuthenticationPrincipal Jwt jwt,
                                     @PathVariable UUID transferId) {
        return transfers.pay(current.require(jwt).id(), transferId);
    }

    @PostMapping("/v1/economy/transfers/{transferId}/received")
    ProductDtos.TransferResponse received(@AuthenticationPrincipal Jwt jwt,
                                          @PathVariable UUID transferId) {
        return transfers.confirmReceived(current.require(jwt).id(), transferId);
    }

    @PostMapping("/v1/economy/transfers/{transferId}/cancel")
    ProductDtos.TransferResponse cancel(@AuthenticationPrincipal Jwt jwt,
                                        @PathVariable UUID transferId,
                                        @RequestBody(required = false)
                                        ProductDtos.CancelTransferRequest request) {
        return transfers.cancel(current.require(jwt).id(), transferId,
            request == null ? null : request.note());
    }

    // MARK: Paperwork

    @PostMapping("/v1/economy/transfers/{transferId}/documents/presign")
    MediaDocumentApi.DocumentUpload presignDocument(@AuthenticationPrincipal Jwt jwt,
                                                    @PathVariable UUID transferId,
                                                    @RequestParam(defaultValue = "application/pdf")
                                                    String contentType) {
        return transfers.presignDocument(current.require(jwt).id(), transferId, contentType);
    }

    @PostMapping("/v1/economy/transfers/{transferId}/documents")
    @ResponseStatus(HttpStatus.CREATED)
    ProductDtos.TransferDocumentResponse attachDocument(
        @AuthenticationPrincipal Jwt jwt, @PathVariable UUID transferId,
        @Valid @RequestBody ProductDtos.AttachTransferDocumentRequest request) {
        return transfers.attachDocument(current.require(jwt).id(), transferId,
            request.objectKey(), request.label());
    }

    @GetMapping("/v1/economy/transfers/{transferId}/documents")
    List<ProductDtos.TransferDocumentResponse> documents(@AuthenticationPrincipal Jwt jwt,
                                                         @PathVariable UUID transferId) {
        return transfers.documentsFor(current.require(jwt).id(), transferId);
    }
}

/**
 * The operator's checkpoint (SPECS §6: "a human verifies the paperwork; same
 * posture as KYC review"). Same guard as every operator surface since 2e M5:
 * {@code PlatformAdminApi} — the {@code platform-admin} Cognito group or the
 * break-glass token — under a path the JWT chain already exempts.
 */
@RestController
class TransferReviewController {

    static final String TOKEN_HEADER = "X-Partner-Admin-Token";

    private final OwnershipTransferService transfers;
    private final PlatformAdminApi admins;

    TransferReviewController(OwnershipTransferService transfers, PlatformAdminApi admins) {
        this.transfers = transfers;
        this.admins = admins;
    }

    /** Escrowed transfers waiting on a document check, plus the flagged-manual
     *  ones the wallet refused. */
    @GetMapping("/v1/economy/admin/transfers")
    List<ProductDtos.TransferResponse> queue(
        @RequestHeader(name = TOKEN_HEADER, required = false) String token,
        @AuthenticationPrincipal Jwt jwt,
        @RequestParam(defaultValue = "50") int limit) {
        admins.require(token, jwt);
        return transfers.reviewQueue(limit);
    }

    @GetMapping("/v1/economy/admin/transfers/{transferId}/documents")
    List<ProductDtos.TransferDocumentResponse> documents(
        @RequestHeader(name = TOKEN_HEADER, required = false) String token,
        @AuthenticationPrincipal Jwt jwt,
        @PathVariable UUID transferId) {
        admins.require(token, jwt);
        return transfers.signedDocuments(transferId);
    }

    @PostMapping("/v1/economy/admin/transfers/{transferId}/confirm-docs")
    ProductDtos.TransferResponse confirmDocs(
        @RequestHeader(name = TOKEN_HEADER, required = false) String token,
        @AuthenticationPrincipal Jwt jwt,
        @PathVariable UUID transferId) {
        return transfers.confirmDocs(admins.require(token, jwt).toString(), transferId);
    }
}
