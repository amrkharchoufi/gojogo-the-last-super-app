package com.gojogo.partner.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

import java.io.Serializable;
import java.util.Objects;
import java.util.UUID;

/**
 * A photo of the car. Ordinary public media — it ends up on a rider's screen
 * next to a plate number, which is the whole point of it. The papers are private
 * and these are not, and the two living in separate tables is what stops that
 * distinction being a boolean somebody gets wrong.
 */
@Entity
@Table(name = "vehicle_photo", schema = "partner")
@IdClass(VehiclePhoto.Key.class)
class VehiclePhoto {

    @Id
    @Column(name = "vehicle_id", nullable = false)
    private UUID vehicleId;

    @Id
    @Column(nullable = false, length = 600)
    private String url;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    protected VehiclePhoto() {
    }

    VehiclePhoto(UUID vehicleId, String url, int sortOrder) {
        this.vehicleId = vehicleId;
        this.url = url;
        this.sortOrder = sortOrder;
    }

    UUID getVehicleId() { return vehicleId; }
    String getUrl() { return url; }
    int getSortOrder() { return sortOrder; }

    /** Assigned key: saving one of these is a merge, never an insert — see the
     *  incidents log entry on @IdClass join entities. */
    record Key(UUID vehicleId, String url) implements Serializable {

        Key() {
            this(null, null);
        }

        @Override
        public boolean equals(Object other) {
            return other instanceof Key key
                && Objects.equals(vehicleId, key.vehicleId) && Objects.equals(url, key.url);
        }

        @Override
        public int hashCode() {
            return Objects.hash(vehicleId, url);
        }
    }
}
