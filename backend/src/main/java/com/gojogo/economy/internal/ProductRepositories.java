package com.gojogo.economy.internal;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface SellerRepository extends JpaRepository<Seller, UUID> {

    Optional<Seller> findByOwnerUserId(UUID ownerUserId);
}

interface ProductRepository extends JpaRepository<Product, UUID> {

    /** The public catalog: live products of unsuspended sellers, newest first. */
    @Query("""
        select p from Product p
        where p.active = true and p.hiddenAt is null
          and p.createdAt < :before
          and (:category is null or p.category = :category)
          and (:sellerId is null or p.sellerId = :sellerId)
          and not exists (select s from Seller s where s.id = p.sellerId and s.suspended = true)
        order by p.createdAt desc
        """)
    List<Product> browse(@Param("category") String category,
                         @Param("sellerId") UUID sellerId,
                         @Param("before") OffsetDateTime before, Pageable page);

    List<Product> findBySellerIdOrderByCreatedAtDesc(UUID sellerId, Pageable page);
}

interface ProductVariantRepository extends JpaRepository<ProductVariant, UUID> {

    /**
     * The oversell guard (SPECS §6): stock moves only when there is enough of
     * it, in one conditional statement, inside the order transaction. Returns 0
     * rather than throwing when there isn't — the caller names the product in
     * its 409.
     */
    @Modifying
    @Query("""
        update ProductVariant v set v.stock = v.stock - :qty
        where v.id = :id and v.active = true and v.stock >= :qty
        """)
    int takeStock(@Param("id") UUID id, @Param("qty") int qty);

    /** The way back — a cancelled order's goods go back on the shelf. */
    @Modifying
    @Query("update ProductVariant v set v.stock = v.stock + :qty where v.id = :id")
    void restock(@Param("id") UUID id, @Param("qty") int qty);
}

interface ProductOrderRepository extends JpaRepository<ProductOrder, UUID> {

    List<ProductOrder> findByBuyerIdOrderByPlacedAtDesc(UUID buyerId, Pageable page);

    List<ProductOrder> findBySellerIdOrderByPlacedAtDesc(UUID sellerId, Pageable page);

    List<ProductOrder> findBySellerIdAndStatusOrderByPlacedAtDesc(
        UUID sellerId, ProductOrderStatus status, Pageable page);

    /** Shipped and never confirmed — what the auto-complete sweep collects. */
    @Query("""
        select o.id from ProductOrder o
        where o.status = com.gojogo.economy.internal.ProductOrderStatus.SHIPPED
          and o.shippedAt < :cutoff
        """)
    List<UUID> shippedBefore(@Param("cutoff") OffsetDateTime cutoff, Pageable page);

    boolean existsByIdAndBuyerIdAndStatus(UUID id, UUID buyerId, ProductOrderStatus status);
}

interface ProductPromotionRepository extends JpaRepository<ProductPromotion, UUID> {

    List<ProductPromotion> findBySellerIdAndActiveTrue(UUID sellerId);

    List<ProductPromotion> findBySellerIdOrderByCreatedAtDesc(UUID sellerId);
}

interface ProductPromotionRedemptionRepository
    extends JpaRepository<ProductPromotionRedemption, UUID> {

    long countByPromotionIdAndUserId(UUID promotionId, UUID userId);
}

interface ProductReviewRepository extends JpaRepository<ProductReview, UUID> {

    Optional<ProductReview> findByProductIdAndAuthorId(UUID productId, UUID authorId);

    List<ProductReview> findByProductIdOrderByCreatedAtDesc(UUID productId, Pageable page);
}

// MARK: Special catalogs (Phase 5 M2)

interface DigitalAssetRepository extends JpaRepository<DigitalAsset, UUID> {

    Optional<DigitalAsset> findByProductId(UUID productId);

    List<DigitalAsset> findByProductIdIn(Collection<UUID> productIds);
}

interface EntitlementRepository extends JpaRepository<Entitlement, UUID> {

    List<Entitlement> findByUserIdOrderByCreatedAtDesc(UUID userId, Pageable page);

    boolean existsByOrderId(UUID orderId);
}

interface OwnershipTransferRepository extends JpaRepository<OwnershipTransfer, UUID> {

    Optional<OwnershipTransfer> findByListingIdAndBuyerIdAndState(
        UUID listingId, UUID buyerId, TransferState state);

    @Query("""
        select t from OwnershipTransfer t
        where t.buyerId = :me or t.sellerId = :me
        order by t.createdAt desc
        """)
    List<OwnershipTransfer> mine(@Param("me") UUID me, Pageable page);

    List<OwnershipTransfer> findByStateOrderByCreatedAtAsc(TransferState state, Pageable page);

    List<OwnershipTransfer> findByFlaggedManualTrueOrderByCreatedAtAsc(Pageable page);
}

interface TransferDocumentRepository extends JpaRepository<TransferDocument, UUID> {

    List<TransferDocument> findByTransferIdOrderByUploadedAtAsc(UUID transferId);
}
