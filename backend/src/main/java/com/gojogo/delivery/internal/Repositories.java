package com.gojogo.delivery.internal;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface MerchantRepository extends JpaRepository<Merchant, UUID> {

    /**
     * Catalog browse, fastest first. Empty strings mean "no filter" rather than
     * nulls — a JPQL {@code :param is null} on an untyped bind is the kind of
     * thing that only fails once it reaches Postgres.
     */
    @Query("select distinct m from Merchant m left join m.categories c "
        + "where m.active = true "
        + "and (:category = '' or c = :category) "
        + "and (:q = '' or lower(m.name) like concat('%', :q, '%') "
        + "     or lower(m.cuisine) like concat('%', :q, '%')) "
        + "order by m.etaMinutes asc, m.name asc")
    List<Merchant> browse(@Param("category") String category, @Param("q") String q, Pageable page);
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

interface OrderRepository extends JpaRepository<CustomerOrder, UUID> {

    /** The one order still in flight for this user, if any. */
    Optional<CustomerOrder> findFirstByUserIdAndStatusNotInOrderByPlacedAtDesc(
        UUID userId, Collection<OrderStatus> terminal);

    /** Order history — delivered and cancelled orders, newest first. */
    List<CustomerOrder> findByUserIdAndStatusInOrderByPlacedAtDesc(
        UUID userId, Collection<OrderStatus> terminal, Pageable page);

    /** Everything the fulfilment job still has to move along. */
    List<CustomerOrder> findByStatusNotInOrderByPlacedAtAsc(
        Collection<OrderStatus> terminal, Pageable page);
}
