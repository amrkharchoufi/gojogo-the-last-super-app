package com.gojogo.economy.internal;

import com.gojogo.media.MediaDocumentApi;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The ownership-transfer workflow (SPECS §6): {@code INQUIRY → OFFER_ACCEPTED
 * → PAYMENT_HELD → DOCS_CONFIRMED → TRANSFERRED → RELEASED}, cancellation with
 * a full refund open through {@code PAYMENT_HELD}.
 *
 * <p>Three decisions carry the shape. The escrow comes <em>before</em> the
 * document check, because a reviewer's time should only be spent on a deal
 * that is real. The check itself is a human act with a name on it — the same
 * posture as KYC review, and the reason there is no auto-confirm anywhere
 * here. And one listing can hold at most one live escrow (a partial unique
 * index), while any number of buyers may sit at {@code INQUIRY} — interest is
 * free, money is exclusive.
 */
@Service
class OwnershipTransferService {

    private final OwnershipTransferRepository transfers;
    private final TransferDocumentRepository transferDocs;
    private final ListingRepository listings;
    private final ProductOrderPayments payments;
    private final MediaDocumentApi documents;

    OwnershipTransferService(OwnershipTransferRepository transfers,
                             TransferDocumentRepository transferDocs,
                             ListingRepository listings, ProductOrderPayments payments,
                             MediaDocumentApi documents) {
        this.transfers = transfers;
        this.transferDocs = transferDocs;
        this.listings = listings;
        this.payments = payments;
        this.documents = documents;
    }

    /** A buyer raises their hand. Idempotent per (listing, buyer): asking twice
     *  returns the same inquiry rather than two. */
    @Transactional
    ProductDtos.TransferResponse inquire(UUID me, UUID listingId) {
        Listing listing = listings.findById(listingId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such listing"));
        if (listing.getKind() != ListingKind.OWNERSHIP_TRANSFER) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "This listing isn't an ownership transfer");
        }
        if (listing.getStatus() != ListingStatus.ACTIVE || listing.isHidden()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "This listing isn't for sale");
        }
        if (listing.getSellerId().equals(me)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "That's your own listing");
        }
        OwnershipTransfer transfer = transfers
            .findByListingIdAndBuyerIdAndState(listingId, me, TransferState.INQUIRY)
            .orElseGet(() -> transfers.save(
                new OwnershipTransfer(listingId, listing.getSellerId(), me)));
        return toResponse(transfer, listing, transferDocs.countByTransferId(transfer.getId()));
    }

    /** The seller names the price. From here the number never moves — a
     *  renegotiation is a cancel and a fresh inquiry. */
    @Transactional
    ProductDtos.TransferResponse accept(UUID me, UUID transferId, long priceCents) {
        OwnershipTransfer transfer = require(transferId);
        if (!transfer.getSellerId().equals(me)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such transfer");
        }
        requireState(transfer, TransferState.INQUIRY);
        transfer.accepted(priceCents, OffsetDateTime.now());
        return toResponse(transfers.save(transfer));
    }

    /**
     * The buyer escrows the price. Above the CONFIG cap the wallet refuses and
     * the row is flagged for manual settlement — an operator moves that kind of
     * money, not this system (SPECS §6).
     */
    @Transactional
    ProductDtos.TransferResponse pay(UUID me, UUID transferId) {
        OwnershipTransfer transfer = require(transferId);
        if (!transfer.getBuyerId().equals(me)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such transfer");
        }
        requireState(transfer, TransferState.OFFER_ACCEPTED);
        long cap = payments.transferWalletCapCents();
        if (cap > 0 && transfer.getPriceCents() > cap) {
            transfer.flagManual();
            transfers.save(transfer);
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "This amount is above the in-app limit — an operator will settle it manually");
        }
        payments.holdTransfer(transfer, "Ownership transfer escrow");
        try {
            // The partial unique index is the arbiter: one live escrow per
            // listing, and the second buyer loses here rather than later.
            return toResponse(transfers.saveAndFlush(transfer));
        } catch (DataIntegrityViolationException anotherBuyerHolds) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Another buyer's transfer is already in progress on this listing");
        }
    }

    /** The human checkpoint. Requires held money — a reviewer's time is only
     *  spent on a deal that is real. */
    @Transactional
    ProductDtos.TransferResponse confirmDocs(String reviewer, UUID transferId) {
        OwnershipTransfer transfer = require(transferId);
        requireState(transfer, TransferState.PAYMENT_HELD);
        transfer.docsConfirmed(reviewer, OffsetDateTime.now());
        return toResponse(transfers.save(transfer));
    }

    /** The buyer has the thing and the papers: the handover is done, the money
     *  moves, and the listing leaves the market as SOLD in the same breath. */
    @Transactional
    ProductDtos.TransferResponse confirmReceived(UUID me, UUID transferId) {
        OwnershipTransfer transfer = require(transferId);
        if (!transfer.getBuyerId().equals(me)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such transfer");
        }
        requireState(transfer, TransferState.DOCS_CONFIRMED);
        OffsetDateTime now = OffsetDateTime.now();
        transfer.transferred(now);
        payments.settleTransfer(transfer, "Ownership transfer");
        transfer.released(now);
        listings.findById(transfer.getListingId()).ifPresent(listing -> {
            listing.setStatus(ListingStatus.SOLD);
            listings.save(listing);
        });
        return toResponse(transfers.save(transfer));
    }

    /** Either side, any time before the paperwork was confirmed. Whatever was
     *  held goes back in full. */
    @Transactional
    ProductDtos.TransferResponse cancel(UUID me, UUID transferId, String note) {
        OwnershipTransfer transfer = require(transferId);
        if (!transfer.isParty(me)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such transfer");
        }
        if (!transfer.getState().cancellable()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "The paperwork is confirmed — this transfer can only complete now");
        }
        payments.releaseTransfer(transfer);
        transfer.cancelled(note, OffsetDateTime.now());
        return toResponse(transfers.save(transfer));
    }

    // MARK: Documents

    MediaDocumentApi.DocumentUpload presignDocument(UUID me, UUID transferId, String contentType) {
        OwnershipTransfer transfer = require(transferId);
        if (!transfer.getSellerId().equals(me)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such transfer");
        }
        return documents.presignDocumentUpload(me, "transfer", contentType);
    }

    @Transactional
    ProductDtos.TransferDocumentResponse attachDocument(UUID me, UUID transferId,
                                                        String objectKey, String label) {
        OwnershipTransfer transfer = require(transferId);
        if (!transfer.getSellerId().equals(me)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such transfer");
        }
        TransferDocument saved = transferDocs.save(
            new TransferDocument(transferId, objectKey, label));
        return new ProductDtos.TransferDocumentResponse(saved.getId(), saved.getLabel(),
            null, saved.getUploadedAt());
    }

    /** The paperwork, each with a freshly signed short-lived read link. For the
     *  two parties; the reviewer reads through the admin surface. */
    @Transactional(readOnly = true)
    List<ProductDtos.TransferDocumentResponse> documentsFor(UUID me, UUID transferId) {
        OwnershipTransfer transfer = require(transferId);
        if (!transfer.isParty(me)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such transfer");
        }
        return signedDocuments(transferId);
    }

    List<ProductDtos.TransferDocumentResponse> signedDocuments(UUID transferId) {
        return transferDocs.findByTransferIdOrderByUploadedAtAsc(transferId).stream()
            .map(d -> new ProductDtos.TransferDocumentResponse(d.getId(), d.getLabel(),
                documents.presignDocumentRead(d.getObjectKey()), d.getUploadedAt()))
            .toList();
    }

    // MARK: Reads

    @Transactional(readOnly = true)
    List<ProductDtos.TransferResponse> mine(UUID me, int limit) {
        return decorate(transfers.mine(me, PageRequest.of(0, Math.clamp(limit, 1, 100))));
    }

    @Transactional(readOnly = true)
    ProductDtos.TransferResponse get(UUID me, UUID transferId) {
        OwnershipTransfer transfer = require(transferId);
        if (!transfer.isParty(me)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such transfer");
        }
        return toResponse(transfer);
    }

    /** The operator's queue: what waits on a document check, plus what was
     *  flagged past the wallet cap. */
    @Transactional(readOnly = true)
    List<ProductDtos.TransferResponse> reviewQueue(int limit) {
        PageRequest page = PageRequest.of(0, Math.clamp(limit, 1, 100));
        List<OwnershipTransfer> waiting = new java.util.ArrayList<>(
            transfers.findByStateOrderByCreatedAtAsc(TransferState.PAYMENT_HELD, page));
        transfers.findByFlaggedManualTrueOrderByCreatedAtAsc(page).stream()
            .filter(t -> waiting.stream().noneMatch(w -> w.getId().equals(t.getId())))
            .forEach(waiting::add);
        return decorate(waiting);
    }

    private List<ProductDtos.TransferResponse> decorate(List<OwnershipTransfer> page) {
        if (page.isEmpty()) return List.of();
        Map<UUID, Listing> byId = listings.findAllById(page.stream()
                .map(OwnershipTransfer::getListingId).collect(Collectors.toSet())).stream()
            .collect(Collectors.toMap(Listing::getId, l -> l));
        // One grouped count for the page rather than one query per row.
        Map<UUID, Long> documentCounts = transferDocs.countByTransferIdIn(
                page.stream().map(OwnershipTransfer::getId).collect(Collectors.toSet())).stream()
            .collect(Collectors.toMap(
                TransferDocumentRepository.TransferDocumentCount::getTransferId,
                TransferDocumentRepository.TransferDocumentCount::getTotal));
        return page.stream()
            .map(t -> toResponse(t, byId.get(t.getListingId()),
                documentCounts.getOrDefault(t.getId(), 0L)))
            .toList();
    }

    private OwnershipTransfer require(UUID transferId) {
        return transfers.findById(transferId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such transfer"));
    }

    private static void requireState(OwnershipTransfer transfer, TransferState expected) {
        if (transfer.getState() != expected) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "The transfer is " + transfer.getState() + ", not " + expected);
        }
    }

    private ProductDtos.TransferResponse toResponse(OwnershipTransfer transfer) {
        return toResponse(transfer, listings.findById(transfer.getListingId()).orElse(null),
            transferDocs.countByTransferId(transfer.getId()));
    }

    private ProductDtos.TransferResponse toResponse(OwnershipTransfer t, Listing listing,
                                                    long documentCount) {
        return new ProductDtos.TransferResponse(t.getId(), t.getListingId(),
            listing == null ? "Removed listing" : listing.getTitle(),
            listing == null ? null : listing.getVinSerial(),
            t.getSellerId(), t.getBuyerId(), t.getState().name(), t.getPriceCents(),
            payments.currency(), t.isFlaggedManual(), t.getCreatedAt(), t.getAcceptedAt(),
            t.getPaidAt(), t.getDocsConfirmedAt(), t.getTransferredAt(), t.getReleasedAt(),
            t.getCancelledAt(), t.getCancelNote(), documentCount);
    }
}
