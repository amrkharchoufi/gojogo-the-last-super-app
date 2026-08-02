package com.gojogo.notifications.internal;

import com.gojogo.partner.VehicleVerificationInvited;
import com.gojogo.travel.SosRaised;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.util.UUID;

/**
 * The two pushes Phase 3 M5 adds, and they could not be less alike.
 *
 * <p><strong>The verification invitation is the mechanism.</strong> A card
 * waiting inside an app somebody already closed is a card nobody answers, and an
 * unanswered invitation is a vehicle that never gets verified — so the push is
 * not a nicety here, it is how community verification happens at all. The reward
 * is in the body because it is the reason to tap.
 *
 * <p><strong>The SOS alert is the only push in this system that is worth waking
 * somebody up for.</strong> It goes to the emergency contacts who are also
 * GojoGo accounts, which is usually a subset — the rest are reached by a message
 * the phone itself sends. It deliberately does not go to the other party in the
 * car: telling a driver that their passenger has just raised an alarm about them
 * is not a safety feature.
 */
@Component
class SafetyNotificationListener {

    private final ApnsPushSender apns;

    SafetyNotificationListener(ApnsPushSender apns) {
        this.apns = apns;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onVerificationInvited(VehicleVerificationInvited event) {
        String car = event.vehicleLabel() == null || event.vehicleLabel().isBlank()
            ? "the car you just rode in" : event.vehicleLabel();
        String body = event.rewardMinor() > 0
            ? String.format("Confirm the plate and the driver, and we'll send you %s %.2f.",
                event.currency(), event.rewardMinor() / 100d)
            : "Confirm the plate and the driver — it takes a few seconds.";
        apns.notifySystem(event.passengerId(),
            "Was " + car + " what it said it was?", body,
            "vehicle-verification", event.verificationId());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onSosRaised(SosRaised event) {
        String who = event.raisedByName() == null || event.raisedByName().isBlank()
            ? "Someone you know" : event.raisedByName();
        String where = event.dropoffLabel() == null || event.dropoffLabel().isBlank()
            ? "" : " on the way to " + event.dropoffLabel();
        for (UUID contact : event.contactProfileIds()) {
            apns.notifySystem(contact,
                who + " needs help",
                "They raised an SOS during a GoJoGo trip" + where
                    + ". Tap to follow their trip.",
                "sos", event.rideId());
        }
    }
}
