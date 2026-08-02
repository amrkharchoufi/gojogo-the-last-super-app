package com.gojogo.dispatch;

import java.util.UUID;

/**
 * The courier twin of {@link DriverProvisioningApi}. Two interfaces over one
 * registry rather than one interface with a kind parameter, because the caller
 * is {@code partner} approving an application of a specific kind, and a
 * provisioning API that can be passed the wrong constant is a provisioning API
 * that will be.
 */
public interface CourierProvisioningApi {

    UUID provisionCourier(WorkerRegistration registration);

    void setCourierSuspended(UUID workerId, boolean suspended);

    void setCourierVehicle(UUID workerId, VehicleRef vehicle);
}
