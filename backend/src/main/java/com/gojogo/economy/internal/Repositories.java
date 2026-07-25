package com.gojogo.economy.internal;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.UUID;

interface ListingRepository extends JpaRepository<Listing, UUID> {

    @Query("select l from Listing l where l.status = com.gojogo.economy.internal.ListingStatus.ACTIVE "
        + "and l.createdAt < :before order by l.createdAt desc, l.id desc")
    List<Listing> browse(@Param("before") OffsetDateTime before, Pageable page);

    @Query("select l from Listing l where l.status = com.gojogo.economy.internal.ListingStatus.ACTIVE "
        + "and l.category = :category and l.createdAt < :before "
        + "order by l.createdAt desc, l.id desc")
    List<Listing> browseByCategory(@Param("category") String category,
                                   @Param("before") OffsetDateTime before, Pageable page);

    List<Listing> findBySellerIdOrderByCreatedAtDesc(UUID sellerId, Pageable page);

    @Modifying
    @Query("update Listing l set l.saveCount = l.saveCount + :delta where l.id = :listingId")
    void bumpSaveCount(@Param("listingId") UUID listingId, @Param("delta") int delta);

    /** Counted in one statement so a detail view stays a read plus one write. */
    @Modifying
    @Query("update Listing l set l.viewCount = l.viewCount + 1 where l.id = :listingId")
    void bumpViewCount(@Param("listingId") UUID listingId);

    /** One row per status the seller has anything in — the seller's own totals
     *  across every listing, not just the page "Your listings" is showing. */
    @Query("select l.status as status, count(l) as listings, "
        + "coalesce(sum(l.saveCount), 0) as saves, coalesce(sum(l.viewCount), 0) as views "
        + "from Listing l where l.sellerId = :sellerId group by l.status")
    List<SellerStatusTotals> sellerTotals(@Param("sellerId") UUID sellerId);

    interface SellerStatusTotals {
        ListingStatus getStatus();

        long getListings();

        long getSaves();

        long getViews();
    }
}

interface SavedListingRepository extends JpaRepository<SavedListing, SavedListing.Key> {

    @Query("select s.listingId from SavedListing s where s.userId = :userId and s.listingId in :listingIds")
    Set<UUID> savedListingIds(@Param("userId") UUID userId,
                              @Param("listingIds") Collection<UUID> listingIds);

    @Query("select s.listingId from SavedListing s where s.userId = :userId order by s.createdAt desc")
    List<UUID> savedByUser(@Param("userId") UUID userId, Pageable page);

    @Modifying
    @Query("delete from SavedListing s where s.listingId = :listingId and s.userId = :userId")
    int deleteByListingIdAndUserId(@Param("listingId") UUID listingId, @Param("userId") UUID userId);
}
