/**
 * Economy module — the commerce vertical ({@code economy} schema). Two catalogs
 * that deliberately never merge (SPECS §6):
 *
 * <ul>
 * <li><b>C2C listings</b> — a person's one-off sale, chat-to-buy, no checkout.
 * The original surface, unchanged.</li>
 * <li><b>Merchant products</b> (Phase 5 M1) — a provisioned seller's catalog:
 * products with variants and counted stock, server-priced checkout through the
 * wallet ({@code hold → settle} on buyer confirmation, commission via
 * {@code FeeApi.ECONOMY}), promotions, and verified-purchase reviews. Sellers
 * arrive through {@link com.gojogo.economy.SellerProvisioningApi}, the
 * {@code MerchantProvisioningApi} pattern — {@code partner} creates what an
 * approval earns and never runs the shop.</li>
 * </ul>
 *
 * <p>Publishes {@link com.gojogo.economy.ListingCreated} and
 * {@link com.gojogo.economy.ProductUpserted} for search (Phase 5 M4) and
 * {@link com.gojogo.economy.ProductOrderPlaced} for the seller's push.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Economy")
package com.gojogo.economy;
