package com.gojogo.delivery.internal;

import com.gojogo.dispatch.DispatchApi;
import com.gojogo.dispatch.WorkerPosition;
import com.gojogo.share.ShareableResource;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;
import java.util.UUID;

/**
 * What a shared delivery looks like to somebody with no account (Phase 4 M6).
 *
 * <p>The fifth platform-defines / vertical-implements seam and the second
 * implementation of this one, after {@code travel}'s. It cost {@code share}
 * nothing — no new verb, no new column, no branch that knows what an order is —
 * which is the return on having made the SPI generic in Phase 3 M5 rather than
 * writing a rides-shaped one. The prediction that "delivery can share an order
 * later without share learning what one is" was written into that milestone's
 * notes; this is it being true.
 *
 * <p><b>Two things it is for, and the second is why it lands in this
 * milestone.</b> One is the obvious share — sending a friend a link to watch
 * dinner arrive. The other is ordering for somebody else: a recipient with no
 * GojoGo account has no other way to see where their food is, and the link is
 * the whole of what makes "order for someone else" more than a name typed into
 * a box.
 *
 * <p><b>What a stranger is allowed to see was chosen by asking what a link
 * found in a group chat should give away.</b> First names only, and the
 * recipient's rather than the payer's — the payer's name is nobody's business
 * at the door. No address beyond the label the customer chose for it, no phone
 * number (least of all the recipient's, which the courier never sees either),
 * no total, no items, and nothing that could be used to message anybody. The
 * PIN is emphatically not here: it is the thing that proves the person at the
 * door is the right one, and putting it on a link would make the link the
 * delivery.
 */
@Component
class OrderShareableResource implements ShareableResource {

    static final String KIND = "order";

    private final OrderRepository orders;
    private final MerchantRepository merchants;
    private final DispatchApi dispatch;

    OrderShareableResource(OrderRepository orders, MerchantRepository merchants,
                           DispatchApi dispatch) {
        this.orders = orders;
        this.merchants = merchants;
        this.dispatch = dispatch;
    }

    @Override
    public String kind() {
        return KIND;
    }

    /**
     * Rendered on every read, never at mint time — the rule this SPI exists to
     * enforce. A link that showed where the courier was when it was created
     * would be a screenshot.
     */
    @Override
    @Transactional(readOnly = true)
    public Optional<SharedView> render(UUID orderId) {
        CustomerOrder order = orders.findById(orderId).orElse(null);
        if (order == null) {
            return Optional.empty();
        }
        // A cancelled order has nothing to watch, and an old delivered one has
        // nothing left to say either. Delivered stays visible for a while so the
        // person who was sent the link can see it actually arrived — the
        // question they opened it to answer.
        if (order.getStatus() == OrderStatus.CANCELLED) {
            return Optional.empty();
        }
        String from = order.getSubOrders().stream().findFirst()
            .map(SubOrder::getMerchantId)
            .flatMap(merchants::findById)
            .map(Merchant::getName)
            .orElse("a restaurant");
        boolean finished = order.getStatus() == OrderStatus.DELIVERED;

        return Optional.of(new SharedView(
            headline(order, from),
            status(order),
            // The courier's first name and their vehicle, which is what
            // somebody watching actually wants — is a person coming, and on
            // what. Never a rating, never a full name.
            order.getCourierName() == null ? null
                : firstName(order.getCourierName())
                    + (order.getCourierVehicle() == null || order.getCourierVehicle().isBlank()
                        ? "" : " · " + order.getCourierVehicle()),
            position(order) == null ? null : position(order).latitude(),
            position(order) == null ? null : position(order).longitude(),
            finished ? null : Eta.minutesLeft(order),
            // The label the customer gave the address ("Home", "Mum's"), never
            // the street. A watcher wants to know it is going to the right
            // place, not how to get there.
            order.isPickup() ? "Collection" : order.getAddressLabel(),
            finished));
    }

    /** "Dinner from Forno Nero, on its way to Sara" — first names, and the
     *  recipient's when there is one. */
    private static String headline(CustomerOrder order, String merchantName) {
        String to = order.doorName();
        if (to.isBlank()) {
            return "An order from " + merchantName;
        }
        return "An order from " + merchantName + " for " + firstName(to);
    }

    /**
     * A sentence, already worded for a reader — the SPI's own rule that this
     * module must not make {@code share} translate an enum.
     */
    private static String status(CustomerOrder order) {
        if (order.isPickup()) {
            return switch (order.getStatus()) {
                case DELIVERED -> "Collected";
                case CONFIRMED -> "Waiting for the kitchen";
                default -> "Being prepared for collection";
            };
        }
        return switch (order.getStatus()) {
            case CONFIRMED -> "Waiting for the kitchen";
            case PREPARING -> "Being prepared";
            case COURIER_TO_RESTAURANT -> "A courier is on the way to collect it";
            case DELIVERING -> "On the way";
            case DELIVERED -> "Delivered";
            case CANCELLED -> "Cancelled";
        };
    }

    /** Only while somebody is actually carrying it: where a courier is between
     *  jobs is nobody's business, and least of all a stranger's. */
    private WorkerPosition position(CustomerOrder order) {
        if (order.getStatus() != OrderStatus.DELIVERING || order.getCourierWorkerId() == null) {
            return null;
        }
        return dispatch.positionOf(order.getCourierWorkerId()).orElse(null);
    }

    private static String firstName(String name) {
        String trimmed = name.trim();
        int space = trimmed.indexOf(' ');
        return space > 0 ? trimmed.substring(0, space) : trimmed;
    }
}
