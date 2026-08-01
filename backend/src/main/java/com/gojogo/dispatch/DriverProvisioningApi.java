package com.gojogo.dispatch;

import java.util.UUID;

/**
 * How an approved partner becomes a driver — the landing place a {@code DRIVER}
 * approval has been refusing toward with a 409 since 2b M6.
 *
 * <p>Same shape and same direction as {@code delivery.MerchantProvisioningApi}:
 * {@code partner} owns the application and the human review, and gets to create
 * what an approval earns and to switch it off again. It does not get to run the
 * dispatch queue.
 *
 * <p>A provisioned driver starts <b>offline</b>. Being allowed to work and
 * wanting to work right now are different facts, and only the second one belongs
 * to the person holding the phone.
 */
public interface DriverProvisioningApi {

    /**
     * Registers the driver, or returns the id of the registration they already
     * have. Idempotent, so a retried approval cannot enrol somebody twice.
     */
    UUID provisionDriver(WorkerRegistration registration);

    /**
     * Blocks a driver from being offered work, or unblocks them. Held apart from
     * their own availability for the same reason {@code delivery.merchant} holds
     * {@code suspended} apart from {@code active}: lifting a platform block must
     * not put somebody on the road who had signed off.
     */
    void setDriverSuspended(UUID workerId, boolean suspended);
}
