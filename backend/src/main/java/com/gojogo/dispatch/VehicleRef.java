package com.gojogo.dispatch;

import java.util.UUID;

/**
 * The car, as much of it as dispatch is allowed to know.
 *
 * <p>Four facts, and every one of them arrives here by being <em>pushed down</em>
 * from {@code partner} at provisioning and whenever the driver switches vehicles
 * — never read across. A vehicle is papers and a plate somebody has to review,
 * which is squarely {@code partner}'s job; dispatch matches on one of these,
 * carries the rest, and has no opinion about any of them.
 *
 * <p>It exists as a record rather than four parameters because it grew from two
 * to four in Phase 3 M5 and would have grown a fifth eventually. A signature
 * with four adjacent strings and booleans in it is one somebody eventually calls
 * with the plate in the label.
 *
 * @param id       the {@code partner.vehicle} row, opaque here. Dispatch never
 *                 looks it up; it hands it back on an {@link Assignment} so the
 *                 vertical can put it on the trip, which is what lets a
 *                 passenger's verification land on the car they actually rode in
 *                 rather than on whatever is active by the time they answer
 * @param category the one field matching filters on
 * @param label    "White Dacia Logan", and {@code plate} beside it — the two
 *                 things that let somebody on a kerb tell which car is theirs
 * @param verified whether other passengers have confirmed this car is what it
 *                 says it is (Phase 3 M5). A badge, not a permission: an
 *                 unverified vehicle works exactly as before
 */
public record VehicleRef(UUID id, VehicleCategory category, String label, String plate,
                         boolean verified) {

    /** A courier on a bicycle, or a driver whose vehicle is flagged. Legitimate,
     *  and deliberately not null: "no vehicle" is a value, and a null here would
     *  be four null-checks in every caller. */
    public static VehicleRef none() {
        return new VehicleRef(null, null, "", "", false);
    }

    public VehicleRef {
        label = label == null ? "" : label;
        plate = plate == null ? "" : plate;
    }
}
