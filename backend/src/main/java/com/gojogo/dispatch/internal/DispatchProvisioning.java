package com.gojogo.dispatch.internal;

import com.gojogo.dispatch.CourierProvisioningApi;
import com.gojogo.dispatch.DriverProvisioningApi;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.dispatch.WorkerKind;
import com.gojogo.dispatch.WorkerRegistration;
import org.springframework.stereotype.Service;

import java.util.UUID;

/**
 * The two doors {@code partner} comes through, over one registry.
 *
 * <p>Two interfaces rather than one with a kind parameter, because the caller is
 * approving an application of a specific kind and a provisioning API that can be
 * handed the wrong constant is one that eventually will be. The implementation
 * is four lines because that is genuinely all the difference amounts to.
 */
@Service
class DispatchProvisioning implements DriverProvisioningApi, CourierProvisioningApi {

    private final DispatchService dispatch;

    DispatchProvisioning(DispatchService dispatch) {
        this.dispatch = dispatch;
    }

    @Override
    public UUID provisionDriver(WorkerRegistration registration) {
        return provision(WorkerKind.DRIVER, registration);
    }

    @Override
    public void setDriverSuspended(UUID workerId, boolean suspended) {
        dispatch.setSuspended(WorkerKind.DRIVER, workerId, suspended);
    }

    @Override
    public void setDriverVehicle(UUID workerId, VehicleCategory category,
                                 String vehicleLabel, String vehiclePlate) {
        dispatch.setVehicle(WorkerKind.DRIVER, workerId, category, vehicleLabel, vehiclePlate);
    }

    @Override
    public UUID provisionCourier(WorkerRegistration registration) {
        return provision(WorkerKind.COURIER, registration);
    }

    @Override
    public void setCourierSuspended(UUID workerId, boolean suspended) {
        dispatch.setSuspended(WorkerKind.COURIER, workerId, suspended);
    }

    @Override
    public void setCourierVehicle(UUID workerId, VehicleCategory category,
                                  String vehicleLabel, String vehiclePlate) {
        dispatch.setVehicle(WorkerKind.COURIER, workerId, category, vehicleLabel, vehiclePlate);
    }

    private UUID provision(WorkerKind kind, WorkerRegistration registration) {
        return dispatch.provision(kind, registration.userId(), registration.partnerAccountId(),
            registration.category(), registration.homeRegion(),
            registration.vehicleLabel(), registration.vehiclePlate());
    }
}
