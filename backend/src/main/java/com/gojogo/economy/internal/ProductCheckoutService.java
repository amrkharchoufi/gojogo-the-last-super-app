package com.gojogo.economy.internal;

import com.gojogo.economy.ProductOrderPlaced;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Checkout and the order lifecycle. One checkout is one seller (SPECS §6: one
 * cart per seller context) — a mixed basket is refused at the variant that
 * doesn't belong, by product name. Multi-seller checkout is the §5
 * parent/sub-order pattern and deliberately not built until somebody wants it.
 *
 * <p>Pricing is entirely server-side: the request carries variant ids,
 * quantities and at most a promotion code. Stock is taken inside the placement
 * transaction with a conditional update ({@code stock >= qty}), so overselling
 * loses the race rather than winning it; a cancellation puts the goods back.
 */
@Service
class ProductCheckoutService {

    private final ProductOrderRepository orders;
    private final ProductRepository products;
    private final ProductVariantRepository variants;
    private final SellerRegistry registry;
    private final ProductPromotionService promotions;
    private final ProductOrderPayments payments;
    private final DigitalDeliveryService digital;
    private final ApplicationEventPublisher events;

    ProductCheckoutService(ProductOrderRepository orders, ProductRepository products,
                           ProductVariantRepository variants, SellerRegistry registry,
                           ProductPromotionService promotions, ProductOrderPayments payments,
                           DigitalDeliveryService digital, ApplicationEventPublisher events) {
        this.orders = orders;
        this.products = products;
        this.variants = variants;
        this.registry = registry;
        this.promotions = promotions;
        this.payments = payments;
        this.digital = digital;
        this.events = events;
    }

    @Transactional
    ProductDtos.OrderResponse checkout(UUID buyerId, ProductDtos.CheckoutRequest request) {
        // Resolve every line to its variant and product, and pin the seller.
        Map<UUID, ProductVariant> byId = variants.findAllById(request.lines().stream()
                .map(ProductDtos.CheckoutLine::variantId).toList()).stream()
            .collect(Collectors.toMap(ProductVariant::getId, v -> v));
        Seller seller = null;
        int subtotal = 0;
        boolean anyDigital = false;
        boolean anyPhysical = false;
        for (ProductDtos.CheckoutLine line : request.lines()) {
            ProductVariant variant = byId.get(line.variantId());
            if (variant == null) {
                throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "No such item " + line.variantId());
            }
            Product product = variant.getProduct();
            if (!variant.isActive() || !product.isBrowsable()) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                    product.getName() + " is no longer available");
            }
            if (seller == null) {
                seller = registry.require(product.getSellerId());
            } else if (!seller.getId().equals(product.getSellerId())) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    product.getName() + " belongs to a different shop — one checkout is one shop");
            }
            if (product.getKind() == ProductKind.DIGITAL) anyDigital = true;
            else anyPhysical = true;
            subtotal += (int) (variant.getPriceCents() * line.quantity());
        }
        // A digital order completes at checkout and a physical one weeks later;
        // one order cannot be in both places, so a mixed basket is two baskets.
        if (anyDigital && anyPhysical) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Digital items check out on their own — split the basket");
        }
        if (anyDigital && !digital.allDeliverable(request.lines().stream()
                .map(l -> byId.get(l.variantId()).getProduct().getId()).distinct().toList())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "An item in this basket has no file behind it yet");
        }
        if (seller.isSuspended()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "This shop is closed");
        }
        if (seller.getOwnerUserId().equals(buyerId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "That's your own shop");
        }

        // Nothing ships on a digital basket, so nothing charges for shipping.
        int shipping = anyDigital ? 0 : seller.shippingFor(subtotal);
        ProductPromotionService.Applied applied = promotions.resolve(seller.getId(), buyerId,
            request.promotionCode(), subtotal, shipping);
        int discount = applied == null ? 0 : applied.discountCents();
        int tax = seller.taxOn(subtotal - discount);

        ProductOrder order = new ProductOrder(buyerId, seller.getId(),
            anyDigital ? "" : request.shipTo());
        for (ProductDtos.CheckoutLine line : request.lines()) {
            ProductVariant variant = byId.get(line.variantId());
            order.addLine(variant.getProduct().getId(), variant.getId(),
                variant.getProduct().getName(), variant.getLabel(),
                variant.getPriceCents(), line.quantity());
        }
        order.price(subtotal, discount, shipping, tax,
            applied == null ? null : applied.promotion().getId(),
            applied == null ? null : applied.promotion().getLabel());

        // Take the stock before the money: the conditional update is the
        // oversell guard, and a line that loses names its product in the 409.
        for (ProductDtos.CheckoutLine line : request.lines()) {
            if (variants.takeStock(line.variantId(), line.quantity()) == 0) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Not enough stock of " + byId.get(line.variantId()).getProduct().getName());
            }
        }

        ProductOrder saved = orders.save(order);
        if (applied != null) {
            promotions.recordRedemption(applied.promotion(), buyerId, saved.getId());
        }
        payments.hold(saved, seller.getDisplayName());
        if (anyDigital) {
            // Delivery is the entitlement, and it exists the moment the money
            // does — hold, settle and grant in the one transaction (SPECS §6:
            // "granted at capture"). No parcel, no confirmation to wait for.
            saved.completed(OffsetDateTime.now());
            payments.settle(saved, seller.getDisplayName());
            digital.grant(saved);
        }
        events.publishEvent(new ProductOrderPlaced(saved.getId(), seller.getId(),
            seller.getOwnerUserId(), buyerId, saved.getLines().size(), saved.getTotalCents()));
        return toResponse(saved, seller);
    }

    // MARK: Lifecycle

    /** The seller posted it. From here the parcel is moving and nobody cancels. */
    @Transactional
    ProductDtos.OrderResponse ship(UUID ownerUserId, UUID orderId, String trackingNote) {
        Seller seller = registry.requireMine(ownerUserId);
        ProductOrder order = sellers(seller, orderId);
        requireStatus(order, ProductOrderStatus.PLACED);
        order.shipped(trackingNote, OffsetDateTime.now());
        return toResponse(orders.save(order), seller);
    }

    /** The buyer has it — the money moves now, and only now. */
    @Transactional
    ProductDtos.OrderResponse confirmReceived(UUID buyerId, UUID orderId) {
        ProductOrder order = buyers(buyerId, orderId);
        requireStatus(order, ProductOrderStatus.SHIPPED);
        complete(order);
        return toResponse(order, registry.require(order.getSellerId()));
    }

    /** Either side backs out before shipping: full release, goods restocked. */
    @Transactional
    ProductDtos.OrderResponse cancelAsBuyer(UUID buyerId, UUID orderId) {
        ProductOrder order = buyers(buyerId, orderId);
        return cancel(order);
    }

    @Transactional
    ProductDtos.OrderResponse cancelAsSeller(UUID ownerUserId, UUID orderId) {
        Seller seller = registry.requireMine(ownerUserId);
        return cancel(sellers(seller, orderId));
    }

    /** The auto-complete sweep's verb — see {@code ProductOrderAutoCompleteJob}. */
    @Transactional
    void completeShipped(UUID orderId) {
        orders.findById(orderId).ifPresent(order -> {
            if (order.getStatus() != ProductOrderStatus.SHIPPED) return;
            complete(order);
        });
    }

    private void complete(ProductOrder order) {
        order.completed(OffsetDateTime.now());
        payments.settle(order, registry.require(order.getSellerId()).getDisplayName());
        orders.save(order);
    }

    private ProductDtos.OrderResponse cancel(ProductOrder order) {
        requireStatus(order, ProductOrderStatus.PLACED);
        order.cancelled(OffsetDateTime.now());
        payments.release(order);
        order.getLines().forEach(line -> variants.restock(line.getVariantId(), line.getQuantity()));
        return toResponse(orders.save(order), registry.require(order.getSellerId()));
    }

    // MARK: Reads

    @Transactional(readOnly = true)
    List<ProductDtos.OrderResponse> mine(UUID buyerId, int limit) {
        return decorate(orders.findByBuyerIdOrderByPlacedAtDesc(buyerId,
            PageRequest.of(0, Math.clamp(limit, 1, 100))));
    }

    @Transactional(readOnly = true)
    ProductDtos.OrderResponse get(UUID me, UUID orderId) {
        ProductOrder order = orders.findById(orderId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such order"));
        Seller seller = registry.require(order.getSellerId());
        if (!order.getBuyerId().equals(me) && !seller.getOwnerUserId().equals(me)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such order");
        }
        return toResponse(order, seller);
    }

    @Transactional(readOnly = true)
    List<ProductDtos.OrderResponse> sellerQueue(UUID ownerUserId, String status, int limit) {
        Seller seller = registry.requireMine(ownerUserId);
        PageRequest page = PageRequest.of(0, Math.clamp(limit, 1, 100));
        List<ProductOrder> queue = status == null || status.isBlank()
            ? orders.findBySellerIdOrderByPlacedAtDesc(seller.getId(), page)
            : orders.findBySellerIdAndStatusOrderByPlacedAtDesc(seller.getId(),
                parseStatus(status), page);
        return queue.stream().map(o -> toResponse(o, seller)).toList();
    }

    private List<ProductDtos.OrderResponse> decorate(List<ProductOrder> page) {
        return page.stream()
            .map(o -> toResponse(o, registry.require(o.getSellerId())))
            .toList();
    }

    private ProductOrder buyers(UUID buyerId, UUID orderId) {
        return orders.findById(orderId)
            .filter(o -> o.getBuyerId().equals(buyerId))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such order"));
    }

    private ProductOrder sellers(Seller seller, UUID orderId) {
        return orders.findById(orderId)
            .filter(o -> o.getSellerId().equals(seller.getId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such order"));
    }

    private static void requireStatus(ProductOrder order, ProductOrderStatus expected) {
        if (order.getStatus() != expected) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "The order is " + order.getStatus() + ", not " + expected);
        }
    }

    private static ProductOrderStatus parseStatus(String status) {
        try {
            return ProductOrderStatus.valueOf(status.trim().toUpperCase());
        } catch (IllegalArgumentException unknown) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown status " + status);
        }
    }

    private ProductDtos.OrderResponse toResponse(ProductOrder order, Seller seller) {
        return new ProductDtos.OrderResponse(
            order.getId(), order.getSellerId(), seller.getDisplayName(),
            order.getStatus().name(), order.getSubtotalCents(), order.getDiscountCents(),
            order.getShippingCents(), order.getTaxCents(), order.getTotalCents(),
            payments.currency(), order.getPromotionLabel(), order.getShipTo(),
            order.getTrackingNote(),
            order.getLines().stream()
                .map(l -> new ProductDtos.OrderLineResponse(l.getProductId(), l.getVariantId(),
                    l.getProductName(), l.getVariantLabel(), l.getUnitPriceCents(),
                    l.getQuantity(), l.getLineTotalCents()))
                .toList(),
            order.getPlacedAt(), order.getShippedAt(), order.getCompletedAt(),
            order.getCancelledAt());
    }
}
