package com.gojogo.delivery.internal;

import com.gojogo.delivery.OrderPlaced;
import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.WorkerPosition;
import com.gojogo.media.MediaDocumentApi;
import com.gojogo.storefront.StorefrontDocument;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.ArrayList;
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

    private static final Logger log = LoggerFactory.getLogger(DeliveryService.class);

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
    private final ApplicationEventPublisher events;
    private final OrderPayments payments;
    private final PromotionService promotions;
    private final MerchantStorefrontService storefronts;
    private final OrderFulfilmentService fulfilment;
    private final DispatchApi dispatch;
    private final DeliveryPolicy policy;
    private final MediaDocumentApi privateMedia;
    private final int serviceFeeCents;

    DeliveryService(MerchantRepository merchants, MenuItemRepository menuItems,
                    OrderRepository orders, AddressRepository addresses,
                    ApplicationEventPublisher events,
                    OrderPayments payments, PromotionService promotions,
                    MerchantStorefrontService storefronts,
                    OrderFulfilmentService fulfilment, DispatchApi dispatch,
                    DeliveryPolicy policy, MediaDocumentApi privateMedia,
                    @Value("${gojogo.delivery.service-fee-cents:99}") int serviceFeeCents) {
        this.merchants = merchants;
        this.menuItems = menuItems;
        this.orders = orders;
        this.addresses = addresses;
        this.events = events;
        this.payments = payments;
        this.promotions = promotions;
        this.storefronts = storefronts;
        this.fulfilment = fulfilment;
        this.dispatch = dispatch;
        this.policy = policy;
        this.privateMedia = privateMedia;
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
     * What this checkout would cost, without placing anything.
     *
     * <p>The point is the last three fields: the app can tell someone their
     * wallet is short <em>before</em> they commit to an order, and offer a
     * top-up for the right amount, rather than letting checkout fail with a 402.
     */
    @Transactional(readOnly = true)
    QuoteDto quote(UUID me, QuoteRequest request) {
        FulfilmentKind kind = FulfilmentKind.parse(request.fulfilmentKind());
        List<PricedBasket> priced = price(me, kind, basketsOf(request.baskets(),
            request.merchantId(), request.lines(), request.promotionCode()));
        Basket basket = Basket.of(priced.stream().map(PricedBasket::slice).toList(),
            serviceFeeCents, tipFor(kind, request.tipCents()), payments.currency());

        long available = payments.required() ? payments.availableFor(me) : Long.MAX_VALUE;
        boolean covers = !payments.required() || available >= basket.totalCents();
        // The flat promotion fields carry the first applied code, for the
        // pre-M3 client with one line to show it on.
        Basket.MerchantSlice first = priced.stream().map(PricedBasket::slice)
            .filter(s -> !s.promotionCode().isEmpty() || s.discountCents() > 0)
            .findFirst().orElse(null);
        return new QuoteDto(basket.subtotalCents(), basket.deliveryFeeCents(),
            basket.serviceFeeCents(), basket.discountCents(), basket.tipCents(),
            basket.totalCents(), basket.currency(),
            first == null ? "" : first.promotionCode(),
            first == null ? "" : first.promotionLabel(),
            kind.name(),
            priced.stream().map(p -> new MerchantQuoteDto(p.merchant().getId(),
                p.merchant().getName(), p.slice().subtotalCents(),
                p.slice().deliveryFeeCents(), p.slice().discountCents(),
                p.slice().promotionCode(), p.slice().promotionLabel())).toList(),
            payments.required() ? available : 0,
            covers, covers ? 0 : basket.totalCents() - available);
    }

    /**
     * Places an order — one checkout, however many kitchens — and holds the
     * money for it.
     *
     * <p>Prices come from the database, never from the request: the client sends
     * item ids and quantities only, and an item that isn't on its restaurant's
     * menu is rejected outright. The same is true of the discount — the request
     * may name a code, never an amount.
     *
     * <p>The funds move into the customer's own ESCROW bucket, not out of their
     * hands: cancelling in time releases them, and each merchant is paid when
     * the food arrives. A wallet that can't cover it raises
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
        FulfilmentKind kind = FulfilmentKind.parse(request.fulfilmentKind());
        List<PricedBasket> priced = price(me, kind, basketsOf(request.baskets(),
            request.merchantId(), request.lines(), request.promotionCode()));

        // The slowest restaurant's advertised ETA is the best guess anybody has
        // until the kitchens accept and say how long they actually need — which
        // is the number that replaces this one. For a collection it is the
        // kitchen's own pickup time, which is the whole point of that column:
        // an ETA that includes a courier's journey is a lie to somebody who is
        // walking there themselves.
        OffsetDateTime now = OffsetDateTime.now();
        int worstEta = priced.stream().mapToInt(p -> etaOf(p.merchant(), kind)).max().orElse(30);
        CustomerOrder order = new CustomerOrder(me, payments.currency(),
            request.note(), now.plusMinutes(worstEta));
        order.fulfilBy(kind);
        // How they want it handed over, if they said. A word this build doesn't
        // recognise is the configured default rather than a 400 — checkout is
        // the worst place in the product to fail on a string, and the choice is
        // changeable right up until the courier is at the door anyway.
        order.chooseHandoffMode(HandoffMode.parse(request.handoffMode(),
            policy.defaultHandoffMode()));
        applyAddress(me, request, order, kind);
        for (PricedBasket basket : priced) {
            SubOrder subOrder = order.addSubOrder(basket.merchant().getId(),
                basket.slice().subtotalCents(), basket.slice().deliveryFeeCents(),
                basket.slice().discountCents(), basket.applied().promotionId(),
                basket.applied().code());
            if (kind.isPickup()) {
                subOrder.collectFrom(basket.merchant().collectionAddress());
            }
            basket.qtyByItem().forEach((itemId, qty) -> {
                MenuItem item = basket.items().get(itemId);
                order.addLine(subOrder, item.getId(), item.getName(), item.getPriceCents(), qty);
            });
        }
        order.priceIt(Basket.of(priced.stream().map(PricedBasket::slice).toList(),
            serviceFeeCents, tipFor(kind, request.tipCents()), payments.currency()));

        CustomerOrder saved = orders.save(order);
        payments.hold(saved, priced.getFirst().merchant().getName()
            + (priced.size() > 1 ? " + " + (priced.size() - 1) + " more" : ""));
        for (PricedBasket basket : priced) {
            promotions.redeem(basket.applied(), me, saved.getId());
            // One event per kitchen: each owner is told about their slice and
            // only their slice. Under the simulation nothing had to be told; a
            // real kitchen that is never told has an order it can only time out.
            events.publishEvent(new OrderPlaced(saved.getId(), me,
                basket.merchant().getId(), basket.merchant().getName(),
                basket.merchant().getOwnerId(), basket.slice().merchantBaseCents(),
                saved.getCurrency(), saved.getPlacedAt()));
        }
        return toOrderDto(saved);
    }

    /**
     * The request's baskets, whichever shape they arrived in: the pre-M3
     * single-merchant fields become one basket, and a top-level promotion code
     * is stamped onto every basket that doesn't name its own — it is tried
     * per merchant and must land somewhere (see {@link #price}).
     */
    private List<BasketRequest> basketsOf(List<BasketRequest> baskets, UUID merchantId,
                                          List<OrderLineRequest> lines, String sharedCode) {
        List<BasketRequest> asked;
        if (baskets != null && !baskets.isEmpty()) {
            asked = baskets.stream()
                .map(b -> b.promotionCode() == null || b.promotionCode().isBlank()
                    ? new BasketRequest(b.merchantId(), b.lines(), sharedCode)
                    : b)
                .toList();
        } else if (merchantId != null && lines != null && !lines.isEmpty()) {
            asked = List.of(new BasketRequest(merchantId, lines, sharedCode));
        } else {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Add something to your basket first");
        }
        long distinct = asked.stream().map(BasketRequest::merchantId).distinct().count();
        if (distinct != asked.size()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "One basket per restaurant");
        }
        if (asked.size() > policy.maxMerchantsPerOrder()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "An order can span at most " + policy.maxMerchantsPerOrder() + " restaurants");
        }
        return asked;
    }

    /**
     * Prices every basket against its own merchant's menu.
     *
     * <p>A promotion code is resolved per merchant, because a promotion is one
     * merchant's own campaign. A shared code (typed once at checkout) is tried
     * against each basket and applied wherever it lands — but if it lands
     * nowhere, the first refusal is rethrown: somebody who typed WELCOME10 and
     * got nothing deserves to be told why, exactly as before.
     */
    private List<PricedBasket> price(UUID me, FulfilmentKind kind, List<BasketRequest> baskets) {
        List<PricedBasket> priced = new ArrayList<>(baskets.size());
        ResponseStatusException firstRefusal = null;
        boolean codeAskedAnywhere = false;
        boolean codeLandedAnywhere = false;
        for (BasketRequest basket : baskets) {
            Merchant merchant = merchants.findById(basket.merchantId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "No such restaurant"));
            // A collection at a counter that does not do collections. Refused
            // out loud rather than quietly turned into a delivery: the second
            // would charge somebody a delivery fee for a journey they were
            // planning to make themselves.
            if (kind.isPickup() && !merchant.isPickupEnabled()) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                    merchant.getName() + " doesn't do collection — order it for delivery instead");
            }
            Map<UUID, Integer> qtyByItem = mergeLines(basket.lines());
            Map<UUID, MenuItem> found = priceableItems(merchant, qtyByItem);
            int subtotal = subtotalOf(qtyByItem, found);
            // No courier, no fee. The one number that changes, and every other
            // consequence of a pickup's money — no tip, nothing under
            // COURIER_FEE at settlement — falls out of this and the tip above
            // rather than being decided again somewhere else.
            int deliveryFee = kind.isPickup() ? 0 : merchant.getDeliveryFeeCents();

            String code = basket.promotionCode();
            PromotionService.Applied applied;
            if (code != null && !code.isBlank()) {
                codeAskedAnywhere = true;
                try {
                    applied = promotions.resolve(merchant.getId(), me, code, subtotal,
                        deliveryFee, kind.isPickup());
                    codeLandedAnywhere = true;
                } catch (ResponseStatusException notHere) {
                    if (firstRefusal == null) firstRefusal = notHere;
                    // The code isn't this merchant's — fall back to whatever
                    // automatic promotion this kitchen runs.
                    applied = promotions.resolve(merchant.getId(), me, null, subtotal,
                        deliveryFee, kind.isPickup());
                }
            } else {
                applied = promotions.resolve(merchant.getId(), me, null, subtotal,
                    deliveryFee, kind.isPickup());
            }
            priced.add(new PricedBasket(merchant, qtyByItem, found, applied,
                Basket.MerchantSlice.of(merchant.getId(), subtotal,
                    deliveryFee, applied.discountCents(),
                    applied.promotionId(), applied.code(), applied.label())));
        }
        if (codeAskedAnywhere && !codeLandedAnywhere && firstRefusal != null) {
            throw firstRefusal;
        }
        return priced;
    }

    /**
     * A tip belongs to whoever carried the food, so a collection has none.
     *
     * <p>Dropped silently rather than refused, because a tip arrives as a
     * number on a checkout the customer may have switched to collection after
     * setting — failing the whole order over it would be punishing somebody for
     * changing their mind. What they are charged is what the quote showed, and
     * the quote drops it the same way.
     */
    private static int tipFor(FulfilmentKind kind, int tipCents) {
        return kind.isPickup() ? 0 : tipCents;
    }

    /** What to promise: the kitchen's own collection time for a pickup, their
     *  delivery ETA otherwise. */
    private static int etaOf(Merchant merchant, FulfilmentKind kind) {
        if (kind.isPickup() && merchant.getPickupPrepMinutes() != null) {
            return merchant.getPickupPrepMinutes();
        }
        return merchant.getEtaMinutes();
    }

    /** One basket, priced: the merchant, what's in it, and its money slice. */
    private record PricedBasket(Merchant merchant, Map<UUID, Integer> qtyByItem,
                                Map<UUID, MenuItem> items, PromotionService.Applied applied,
                                Basket.MerchantSlice slice) {
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
    private void applyAddress(UUID me, PlaceOrderRequest request, CustomerOrder order,
                              FulfilmentKind kind) {
        // A collection has no address to go to — it has a counter to be
        // collected from, which is the sub-order's and is copied there. Asking
        // for a delivery address anyway is how a pickup ends up needing a
        // saved address to exist before somebody can walk to a restaurant.
        if (kind.isPickup()) {
            return;
        }
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

    /**
     * The customer changes their mind about the whole order. Allowed right up
     * until a courier has any bag in their hands — a collected bag is food
     * someone has already cooked and carried, and taking the order out from
     * under it is a dispute rather than a button. Stands the courier down
     * through dispatch so they are free for the next offer.
     */
    @Transactional
    OrderDto cancel(UUID me, UUID orderId) {
        CustomerOrder order = require(me, orderId);
        if (!CANCELLABLE.contains(order.getStatus())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                order.getStatus() == OrderStatus.CANCELLED
                    ? "That order is already cancelled"
                    : "Too late to cancel — your courier has your order");
        }
        if (order.getSubOrders().stream().anyMatch(s -> s.getStatus() == SubOrderStatus.COLLECTED)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Too late to cancel — your courier has part of your order");
        }
        // Nothing was captured, so this is a release and not a refund: the money
        // never left the customer's own escrow.
        fulfilment.cancel(order, "You cancelled this order");
        return toOrderDto(order);
    }

    /**
     * The customer changes their mind about one kitchen (Phase 4 M3). Allowed
     * only while that restaurant hasn't answered — the SPECS §5 rule: once a
     * kitchen has accepted, food is being made, and backing out of it is theirs
     * to refuse. Exactly that slice's money goes back; the rest of the order is
     * untouched, unless this was the last live slice, in which case the whole
     * order ends and everything left comes back.
     */
    @Transactional
    OrderDto cancelSubOrder(UUID me, UUID orderId, UUID subOrderId) {
        CustomerOrder order = require(me, orderId);
        SubOrder sub = order.getSubOrders().stream()
            .filter(s -> subOrderId.equals(s.getId()))
            .findFirst()
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such part of this order"));
        if (sub.getStatus() != SubOrderStatus.CONFIRMED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                sub.getStatus() == SubOrderStatus.CANCELLED
                    ? "That part is already cancelled"
                    : "Too late — that restaurant is already cooking");
        }
        fulfilment.cancelSubOrder(order, sub, "You cancelled this part of your order");
        return toOrderDto(order);
    }

    /**
     * How they want the food handed over, changed in flight.
     *
     * <p>Changeable until the moment it happens, and that is the product
     * decision rather than a technical one: "leave it at the door" is what
     * somebody types when the courier is four minutes away and the baby has just
     * gone down, and a choice locked in at checkout would be a choice made
     * before the reason for it existed. Refused once the order is finished —
     * there is nothing left to hand over, and quietly accepting a change that
     * can no longer mean anything is worse than saying so.
     *
     * <p>Switching an order that predates {@code V38} to PIN does not conjure a
     * PIN: there is no code on that row, and the handoff falls back to a plain
     * confirm. Minting one here would be minting a number the customer has never
     * been shown.
     */
    @Transactional
    OrderDto setHandoffMode(UUID me, UUID orderId, String mode) {
        CustomerOrder order = require(me, orderId);
        if (order.getStatus().isTerminal()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                order.getStatus() == OrderStatus.DELIVERED
                    ? "That order has already been delivered"
                    : "That order was cancelled");
        }
        // There is no doorstep on a collection, so there is nothing to choose
        // between. Said out loud rather than accepted and ignored: a control
        // that stores a preference nothing will ever read is worse than one
        // that isn't there.
        if (order.isPickup()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You're collecting this one — show your code at the counter");
        }
        order.chooseHandoffMode(HandoffMode.parse(mode, policy.defaultHandoffMode()));
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
        // A tip is 100% the courier's (SPECS §1), and a collection had none.
        // Refused rather than quietly paid to the platform, which is what the
        // courier-account fallback in OrderPayments would otherwise do with it.
        if (order.isPickup()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "You collected this one — there's nobody to tip");
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

    // MARK: Mapping

    private List<OrderDto> decorate(List<CustomerOrder> page) {
        if (page.isEmpty()) {
            return List.of();
        }
        Map<UUID, Merchant> byId = merchantsOf(page);
        return page.stream().map(o -> toOrderDto(o, byId)).toList();
    }

    /** One query for every merchant these orders span, however many orders. */
    private Map<UUID, Merchant> merchantsOf(List<CustomerOrder> page) {
        return merchants
            .findAllById(page.stream()
                .flatMap(o -> o.getSubOrders().stream())
                .map(SubOrder::getMerchantId)
                .collect(Collectors.toSet()))
            .stream().collect(Collectors.toMap(Merchant::getId, Function.identity()));
    }

    private OrderDto toOrderDto(CustomerOrder order) {
        return toOrderDto(order, merchantsOf(List.of(order)));
    }

    private OrderDto toOrderDto(CustomerOrder order, Map<UUID, Merchant> merchantsById) {
        // The order's face for the pre-M3 fields: the first slice's restaurant.
        Merchant primary = order.getSubOrders().isEmpty() ? null
            : merchantsById.get(order.getSubOrders().getFirst().getMerchantId());
        // Where the courier actually is, straight from dispatch, rather than
        // where a timeline says somebody would be by now. Only while they are
        // carrying it: their position between jobs is nobody's business.
        WorkerPosition position = order.getStatus() == OrderStatus.DELIVERING
            && order.getCourierWorkerId() != null
            ? dispatch.positionOf(order.getCourierWorkerId()).orElse(null)
            : null;
        CourierDto courier = order.getCourierName() == null ? null : new CourierDto(
            order.getCourierName(),
            order.getCourierVehicle(),
            order.getCourierRating() == null ? 0 : order.getCourierRating().doubleValue(),
            order.getCourierDeliveries() == null ? 0 : order.getCourierDeliveries(),
            position == null ? null : position.latitude(),
            position == null ? null : position.longitude(),
            position == null ? null : position.at());
        OrderMerchantDto merchantDto = primary == null
            ? new OrderMerchantDto(order.getSubOrders().isEmpty() ? order.getId()
                : order.getSubOrders().getFirst().getMerchantId(), "Restaurant", null, 0, 0)
            : new OrderMerchantDto(primary.getId(), primary.getName(), primary.getImageUrl(),
                primary.getLatitude(), primary.getLongitude());
        String promotionCode = order.getSubOrders().stream()
            .map(SubOrder::getPromotionCode)
            .filter(code -> !code.isEmpty())
            .findFirst().orElse("");
        return new OrderDto(
            order.getId(),
            merchantDto,
            order.getStatus().name(),
            Eta.minutesLeft(order),
            order.getFulfilmentKind().name(),
            Eta.courierProgress(order,
                position == null ? null : position.latitude(),
                position == null ? null : position.longitude(),
                primary == null ? null : primary.getLatitude(),
                primary == null ? null : primary.getLongitude()),
            courier,
            order.getCourierSearch().name(),
            order.getCancelReason(),
            order.getReadyAt(),
            order.getLines().stream()
                .map(l -> new OrderLineDto(l.getMenuItemId(), l.getName(), l.getUnitPriceCents(), l.getQty()))
                .toList(),
            order.getSubOrders().stream()
                .map(sub -> toSubOrderDto(order, sub, merchantsById.get(sub.getMerchantId())))
                .toList(),
            order.getSubtotalCents(),
            order.getDeliveryFeeCents(),
            order.getServiceFeeCents(),
            order.getTotalCents(),
            order.getDiscountCents(),
            order.getTipCents(),
            promotionCode,
            order.getPaymentStatus().name(),
            order.getCurrency(),
            order.getAddressLabel(),
            new OrderAddressDto(order.getAddressId(), order.getAddressLabel(),
                order.getAddressLine(), order.getAddressNote(),
                order.getAddressLatitude(), order.getAddressLongitude()),
            order.getNote(),
            order.getRating(),
            order.getHandoffMode().name(),
            visiblePin(order),
            proofPhotoUrl(order),
            order.getConversationId(),
            order.getPlacedAt(),
            order.getStatusChangedAt(),
            order.getEtaAt());
    }

    private static SubOrderDto toSubOrderDto(CustomerOrder order, SubOrder sub,
                                             Merchant merchant) {
        return new SubOrderDto(
            sub.getId(),
            sub.getMerchantId(),
            merchant == null ? "Restaurant" : merchant.getName(),
            merchant == null ? null : merchant.getImageUrl(),
            sub.getStatus().name(),
            sub.getStatus() == SubOrderStatus.CONFIRMED && !order.getStatus().isTerminal(),
            order.getLines().stream()
                .filter(l -> l.belongsTo(sub))
                .map(l -> new OrderLineDto(l.getMenuItemId(), l.getName(),
                    l.getUnitPriceCents(), l.getQty()))
                .toList(),
            sub.getSubtotalCents(),
            sub.getDeliveryFeeCents(),
            sub.getDiscountCents(),
            sub.getPromotionCode(),
            sub.getPrepMinutes() == null ? 0 : sub.getPrepMinutes(),
            sub.getReadyAt(),
            sub.getCollectedAt(),
            sub.getCancelReason(),
            collectionCode(order, sub),
            sub.getReadyMarkedAt() != null && sub.getStatus() == SubOrderStatus.PREPARING,
            sub.getPickupAddress(),
            order.isPickup() && merchant != null ? merchant.getLatitude() : null,
            order.isPickup() && merchant != null ? merchant.getLongitude() : null,
            sub.getReadyMarkedAt());
    }

    /**
     * The digits the customer holds up at that counter — and the mirror image
     * of {@code visiblePin} below, which is the same rule about the same kind
     * of secret.
     *
     * <p>Only for a collection, and only while there is still something to
     * collect: a code that outlives its handoff is a number sitting in a
     * screenshot and in a history screen for a year. On a delivery it stays
     * empty here, because there it is the <em>kitchen</em> that shows it and a
     * customer who could read it could mark their own food collected.
     */
    private static String collectionCode(CustomerOrder order, SubOrder sub) {
        return order.isPickup() && sub.getStatus() == SubOrderStatus.PREPARING
            ? sub.getPickupCode()
            : "";
    }

    /**
     * The PIN, and only while it is the thing that opens the door.
     *
     * <p>Blank once the order is finished or the mode is not PIN, because a PIN
     * that outlives its handoff is a number sitting in a screenshot and in a
     * history screen for a year — and the one place it could ever be read from
     * is the customer's own order, since it is on no other DTO in the system.
     * There is nothing to hide it from except time.
     */
    private static String visiblePin(CustomerOrder order) {
        return order.getStatus().isTerminal() || order.getHandoffMode() != HandoffMode.PIN
            || order.isPickup()
            ? ""
            : order.getDeliveryPin();
    }

    /**
     * A signed link to the drop-off photo, minted for this one read.
     *
     * <p>Never the object key: the key is the handle the server keeps, and a
     * link that has expired is a link that cannot leak — the same posture
     * {@code MediaDocumentApi} takes with a driving licence, for a photograph of
     * somebody's front door with their dinner on it. Only once the order is
     * DELIVERED, because before that a photo on the row is a courier's failed
     * attempt rather than proof of anything.
     *
     * <p>Signing failures fall back to null rather than failing the read: the
     * order screen is how a customer finds out what happened to their food, and
     * it must not go blank because S3 was slow.
     */
    private String proofPhotoUrl(CustomerOrder order) {
        if (order.getStatus() != OrderStatus.DELIVERED || order.getProofPhotoKey() == null) {
            return null;
        }
        try {
            return privateMedia.presignDocumentRead(order.getProofPhotoKey());
        } catch (RuntimeException mediaIsHavingAMoment) {
            log.warn("Couldn't sign the proof photo for order {}: {}",
                order.getId(), mediaIsHavingAMoment.toString());
            return null;
        }
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
            storefront,
            merchant.isPickupEnabled(),
            merchant.getPickupPrepMinutes() == null
                ? merchant.getEtaMinutes() : merchant.getPickupPrepMinutes(),
            merchant.getPickupAddress());
    }
}
