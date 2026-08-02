/**
 * Delivery module — food-delivery catalog, orders, and fulfilment state
 * ({@code delivery} schema). A vertical product surface (ARCHITECTURE.md §2/§6):
 * owns merchants, menus, and customer orders, and publishes
 * {@link com.gojogo.delivery.OrderPlaced} / {@link com.gojogo.delivery.OrderStatusChanged}
 * for future consumers (notifications, search, analytics).
 *
 * <p>Restaurants come from the {@code partner} module, which owns onboarding
 * and KYC and calls
 * {@link com.gojogo.delivery.MerchantProvisioningApi#provisionMerchant} once a
 * human has approved an application. Delivery holds nothing but the resulting
 * {@code ownerId} stamp — it knows who manages a restaurant, never why they
 * were allowed to. Everything after provisioning (menu, prices, opening hours)
 * is the owner's, over this module's own {@code /v1/delivery/merchants/mine}
 * surface.
 *
 * <p><b>Fulfilment is real as of Phase 4 M1.</b> It used to be simulated: an
 * order walked a server-side timeline, a kitchen always took twenty seconds and
 * a courier was drawn from four hardcoded names. The state machine, the events
 * and the API were the real thing — only the actors were fake — and the swap
 * came out exactly as 2b M4 predicted: the six statuses, the two events and
 * every customer-facing endpoint are unchanged, and what was deleted was one
 * job and one class of durations. Now a restaurant accepts an order and says
 * how long it needs, that estimate schedules a courier search through the
 * platform {@code dispatch} module ({@code readyAt − pickupLead}, carried on
 * {@code DispatchRequest.startAfter}), and a courier who accepts, collects and
 * hands over is what moves the order the rest of the way — and is paid the
 * delivery fee and the tip that 2e M3 parked with the platform under their own
 * ledger kinds for exactly this milestone.
 *
 * <p><b>Phase 4 M2 makes the two courier taps provable</b>, and it does so by
 * composing two more platform modules rather than growing anything of its own. A
 * pickup code and a delivery PIN are minted when the restaurant accepts; a
 * contactless drop-off is photographed into {@code media}'s private prefix
 * ({@link com.gojogo.media.MediaDocumentApi}, the same mechanism a driving
 * licence uses, and for the same reason — no public URL, a signature per read);
 * and the courier and the customer get a thread through
 * {@link com.gojogo.messaging.MessagingApi} with a
 * {@link com.gojogo.messaging.ConversationContext} card back to the order. That
 * context is the seam 2b M3 built for a listing and 3 M3 reused for a ride, and
 * this is its third consumer with no change to {@code messaging} at all — which
 * is what a generic reference was for. Neither new dependency runs in the other
 * direction: {@code media} and {@code messaging} still know nothing about an
 * order. The six order statuses are, once again, unchanged.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Delivery")
package com.gojogo.delivery;
