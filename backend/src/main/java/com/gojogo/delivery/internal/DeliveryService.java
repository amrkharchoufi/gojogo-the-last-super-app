package com.gojogo.delivery.internal;

import com.gojogo.delivery.OrderPlaced;
import com.gojogo.delivery.OrderStatusChanged;
import com.gojogo.storefront.StorefrontDocument;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
class DeliveryService {

    /** Orders in these states are done — they never move again. */
    private static final Set<OrderStatus> TERMINAL =
        EnumSet.of(OrderStatus.DELIVERED, OrderStatus.CANCELLED);

    /** Once the courier has the food, cancelling isn't ours to offer. */
    private static final Set<OrderStatus> CANCELLABLE =
        EnumSet.of(OrderStatus.CONFIRMED, OrderStatus.PREPARING, OrderStatus.COURIER_TO_RESTAURANT);

    private final MerchantRepository merchants;
    private final MenuItemRepository menuItems;
    private final OrderRepository orders;
    private final AddressRepository addresses;
    private final DeliveryTimeline timeline;
    private final ApplicationEventPublisher events;
    private final OrderPayments payments;
    private final PromotionService promotions;
    private final MerchantStorefrontService storefronts;
    private final int serviceFeeCents;

    DeliveryService(MerchantRepository merchants, MenuItemRepository menuItems,
                    OrderRepository orders, AddressRepository addresses,
                    DeliveryTimeline timeline, ApplicationEventPublisher events,
                    OrderPayments payments, PromotionService promotions,
                    MerchantStorefrontService storefronts,
                    @Value("${gojogo.delivery.service-fee-cents:99}") int serviceFeeCents) {
        this.merchants = merchants;
        this.menuItems = menuItems;
        this.orders = orders;
        this.addresses = addresses;
        this.timeline = timeline;
        this.events = events;
        this.payments = payments;
        this.promotions = promotions;
        this.storefronts = storefronts;
        this.serviceFeeCents = serviceFeeCents;
    }

    // MARK: Addresses

    @Transactional(readOnly = true)
    List<AddressDto> addresses(UUID me) {
        return addresses.findByUserIdOrderByIsDefaultDescCreatedAtDesc(me).stream()
            .map(DeliveryService::toAddressDto)
            .toList();
    }

    /** Saves an address. The first one a user saves becomes their default —
     *  nobody should have to set a default they didn't know existed. */
    @Transactional
    AddressDto createAddress(UUID me, SaveAddressRequest request) {
        boolean first = addresses.findByUserIdOrderByIsDefaultDescCreatedAtDesc(me).isEmpty();
        Address address = new Address(me, request.label(), request.line1(), request.note(),
            request.latitude(), request.longitude());
        if (request.makeDefault() || first) {
            addresses.clearDefault(me);
            addresses.flush();
            address.setDefault(true);
        }
        return toAddressDto(addresses.save(address));
    }

    @Transactional
    AddressDto updateAddress(UUID me, UUID addressId, SaveAddressRequest request) {
        Address address = requireAddress(me, addressId);
        address.apply(request.label(), request.line1(), request.note(),
            request.latitude(), request.longitude());
        if (request.makeDefault() && !address.isDefault()) {
            addresses.clearDefault(me);
            addresses.flush();
            address.setDefault(true);
        }
        return toAddressDto(address);
    }

    @Transactional
    void makeDefaultAddress(UUID me, UUID addressId) {
        Address address = requireAddress(me, addressId);
        if (address.isDefault()) {
            return;
        }
        addresses.clearDefault(me);
        addresses.flush();
        address.setDefault(true);
    }

    /** Deleting the default promotes the next-newest, so a user with addresses
     *  left always has one selected. */
    @Transactional
    void deleteAddress(UUID me, UUID addressId) {
        Address address = requireAddress(me, addressId);
        boolean wasDefault = address.isDefault();
        addresses.delete(address);
        addresses.flush();
        if (wasDefault) {
            addresses.findByUserIdOrderByIsDefaultDescCreatedAtDesc(me).stream()
                .findFirst()
                .ifPresent(next -> next.setDefault(true));
        }
    }

    private Address requireAddress(UUID me, UUID addressId) {
        return addresses.findById(addressId)
            .filter(a -> a.getUserId().equals(me))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such address"));
    }

    private static AddressDto toAddressDto(Address a) {
        return new AddressDto(a.getId(), a.getLabel(), a.getLine1(), a.getNote(),
            a.getLatitude(), a.getLongitude(), a.isDefault());
    }

    // MARK: Catalog

    @Transactional(readOnly = true)
    List<MerchantDto> browse(String category, String query, int limit) {
        String cat = category == null || category.isBlank() || category.equalsIgnoreCase("All")
            ? "" : category;
        String q = query == null ? "" : query.trim().toLowerCase();
        // Categories/tags are lazy element collections, so this is an extra
        // query per row — fine for a catalog of this size, and the alternative
        // (fetch join + Pageable) paginates in memory.
        return merchants.browse(cat, q, PageRequest.of(0, Math.clamp(limit, 1, 50))).stream()
            .map(m -> toMerchantDto(m, false, StorefrontDocument.empty()))
            .toList();
    }

    /** The promotions a customer could use at this restaurant. */
    @Transactional(readOnly = true)
    List<PromotionDto> livePromotions(UUID merchantId) {
        return promotions.liveFor(merchantId);
    }

    @Transactional(readOnly = true)
    MerchantDto merchant(UUID merchantId) {
        Merchant merchant = merchants.findById(merchantId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such restaurant"));
        // Detail only, like the menu: a browse row shows a card, and shipping
        // every restaurant's whole page to draw one would be a query per row.
        return toMerchantDto(merchant, true, storefronts.of(merchantId));
    }

    // MARK: Orders

    /**
     * What this basket would cost, without placing anything.
     *
     * <p>The point is the last three fields: the app can tell someone their
     * wallet is short <em>before</em> they commit to an order, and offer a
     * top-up for the right amount, rather than letting checkout fail with a 402.
     */
    @Transactional(readOnly = true)
    QuoteDto quote(UUID me, QuoteRequest request) {
        Merchant merchant = merchants.findById(request.merchantId())
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such restaurant"));
        Map<UUID, MenuItem> found = priceableItems(merchant, mergeLines(request.lines()));
        int subtotal = subtotalOf(mergeLines(request.lines()), found);

        PromotionService.Applied applied = promotions.resolve(merchant.getId(), me,
            request.promotionCode(), subtotal, merchant.getDeliveryFeeCents());
        Basket basket = Basket.of(subtotal, merchant.getDeliveryFeeCents(), serviceFeeCents,
            applied.discountCents(), request.tipCents(), payments.currency());

        long available = payments.required() ? payments.availableFor(me) : Long.MAX_VALUE;
        boolean covers = !payments.required() || available >= basket.totalCents();
        return new QuoteDto(basket.subtotalCents(), basket.deliveryFeeCents(),
            basket.serviceFeeCents(), basket.discountCents(), basket.tipCents(),
            basket.totalCents(), basket.currency(), applied.code(), applied.label(),
            payments.required() ? available : 0,
            covers, covers ? 0 : basket.totalCents() - available);
    }

    /**
     * Places an order and holds the money for it.
     *
     * <p>Prices come from the database, never from the request: the client sends
     * item ids and quantities only, and an item that isn't on this restaurant's
     * menu is rejected outright. The same is true of the discount — the request
     * may name a code, never an amount.
     *
     * <p>The funds move into the customer's own ESCROW bucket, not out of their
     * hands: cancelling in time releases them, and the merchant is paid when the
     * food arrives. A wallet that can't cover it raises
     * {@link com.gojogo.payments.InsufficientFundsException}, which the global
     * handler turns into a 402 — and nothing is saved, because the hold and the
     * order are one transaction.
     */
    @Transactional
    OrderDto place(UUID me, PlaceOrderRequest request) {
        orders.findFirstByUserIdAndStatusNotInOrderByPlacedAtDesc(me, TERMINAL).ifPresent(open -> {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You already have an order in progress");
        });
        Merchant merchant = merchants.findById(request.merchantId())
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such restaurant"));

        Map<UUID, Integer> qtyByItem = mergeLines(request.lines());
        Map<UUID, MenuItem> found = priceableItems(merchant, qtyByItem);

        OffsetDateTime now = OffsetDateTime.now();
        CustomerOrder order = new CustomerOrder(me, merchant.getId(), payments.currency(),
            request.note(), now.plus(timeline.total()));
        applyAddress(me, request, order);
        qtyByItem.forEach((itemId, qty) -> {
            MenuItem item = found.get(itemId);
            order.addLine(item.getId(), item.getName(), item.getPriceCents(), qty);
        });

        int subtotal = subtotalOf(qtyByItem, found);
        PromotionService.Applied applied = promotions.resolve(merchant.getId(), me,
            request.promotionCode(), subtotal, merchant.getDeliveryFeeCents());
        order.priceIt(Basket.of(subtotal, merchant.getDeliveryFeeCents(), serviceFeeCents,
            applied.discountCents(), request.tipCents(), payments.currency()),
            applied.promotionId(), applied.code());

        CustomerOrder saved = orders.save(order);
        payments.hold(saved, merchant.getName());
        promotions.redeem(applied, me, saved.getId());

        events.publishEvent(new OrderPlaced(saved.getId(), me, merchant.getId(), merchant.getName(),
            saved.getTotalCents(), saved.getCurrency(), saved.getPlacedAt()));
        return toOrderDto(saved, merchant);
    }

    /** Merges duplicate lines, so two "+1" taps on the same dish are one line. */
    private static Map<UUID, Integer> mergeLines(List<OrderLineRequest> lines) {
        Map<UUID, Integer> qtyByItem = new LinkedHashMap<>();
        for (OrderLineRequest line : lines) {
            qtyByItem.merge(line.menuItemId(), line.qty(), Integer::sum);
        }
        return qtyByItem;
    }

    /** The requested items, proven to be on this restaurant's menu and for sale. */
    private Map<UUID, MenuItem> priceableItems(Merchant merchant, Map<UUID, Integer> qtyByItem) {
        Map<UUID, MenuItem> found = menuItems
            .findForMerchant(merchant.getId(), qtyByItem.keySet()).stream()
            .collect(Collectors.toMap(MenuItem::getId, Function.identity()));
        if (found.size() != qtyByItem.size()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Some items are no longer on the menu");
        }
        if (found.values().stream().anyMatch(item -> !item.isAvailable())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Some items are sold out");
        }
        return found;
    }

    private static int subtotalOf(Map<UUID, Integer> qtyByItem, Map<UUID, MenuItem> found) {
        return qtyByItem.entrySet().stream()
            .mapToInt(entry -> found.get(entry.getKey()).getPriceCents() * entry.getValue())
            .sum();
    }

    /**
     * Resolves where the order is going: a saved address of the caller's, the
     * caller's default when none was named, or the legacy free-text label. An
     * order with nowhere to go is rejected — a courier needs an address.
     */
    private void applyAddress(UUID me, PlaceOrderRequest request, CustomerOrder order) {
        Address address = request.addressId() != null
            ? requireAddress(me, request.addressId())
            : addresses.findFirstByUserIdAndIsDefaultTrue(me).orElse(null);
        if (address != null) {
            order.deliverTo(address.getId(), address.getLabel(), address.getLine1(),
                address.getNote(), address.getLatitude(), address.getLongitude());
            return;
        }
        String label = request.addressLabel();
        if (label == null || label.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Add a delivery address first");
        }
        order.deliverTo(null, label, "", "", null, null);
    }

    @Transactional(readOnly = true)
    ActiveOrderResponse active(UUID me) {
        return new ActiveOrderResponse(orders
            .findFirstByUserIdAndStatusNotInOrderByPlacedAtDesc(me, TERMINAL)
            .map(this::toOrderDto)
            .orElse(null));
    }

    @Transactional(readOnly = true)
    List<OrderDto> history(UUID me, int limit) {
        List<CustomerOrder> past = orders.findByUserIdAndStatusInOrderByPlacedAtDesc(
            me, TERMINAL, PageRequest.of(0, Math.clamp(limit, 1, 50)));
        return decorate(past);
    }

    @Transactional(readOnly = true)
    OrderDto get(UUID me, UUID orderId) {
        return toOrderDto(require(me, orderId));
    }

    @Transactional
    OrderDto cancel(UUID me, UUID orderId) {
        CustomerOrder order = require(me, orderId);
        if (!CANCELLABLE.contains(order.getStatus())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                order.getStatus() == OrderStatus.CANCELLED
                    ? "That order is already cancelled"
                    : "Too late to cancel — your courier is on the way");
        }
        order.moveTo(OrderStatus.CANCELLED, OffsetDateTime.now());
        // Nothing was captured, so this is a release and not a refund: the money
        // never left the customer's own escrow.
        payments.release(order);
        events.publishEvent(new OrderStatusChanged(order.getId(), me,
            merchantName(order.getMerchantId()), OrderStatus.CANCELLED.name(), 0));
        return toOrderDto(order);
    }

    @Transactional
    OrderDto rate(UUID me, UUID orderId, int stars) {
        CustomerOrder order = require(me, orderId);
        if (order.getStatus() != OrderStatus.DELIVERED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You can rate an order once it's delivered");
        }
        order.rate(stars);
        return toOrderDto(order);
    }

    /**
     * A tip after the food arrived — 100% the courier's (SPECS §1), paid
     * straight through rather than through escrow, since there is nothing left
     * to hold it against and the work is already done.
     */
    @Transactional
    OrderDto tip(UUID me, UUID orderId, int tipCents) {
        CustomerOrder order = require(me, orderId);
        if (order.getStatus() != OrderStatus.DELIVERED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You can tip once your order has arrived");
        }
        payments.tipAfterDelivery(order, tipCents);
        return toOrderDto(order);
    }

    /** 404 rather than 403 for someone else's order — don't confirm it exists. */
    private CustomerOrder require(UUID me, UUID orderId) {
        return orders.findById(orderId)
            .filter(o -> o.getUserId().equals(me))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such order"));
    }

    // MARK: Fulfilment (called by OrderFulfilmentJob)

    /** Orders still in flight, oldest first. */
    @Transactional(readOnly = true)
    List<UUID> openOrderIds(int limit) {
        return orders.findByStatusNotInOrderByPlacedAtAsc(TERMINAL, PageRequest.of(0, limit))
            .stream().map(CustomerOrder::getId).toList();
    }

    /**
     * Walks one order up to wherever the timeline says it should be by now,
     * publishing every step it passes through. Recomputed from {@code placedAt}
     * each tick, so a missed run (or a restart) catches up rather than stalls.
     */
    @Transactional
    void advance(UUID orderId) {
        CustomerOrder order = orders.findById(orderId).orElse(null);
        if (order == null || order.getStatus().isTerminal()) {
            return;
        }
        OffsetDateTime now = OffsetDateTime.now();
        OrderStatus target = timeline.statusAt(Duration.between(order.getPlacedAt(), now));
        String merchantName = merchantName(order.getMerchantId());
        while (order.getStatus().ordinal() < target.ordinal()) {
            OrderStatus next = order.getStatus().next().orElseThrow();
            order.moveTo(next, now);
            if (next == OrderStatus.COURIER_TO_RESTAURANT) {
                assignCourier(order);
            }
            if (next == OrderStatus.DELIVERED) {
                // The food arrived: the hold becomes the merchant's, the
                // courier's and the platform's. Idempotent on the order, so a
                // second pass through DELIVERED cannot pay anyone twice.
                payments.settle(order, merchantName);
            }
            events.publishEvent(new OrderStatusChanged(order.getId(), order.getUserId(),
                merchantName, next.name(), etaMinutes(order, now)));
        }
    }

    /**
     * Picks the courier. Deterministic on the order id so every device (and a
     * retry) shows the same person — a random pick per read is how you end up
     * with a courier who changes name mid-delivery.
     */
    private static void assignCourier(CustomerOrder order) {
        Courier courier = Courier.ROSTER.get(
            Math.floorMod(order.getId().hashCode(), Courier.ROSTER.size()));
        order.assignCourier(courier.name(), courier.vehicle(),
            BigDecimal.valueOf(courier.rating()), courier.deliveries());
    }

    private record Courier(String name, String vehicle, double rating, int deliveries) {
        static final List<Courier> ROSTER = List.of(
            new Courier("Yassine B.", "Scooter · Yamaha", 4.94, 2140),
            new Courier("Sara L.", "E-bike", 4.88, 1675),
            new Courier("Mehdi K.", "Scooter · Honda", 4.97, 3020),
            new Courier("Amine T.", "On foot", 4.91, 890));
    }

    // MARK: Mapping

    private List<OrderDto> decorate(List<CustomerOrder> page) {
        if (page.isEmpty()) {
            return List.of();
        }
        Map<UUID, Merchant> byId = merchants
            .findAllById(page.stream().map(CustomerOrder::getMerchantId).collect(Collectors.toSet()))
            .stream().collect(Collectors.toMap(Merchant::getId, Function.identity()));
        return page.stream().map(o -> toOrderDto(o, byId.get(o.getMerchantId()))).toList();
    }

    private OrderDto toOrderDto(CustomerOrder order) {
        return toOrderDto(order, merchants.findById(order.getMerchantId()).orElse(null));
    }

    private OrderDto toOrderDto(CustomerOrder order, Merchant merchant) {
        OffsetDateTime now = OffsetDateTime.now();
        Duration elapsed = Duration.between(order.getPlacedAt(), now);
        CourierDto courier = order.getCourierName() == null ? null : new CourierDto(
            order.getCourierName(),
            order.getCourierVehicle(),
            order.getCourierRating() == null ? 0 : order.getCourierRating().doubleValue(),
            order.getCourierDeliveries() == null ? 0 : order.getCourierDeliveries());
        OrderMerchantDto merchantDto = merchant == null
            ? new OrderMerchantDto(order.getMerchantId(), "Restaurant", null, 0, 0)
            : new OrderMerchantDto(merchant.getId(), merchant.getName(), merchant.getImageUrl(),
                merchant.getLatitude(), merchant.getLongitude());
        return new OrderDto(
            order.getId(),
            merchantDto,
            order.getStatus().name(),
            etaMinutes(order, now),
            timeline.courierProgress(order.getStatus(), elapsed),
            courier,
            order.getLines().stream()
                .map(l -> new OrderLineDto(l.getMenuItemId(), l.getName(), l.getUnitPriceCents(), l.getQty()))
                .toList(),
            order.getSubtotalCents(),
            order.getDeliveryFeeCents(),
            order.getServiceFeeCents(),
            order.getTotalCents(),
            order.getDiscountCents(),
            order.getTipCents(),
            order.getPromotionCode(),
            order.getPaymentStatus().name(),
            order.getCurrency(),
            order.getAddressLabel(),
            new OrderAddressDto(order.getAddressId(), order.getAddressLabel(),
                order.getAddressLine(), order.getAddressNote(),
                order.getAddressLatitude(), order.getAddressLongitude()),
            order.getNote(),
            order.getRating(),
            order.getPlacedAt(),
            order.getStatusChangedAt(),
            order.getEtaAt());
    }

    /** Minutes left on the promise, floored at 1 while the order is still live. */
    private static int etaMinutes(CustomerOrder order, OffsetDateTime now) {
        if (order.getStatus().isTerminal()) {
            return 0;
        }
        long seconds = Duration.between(now, order.getEtaAt()).getSeconds();
        return (int) Math.max(1, Math.ceilDiv(seconds, 60));
    }

    private String merchantName(UUID merchantId) {
        return merchants.findById(merchantId).map(Merchant::getName).orElse("Restaurant");
    }

    private static MerchantDto toMerchantDto(Merchant merchant, boolean withMenu,
                                             StorefrontDocument storefront) {
        List<MenuSectionDto> menu = withMenu
            ? merchant.getMenu().stream()
                .sorted(Comparator.comparingInt(MenuSection::getSortOrder))
                .map(section -> new MenuSectionDto(section.getId(), section.getName(),
                    section.getItems().stream()
                        .filter(MenuItem::isAvailable)
                        .map(item -> new MenuItemDto(item.getId(), item.getName(), item.getDetail(),
                            item.getPriceCents(), item.getImageUrl(), item.isPopular()))
                        .toList()))
                .toList()
            : List.of();
        return new MerchantDto(
            merchant.getId(),
            merchant.getName(),
            merchant.getCuisine(),
            merchant.getRating().doubleValue(),
            merchant.getReviewCount(),
            merchant.getEtaMinutes(),
            merchant.getDeliveryFeeCents(),
            merchant.getImageUrl(),
            merchant.getPromo(),
            List.copyOf(merchant.getTags()),
            List.copyOf(merchant.getCategories()),
            merchant.getLatitude(),
            merchant.getLongitude(),
            menu,
            storefront);
    }
}
