package com.gojogo.economy.internal;

import com.gojogo.economy.ProductUpserted;
import com.gojogo.media.MediaApi;
import org.springframework.context.ApplicationEventPublisher;
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
 * The merchant catalog: a seller's CRUD and the public browse. Money never
 * moves here — checkout is {@code ProductCheckoutService}'s.
 */
@Service
class ProductCatalogService {

    private final ProductRepository products;
    private final SellerRepository sellers;
    private final SellerRegistry registry;
    private final MediaApi media;
    private final ApplicationEventPublisher events;

    ProductCatalogService(ProductRepository products, SellerRepository sellers,
                          SellerRegistry registry, MediaApi media,
                          ApplicationEventPublisher events) {
        this.products = products;
        this.sellers = sellers;
        this.registry = registry;
        this.media = media;
        this.events = events;
    }

    @Transactional
    ProductDtos.ProductResponse create(UUID ownerUserId, ProductDtos.CreateProductRequest request) {
        Seller seller = registry.requireMine(ownerUserId);
        ProductKind kind = ProductKind.PHYSICAL;
        if (request.kind() != null && !request.kind().isBlank()) {
            try {
                kind = ProductKind.valueOf(request.kind().trim().toUpperCase());
            } catch (IllegalArgumentException unknown) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Unknown product kind " + request.kind());
            }
        }
        Product product = new Product(seller.getId(), request.name().trim(),
            request.description(),
            blankTo(request.category(), "General"),
            blank(request.brand()), kind, request.specs());
        cleanUrls(request.imageUrls()).forEach(product::addMedia);
        for (ProductDtos.VariantRequest variant : request.variants()) {
            product.addVariant(blank(variant.sku()), variant.label().trim(),
                variant.priceCents(), variant.stock());
        }
        Product saved = products.save(product);
        markReferenced(request.imageUrls());
        publishUpserted(saved);
        return toResponse(saved, seller);
    }

    /**
     * Edits the page and replaces the variant set. A variant carrying its id is
     * updated in place — orders reference variant ids, so an edit must not
     * churn them; one without is new; one missing from the request is retired
     * ({@code active = false}) rather than deleted, because an order line may
     * point at it forever.
     */
    @Transactional
    ProductDtos.ProductResponse update(UUID ownerUserId, UUID productId,
                                       ProductDtos.CreateProductRequest request) {
        Seller seller = registry.requireMine(ownerUserId);
        Product product = owned(seller, productId);
        product.edit(request.name().trim(), request.description(),
            blankTo(request.category(), "General"), blank(request.brand()), request.specs());
        product.replaceMedia(cleanUrls(request.imageUrls()));

        Map<UUID, ProductDtos.VariantRequest> byId = request.variants().stream()
            .filter(v -> v.id() != null)
            .collect(Collectors.toMap(ProductDtos.VariantRequest::id, v -> v));
        for (ProductVariant variant : product.getVariants()) {
            ProductDtos.VariantRequest edit = byId.remove(variant.getId());
            if (edit == null) {
                variant.edit(variant.getSku(), variant.getLabel(), variant.getPriceCents(),
                    variant.getStock(), false);
            } else {
                variant.edit(blank(edit.sku()), edit.label().trim(), edit.priceCents(),
                    edit.stock(), edit.active());
            }
        }
        if (!byId.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown variant id " + byId.keySet().iterator().next());
        }
        request.variants().stream()
            .filter(v -> v.id() == null)
            .forEach(v -> product.addVariant(blank(v.sku()), v.label().trim(),
                v.priceCents(), v.stock()));

        Product saved = products.save(product);
        markReferenced(request.imageUrls());
        publishUpserted(saved);
        return toResponse(saved, seller);
    }

    /** Take the page out of the shop window, or put it back. Stock is untouched. */
    @Transactional
    ProductDtos.ProductResponse setActive(UUID ownerUserId, UUID productId, boolean active) {
        Seller seller = registry.requireMine(ownerUserId);
        Product product = owned(seller, productId);
        product.setActive(active);
        Product saved = products.save(product);
        publishUpserted(saved);
        return toResponse(saved, seller);
    }

    @Transactional(readOnly = true)
    List<ProductDtos.ProductResponse> mine(UUID ownerUserId, int limit) {
        Seller seller = registry.requireMine(ownerUserId);
        return products.findBySellerIdOrderByCreatedAtDesc(seller.getId(),
                PageRequest.of(0, Math.clamp(limit, 1, 100))).stream()
            .map(p -> toResponse(p, seller))
            .toList();
    }

    @Transactional(readOnly = true)
    ProductDtos.ProductPageResponse browse(String category, UUID sellerId,
                                           OffsetDateTime before, int limit) {
        OffsetDateTime cursor = before == null ? OffsetDateTime.now().plusMinutes(1) : before;
        int size = Math.clamp(limit, 1, 50);
        String cat = category == null || category.isBlank() || category.equalsIgnoreCase("All")
            ? null : category;
        List<Product> page = products.browse(cat, sellerId, cursor, PageRequest.of(0, size));
        List<ProductDtos.ProductResponse> items = decorate(page);
        OffsetDateTime nextBefore = page.size() < size ? null : page.getLast().getCreatedAt();
        return new ProductDtos.ProductPageResponse(items, nextBefore);
    }

    @Transactional(readOnly = true)
    ProductDtos.ProductResponse get(UUID me, UUID productId) {
        Product product = products.findById(productId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such product"));
        Seller seller = registry.require(product.getSellerId());
        boolean owner = seller.getOwnerUserId().equals(me);
        // Same 404 as never-existed: a hidden or suspended page must not be
        // distinguishable from a missing one to anybody but its owner.
        if (!owner && (!product.isBrowsable() || seller.isSuspended())) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No such product");
        }
        return toResponse(product, seller);
    }

    // MARK: Moderation + shared lookups

    @Transactional
    void setHidden(UUID productId, boolean hidden) {
        products.findById(productId).ifPresent(p -> {
            p.setHidden(hidden);
            products.save(p);
        });
    }

    @Transactional
    void removeAsModerator(UUID productId) {
        products.findById(productId).ifPresent(products::delete);
    }

    @Transactional(readOnly = true)
    java.util.Optional<Product> find(UUID productId) {
        return products.findById(productId);
    }

    List<ProductDtos.ProductResponse> decorate(List<Product> page) {
        if (page.isEmpty()) {
            return List.of();
        }
        Map<UUID, Seller> byId = sellers.findAllById(page.stream()
                .map(Product::getSellerId).collect(Collectors.toSet())).stream()
            .collect(Collectors.toMap(Seller::getId, s -> s));
        return page.stream()
            .map(p -> toResponse(p, byId.get(p.getSellerId())))
            .toList();
    }

    private Product owned(Seller seller, UUID productId) {
        Product product = products.findById(productId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such product"));
        if (!product.getSellerId().equals(seller.getId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your product");
        }
        return product;
    }

    private void publishUpserted(Product product) {
        events.publishEvent(new ProductUpserted(product.getId(), product.getSellerId(),
            product.getName(), product.getCategory(), product.getBrand(),
            product.isBrowsable(), OffsetDateTime.now()));
    }

    private void markReferenced(List<String> imageUrls) {
        List<String> clean = cleanUrls(imageUrls);
        if (!clean.isEmpty()) {
            media.markReferenced(clean);
        }
    }

    static ProductDtos.ProductResponse toResponse(Product product, Seller seller) {
        return new ProductDtos.ProductResponse(
            product.getId(),
            product.getSellerId(),
            seller == null ? "Shop" : seller.getDisplayName(),
            seller == null ? null : seller.getLogoUrl(),
            product.getName(),
            product.getDescription(),
            product.getCategory(),
            product.getBrand(),
            product.getKind().name(),
            product.getSpecs(),
            product.getMedia().stream().map(ProductMedia::getImageUrl).toList(),
            product.getVariants().stream()
                .map(v -> new ProductDtos.VariantResponse(v.getId(), v.getSku(), v.getLabel(),
                    v.getPriceCents(), v.getStock(), v.isActive()))
                .toList(),
            product.isActive(),
            product.getRatingCount() == 0 ? null
                : Math.round(product.getRatingSum() * 10.0 / product.getRatingCount()) / 10.0,
            product.getRatingCount(),
            product.getCreatedAt(),
            product.getUpdatedAt());
    }

    private static List<String> cleanUrls(List<String> urls) {
        return urls == null ? List.of() : urls.stream()
            .filter(u -> u != null && !u.isBlank())
            .toList();
    }

    private static String blank(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    private static String blankTo(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }
}
