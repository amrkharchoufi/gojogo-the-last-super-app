/**
 * Delivery module — food-delivery catalog, orders, and fulfilment state
 * ({@code delivery} schema). A vertical product surface (ARCHITECTURE.md §2/§6):
 * owns merchants, menus, and customer orders, and publishes
 * {@link com.gojogo.delivery.OrderPlaced} / {@link com.gojogo.delivery.OrderStatusChanged}
 * for future consumers (notifications, search, analytics).
 *
 * <p>Fulfilment is <em>simulated</em> until the platform {@code dispatch} module
 * exists (Phase 3): an order walks a server-side timeline rather than being
 * offered to a real courier. The state machine and the API around it are the
 * real thing — only the actor moving the order is fake — so wiring dispatch in
 * later replaces {@code OrderFulfilmentJob} and nothing else.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Delivery")
package com.gojogo.delivery;
