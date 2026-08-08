package com.gojogo.assistant.internal;

/**
 * What the confirm card says a gated action is (MADELEINE.md §5 step 2).
 *
 * <p><b>Nothing here interpolates the model's arguments.</b> The summary is the
 * sentence a person reads before money moves, and text that reached it from
 * model output would be text a hostile listing could have written — "Free ride,
 * approve to claim" is a plausible thing to find in a marketplace description,
 * and the confirm card is precisely the surface that must not repeat it. So each
 * tool gets one fixed sentence naming the <em>kind</em> of commitment.
 *
 * <p>M4 replaces these with the real card: the exact amount from the owning
 * vertical's quote path, the restaurant's own name, the address the order is
 * going to — all read back from the vertical at approval time rather than
 * carried from the conversation.
 */
final class AssistantActionSummaries {

    private AssistantActionSummaries() {
    }

    static String summaryFor(String toolName) {
        return switch (toolName) {
            case "place_order" -> "Place the delivery order in your cart and pay for it "
                + "from your wallet.";
            case "request_ride" -> "Request a ride and open a fare negotiation with drivers.";
            case "accept_ride_offer" -> "Accept a driver's fare. This freezes the price.";
            case "cancel_ride" -> "Cancel your ride. This may incur a cancellation fee.";
            case "publish_listing" -> "Publish your listing so anyone on the marketplace "
                + "can see it.";
            case "publish_post" -> "Publish your post so your followers can see it.";
            case "book_service" -> "Book this appointment and commit to its price.";
            // A gated tool with no sentence of its own is still gated — the wall
            // does not depend on this file. It just asks less well.
            default -> "Confirm this action before it happens.";
        };
    }
}
