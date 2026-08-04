package com.gojogo.delivery.internal;

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

interface MerchantRepository extends JpaRepository<Merchant, UUID> {

    /**
     * Catalog browse, fastest first. Empty strings mean "no filter" rather than
     * nulls — a JPQL {@code :param is null} on an untyped bind is the kind of
     * thing that only fails once it reaches Postgres.
     *
     * <p>Both flags have to be right: {@code active} is the owner saying
     * they're open, {@code suspended} is the platform saying they're not.
     */
    @Query("select distinct m from Merchant m left join m.categories c "
        + "where m.active = true and m.suspended = false "
        + "and (:category = '' or c = :category) "
        + "and (:q = '' or lower(m.name) like concat('%', :q, '%') "
        + "     or lower(m.cuisine) like concat('%', :q, '%')) "
        + "order by m.etaMinutes asc, m.name asc")
    List<Merchant> browse(@Param("category") String category, @Param("q") String q, Pageable page);

    /** The restaurant this profile manages, if they have one. */
    Optional<Merchant> findFirstByOwnerId(UUID ownerId);
}

interface MenuSectionRepository extends JpaRepository<MenuSection, UUID> {

    List<MenuSection> findByMerchantIdOrderBySortOrderAsc(UUID merchantId);

    /** Which of these sections are this restaurant's — the storefront write
     *  refuses a block pointing anywhere else, and needs to name the id. */
    @Query("select s.id from MenuSection s where s.merchantId = :merchantId and s.id in :ids")
    List<UUID> idsForMerchant(@Param("merchantId") UUID merchantId,
                              @Param("ids") Collection<UUID> ids);

    @Query("select coalesce(max(s.sortOrder), -1) from MenuSection s where s.merchantId = :merchantId")
    int maxSortOrder(@Param("merchantId") UUID merchantId);
}

interface MenuItemRepository extends JpaRepository<MenuItem, UUID> {

    /**
     * The items of one merchant, by id. Used to price an order: an item that
     * belongs to a different restaurant (or doesn't exist) simply won't come
     * back, and the order is rejected.
     */
    @Query("select i from MenuItem i, MenuSection s "
        + "where i.sectionId = s.id and s.merchantId = :merchantId and i.id in :ids")
    List<MenuItem> findForMerchant(@Param("merchantId") UUID merchantId,
                                   @Param("ids") Collection<UUID> ids);

    List<MenuItem> findBySectionIdOrderBySortOrderAsc(UUID sectionId);

    /** Whether this restaurant has anything a customer could actually order —
     *  the bar for letting the owner publish it. */
    @Query("select count(i) from MenuItem i, MenuSection s "
        + "where i.sectionId = s.id and s.merchantId = :merchantId and i.available = true")
    long countAvailableForMerchant(@Param("merchantId") UUID merchantId);

    @Query("select coalesce(max(i.sortOrder), -1) from MenuItem i where i.sectionId = :sectionId")
    int maxSortOrder(@Param("sectionId") UUID sectionId);
}

interface AddressRepository extends JpaRepository<Address, UUID> {

    /** Saved addresses, default first, then newest. */
    List<Address> findByUserIdOrderByIsDefaultDescCreatedAtDesc(UUID userId);

    Optional<Address> findFirstByUserIdAndIsDefaultTrue(UUID userId);

    /** Clears the current default so a new one can take it (one per user is a
     *  partial unique index, so this has to run before the new one is set). */
    @Modifying
    @Query("update Address a set a.isDefault = false where a.userId = :userId and a.isDefault = true")
    void clearDefault(@Param("userId") UUID userId);
}

interface PromotionRepository extends JpaRepository<Promotion, UUID> {

    List<Promotion> findByMerchantIdOrderByCreatedAtDesc(UUID merchantId);

    /** Which of these promotions are this restaurant's — see
     *  {@link MenuSectionRepository#idsForMerchant}. */
    @Query("select p.id from Promotion p where p.merchantId = :merchantId and p.id in :ids")
    List<UUID> idsForMerchant(@Param("merchantId") UUID merchantId,
                              @Param("ids") Collection<UUID> ids);

    List<Promotion> findByMerchantIdAndActiveTrue(UUID merchantId);

    /** Case-insensitive: a customer typing `welcome10` means WELCOME10. */
    Optional<Promotion> findByMerchantIdAndCodeIgnoreCase(UUID merchantId, String code);
}

interface PromotionRedemptionRepository extends JpaRepository<PromotionRedemption, UUID> {

    long countByPromotionIdAndUserId(UUID promotionId, UUID userId);

    /** Keyed on both since Phase 4 M3: one order can carry a different
     *  promotion per merchant, and the second must not be skipped because the
     *  first was recorded. */
    boolean existsByPromotionIdAndOrderId(UUID promotionId, UUID orderId);

    /** Everything this order has claimed. Read when it changes (Phase 4 M5), so
     *  a promotion the new basket no longer uses stops counting against the
     *  customer's allowance. */
    List<PromotionRedemption> findByOrderId(UUID orderId);
}

interface OrderRepository extends JpaRepository<CustomerOrder, UUID> {

    /**
     * The orders actually being fulfilled right now — soonest first (Phase 4
     * M5).
     *
     * <p>A list rather than the single order this used to be, because a
     * scheduled order promotes on its own clock and can land while another one
     * is in flight. Refusing to promote it would be holding somebody's dinner
     * back over a rule about screens.
     *
     * <p>A scheduled order that no kitchen has been told about is deliberately
     * <em>not</em> here: it is not in flight, and drawing a tracking card for
     * an order that is three days away is the app describing a state nobody is
     * in.
     */
    @Query("select o from CustomerOrder o where o.userId = :userId "
        + "and o.status not in :terminal and o.queuedAt is not null "
        + "order by o.etaAt asc")
    List<CustomerOrder> liveFor(@Param("userId") UUID userId,
                                @Param("terminal") Collection<OrderStatus> terminal);

    /** Scheduled orders no kitchen has seen yet, soonest first — the ones the
     *  customer can still change or cancel for nothing. */
    @Query("select o from CustomerOrder o where o.userId = :userId "
        + "and o.status not in :terminal and o.queuedAt is null "
        + "order by o.scheduledFor asc")
    List<CustomerOrder> waitingFor(@Param("userId") UUID userId,
                                   @Param("terminal") Collection<OrderStatus> terminal);

    /**
     * Scheduled orders whose moment has come. Matches the partial index
     * {@code V42} creates — the rows worth looking at are the few that are
     * still waiting, not every order ever placed.
     */
    @Query("select o.id from CustomerOrder o where o.queuedAt is null "
        + "and o.queueAt <= :now and o.status not in :terminal "
        + "order by o.queueAt asc")
    List<UUID> dueForQueue(@Param("now") OffsetDateTime now,
                           @Param("terminal") Collection<OrderStatus> terminal, Pageable page);

    /** Order history — delivered and cancelled orders, newest first. */
    List<CustomerOrder> findByUserIdAndStatusInOrderByPlacedAtDesc(
        UUID userId, Collection<OrderStatus> terminal, Pageable page);

    /** The one order a courier is carrying. Never more than one — accepting
     *  anything makes a worker BUSY in every registration they hold. */
    Optional<CustomerOrder> findFirstByCourierUserIdAndStatusInOrderByStatusChangedAtDesc(
        UUID courierUserId, Collection<OrderStatus> statuses);

    List<CustomerOrder> findByCourierUserIdAndStatusOrderByStatusChangedAtDesc(
        UUID courierUserId, OrderStatus status, Pageable page);
}

interface SubOrderRepository extends JpaRepository<SubOrder, UUID> {

    /**
     * The restaurant's live queue, oldest first — a kitchen works in the order
     * things arrived in. Since Phase 4 M3 a kitchen sees its own slice of an
     * order and nothing about the other merchants on it.
     *
     * <p>"Arrived" is {@code queuedAt} since Phase 4 M5, not {@code placedAt}:
     * a scheduled order arrives when it is promoted, and one placed yesterday
     * for tonight is not something to sort to the top of tonight's queue. The
     * null check is the same fact from the other side — a scheduled order
     * nobody has been told about is not in anybody's queue at all.
     */
    @Query("select s from SubOrder s where s.merchantId = :merchantId "
        + "and s.status in :statuses and s.order.queuedAt is not null "
        + "order by s.order.queuedAt asc")
    List<SubOrder> queueFor(@Param("merchantId") UUID merchantId,
                            @Param("statuses") Collection<SubOrderStatus> statuses);

    /** What they finished (or lost), newest first. */
    @Query("select s from SubOrder s where s.merchantId = :merchantId "
        + "and s.status in :statuses order by s.order.statusChangedAt desc")
    List<SubOrder> historyFor(@Param("merchantId") UUID merchantId,
                              @Param("statuses") Collection<SubOrderStatus> statuses,
                              Pageable page);

    /**
     * Slices nobody in a kitchen ever answered — still CONFIRMED past the
     * cutoff on an order that is still going. The same query that used to run
     * on the order runs per kitchen now, because "the restaurant didn't answer"
     * is a fact about one restaurant and must not time out the two that did.
     *
     * <p>Counted from {@code queuedAt} since Phase 4 M5, and the null check is
     * load-bearing rather than defensive: a scheduled order sits in CONFIRMED
     * from the moment it is placed, so a cutoff measured from {@code placedAt}
     * would cancel tomorrow's lunch ten minutes after somebody ordered it. A
     * restaurant cannot fail to answer a question it has not been asked.
     */
    @Query("select s.id from SubOrder s where s.status = com.gojogo.delivery.internal.SubOrderStatus.CONFIRMED "
        + "and s.order.status not in :terminal "
        + "and s.order.queuedAt is not null and s.order.queuedAt < :cutoff "
        + "order by s.order.queuedAt asc")
    List<UUID> unansweredIds(@Param("terminal") Collection<OrderStatus> terminal,
                             @Param("cutoff") OffsetDateTime cutoff, Pageable page);
}
