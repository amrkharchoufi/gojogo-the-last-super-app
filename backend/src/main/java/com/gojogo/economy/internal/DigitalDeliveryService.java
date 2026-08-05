package com.gojogo.economy.internal;

import com.gojogo.media.MediaDocumentApi;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.security.SecureRandom;
import java.time.OffsetDateTime;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Delivery of the products no courier will ever carry (SPECS §6): the asset a
 * seller attaches, the entitlements a capture grants, and the short-lived
 * signed GET a download actually is. Files live in the private prefix and the
 * entitlement row is the only durable proof of ownership — a URL that expired
 * is a URL that cannot leak.
 */
@Service
class DigitalDeliveryService {

    private static final SecureRandom RANDOM = new SecureRandom();

    private final DigitalAssetRepository assets;
    private final EntitlementRepository entitlements;
    private final ProductRepository products;
    private final SellerRegistry registry;
    private final MediaDocumentApi documents;

    DigitalDeliveryService(DigitalAssetRepository assets, EntitlementRepository entitlements,
                           ProductRepository products, SellerRegistry registry,
                           MediaDocumentApi documents) {
        this.assets = assets;
        this.entitlements = entitlements;
        this.products = products;
        this.registry = registry;
        this.documents = documents;
    }

    // MARK: Seller side

    /** A presigned PUT into the private prefix for the product's file. */
    MediaDocumentApi.DocumentUpload presignUpload(UUID ownerUserId, String contentType) {
        Seller seller = registry.requireMine(ownerUserId);
        return documents.presignDocumentUpload(seller.getId(), "digital", contentType);
    }

    /**
     * Attaches (or replaces) the file behind a DIGITAL product. Replacing keeps
     * every existing entitlement working — a buyer's download follows the
     * product, not the version they happened to buy.
     */
    @Transactional
    void attach(UUID ownerUserId, UUID productId, String objectKey, String fileName,
                String contentType, String entitlementKind) {
        Seller seller = registry.requireMine(ownerUserId);
        Product product = products.findById(productId)
            .filter(p -> p.getSellerId().equals(seller.getId()))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such product"));
        if (product.getKind() != ProductKind.DIGITAL) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Only a DIGITAL product takes an asset");
        }
        EntitlementKind kind = parseKind(entitlementKind);
        assets.findByProductId(productId).ifPresentOrElse(existing -> {
            String old = existing.getObjectKey();
            existing.replace(objectKey, fileName, contentType, kind);
            assets.save(existing);
            if (!old.equals(objectKey)) {
                documents.deleteDocument(old);
            }
        }, () -> assets.save(new DigitalAsset(productId, objectKey, fileName, contentType, kind)));
    }

    /** Whether every DIGITAL product in the set has a file to deliver — asked
     *  at checkout, because selling an empty download is not a race anybody
     *  should be able to win. */
    boolean allDeliverable(List<UUID> digitalProductIds) {
        if (digitalProductIds.isEmpty()) return true;
        return assets.findByProductIdIn(digitalProductIds).stream()
            .map(DigitalAsset::getProductId)
            .collect(Collectors.toSet())
            .containsAll(digitalProductIds);
    }

    // MARK: Grant + redeem

    /** Grants what a settled digital order owns — one entitlement per unit.
     *  Guarded by the order id: a retried settlement grants nothing twice. */
    @Transactional
    void grant(ProductOrder order) {
        if (entitlements.existsByOrderId(order.getId())) return;
        Map<UUID, DigitalAsset> byProduct = assets.findByProductIdIn(order.getLines().stream()
                .map(ProductOrderLine::getProductId).toList()).stream()
            .collect(Collectors.toMap(DigitalAsset::getProductId, a -> a));
        for (ProductOrderLine line : order.getLines()) {
            DigitalAsset asset = byProduct.get(line.getProductId());
            if (asset == null) continue;
            for (int unit = 0; unit < line.getQuantity(); unit++) {
                entitlements.save(new Entitlement(order.getBuyerId(), line.getProductId(),
                    order.getId(), asset.getEntitlementKind(),
                    asset.getEntitlementKind() == EntitlementKind.LICENSE ? newLicenseKey() : null));
            }
        }
    }

    @Transactional(readOnly = true)
    List<ProductDtos.EntitlementResponse> mine(UUID me, int limit) {
        List<Entitlement> page = entitlements.findByUserIdOrderByCreatedAtDesc(me,
            org.springframework.data.domain.PageRequest.of(0, Math.clamp(limit, 1, 100)));
        if (page.isEmpty()) return List.of();
        Map<UUID, Product> names = products.findAllById(page.stream()
                .map(Entitlement::getProductId).collect(Collectors.toSet())).stream()
            .collect(Collectors.toMap(Product::getId, p -> p));
        Map<UUID, DigitalAsset> files = assets.findByProductIdIn(page.stream()
                .map(Entitlement::getProductId).collect(Collectors.toSet())).stream()
            .collect(Collectors.toMap(DigitalAsset::getProductId, a -> a));
        return page.stream().map(e -> {
            Product product = names.get(e.getProductId());
            DigitalAsset asset = files.get(e.getProductId());
            return new ProductDtos.EntitlementResponse(e.getId(), e.getProductId(),
                product == null ? "Removed product" : product.getName(),
                e.getKind().name(), e.getLicenseKey(),
                asset == null ? "" : asset.getFileName(),
                e.getExpiresAt(), e.getCreatedAt());
        }).toList();
    }

    /** A fresh short-lived signed GET — minted per ask, never stored,
     *  re-issuable for as long as the entitlement lives. */
    @Transactional(readOnly = true)
    String downloadUrl(UUID me, UUID entitlementId) {
        Entitlement entitlement = entitlements.findById(entitlementId)
            .filter(e -> e.getUserId().equals(me))
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No such entitlement"));
        if (!entitlement.isLive(OffsetDateTime.now())) {
            throw new ResponseStatusException(HttpStatus.GONE, "This entitlement has expired");
        }
        DigitalAsset asset = assets.findByProductId(entitlement.getProductId())
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.CONFLICT,
                "The file behind this product is gone — contact the seller"));
        return documents.presignDocumentRead(asset.getObjectKey());
    }

    private static EntitlementKind parseKind(String value) {
        if (value == null || value.isBlank()) return EntitlementKind.DOWNLOAD;
        try {
            return EntitlementKind.valueOf(value.trim().toUpperCase());
        } catch (IllegalArgumentException unknown) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Unknown entitlement kind " + value);
        }
    }

    /** GOJO-XXXX-XXXX-XXXX-XXXX from 64 random bits — generated, not pooled
     *  (SPECS offers either; a pool is bookkeeping nobody asked for yet). */
    private static String newLicenseKey() {
        byte[] bytes = new byte[8];
        RANDOM.nextBytes(bytes);
        String hex = HexFormat.of().formatHex(bytes).toUpperCase();
        return "GOJO-" + hex.substring(0, 4) + "-" + hex.substring(4, 8)
            + "-" + hex.substring(8, 12) + "-" + hex.substring(12, 16);
    }
}
