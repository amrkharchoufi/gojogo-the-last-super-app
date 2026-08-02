package com.gojogo.partner.internal;

import com.gojogo.config.ConfigApi;
import com.gojogo.dispatch.VehicleCategory;
import com.gojogo.media.MediaApi;
import com.gojogo.media.MediaDocumentApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * A car, its papers, and the rules that keep a verdict attached to the thing it
 * was given about.
 *
 * <p>The first test is the one that matters. Everything else here is bookkeeping;
 * "changing the plate keeps the approval" would be a working product with a hole
 * in the middle of it — register a scooter, get it approved, edit it into a car
 * nobody has seen.
 */
class VehicleLifecycleTests {

    private static final UUID ACCOUNT = UUID.randomUUID();
    private static final UUID OWNER = UUID.randomUUID();
    private static final LocalDate TODAY = LocalDate.of(2026, 8, 1);

    private VehicleRepository vehicles;
    private VehicleDocumentRepository documents;
    private VehicleService service;
    private PartnerAccount account;

    @BeforeEach
    void setUp() {
        vehicles = mock(VehicleRepository.class);
        documents = mock(VehicleDocumentRepository.class);
        VehiclePhotoRepository photos = mock(VehiclePhotoRepository.class);
        ConfigApi config = mock(ConfigApi.class);
        when(config.number(anyString(), anyLong()))
            .thenAnswer(call -> call.getArgument(1, Long.class));
        when(config.flag(anyString(), anyBoolean()))
            .thenAnswer(call -> call.getArgument(1, Boolean.class));
        when(photos.findByVehicleIdOrderBySortOrderAsc(any())).thenReturn(List.of());
        when(documents.findByVehicleIdOrderByKindAsc(any())).thenReturn(List.of());
        service = new VehicleService(vehicles, documents, photos,
            mock(VehicleVerificationRepository.class),
            mock(MediaDocumentApi.class), mock(MediaApi.class), config);
        account = new PartnerAccount(OWNER, PartnerKind.DRIVER, "Amina drives");
        setField(account, "id", ACCOUNT);
    }

    // MARK: The verdict follows the car, not the row

    @Test
    @DisplayName("changing the plate un-approves the vehicle — an edited plate is "
        + "a different car")
    void editingThePlateResetsTheVerdict() {
        Vehicle vehicle = approvedCar();

        vehicle.apply(VehicleCategory.CAR.name(), "Dacia", "Logan", 2019, "White",
            "77777-B-9", "Casablanca", TODAY.plusYears(1), TODAY.plusMonths(6));

        assertThat(vehicle.getState()).isEqualTo(VehicleState.SUBMITTED);
    }

    @Test
    @DisplayName("changing the category un-approves it too — a scooter approved as "
        + "a scooter is not an approved car")
    void editingTheCategoryResetsTheVerdict() {
        Vehicle vehicle = approvedCar();

        vehicle.apply(VehicleCategory.XL.name(), "Dacia", "Logan", 2019, "White",
            "12345-A-6", "Casablanca", TODAY.plusYears(1), TODAY.plusMonths(6));

        assertThat(vehicle.getState()).isEqualTo(VehicleState.SUBMITTED);
    }

    @Test
    @DisplayName("changing the colour does not — repainting a car is not describing "
        + "a new one")
    void cosmeticEditsKeepTheVerdict() {
        Vehicle vehicle = approvedCar();

        vehicle.apply(VehicleCategory.CAR.name(), "Dacia", "Logan", 2019, "Blue",
            "12345-A-6", "Casablanca", TODAY.plusYears(1), TODAY.plusMonths(6));

        assertThat(vehicle.getState()).isEqualTo(VehicleState.APPROVED);
    }

    // MARK: Flags

    @Test
    @DisplayName("flagging a vehicle stops it being the one dispatch matches on")
    void flaggingDeactivates() {
        Vehicle vehicle = approvedCar();
        vehicle.setActive(true);

        vehicle.flag("Insurance expired");

        // Otherwise the fastest way to keep working is to ignore the flag.
        assertThat(vehicle.isActive()).isFalse();
        assertThat(vehicle.getState()).isEqualTo(VehicleState.FLAGGED);
        assertThat(vehicle.getFlaggedAt()).isNotNull();
    }

    @Test
    @DisplayName("a new certificate puts a flagged vehicle back in the queue — and "
        + "does not approve it")
    void resubmittingIsAClaimNotAVerdict() {
        Vehicle vehicle = approvedCar();
        vehicle.flag("Insurance expired");

        vehicle.resubmit();

        assertThat(vehicle.getState()).isEqualTo(VehicleState.SUBMITTED);
        assertThat(vehicle.getReviewNote()).isNull();
    }

    @Test
    @DisplayName("resubmit does nothing to a vehicle that was never flagged")
    void resubmitOnlyAppliesToFlagged() {
        Vehicle vehicle = approvedCar();

        vehicle.resubmit();

        assertThat(vehicle.getState()).isEqualTo(VehicleState.APPROVED);
    }

    // MARK: Papers

    @Test
    @DisplayName("papers are only as good as the sooner of the two dates")
    void papersExpireOnTheEarlierDate() {
        Vehicle vehicle = approvedCar();
        vehicle.apply(VehicleCategory.CAR.name(), "Dacia", "Logan", 2019, "White",
            "12345-A-6", "Casablanca", LocalDate.of(2027, 1, 1), LocalDate.of(2026, 3, 1));

        // A car with insurance and a lapsed registration is as illegal as the
        // reverse, so the earlier one is the answer.
        assertThat(vehicle.papersValidUntil()).isEqualTo(LocalDate.of(2026, 3, 1));
        assertThat(vehicle.papersExpiredOn(TODAY)).isTrue();
    }

    @Test
    @DisplayName("a vehicle with no dates on file is not 'expired' — it is "
        + "incomplete, which is a different refusal")
    void missingDatesAreNotExpiry() {
        Vehicle vehicle = new Vehicle(ACCOUNT, OWNER, VehicleCategory.CAR.name());

        assertThat(vehicle.papersValidUntil()).isNull();
        assertThat(vehicle.papersExpiredOn(TODAY)).isFalse();
    }

    // MARK: What blocks a submission

    @Test
    @DisplayName("a driver with no vehicle is told to add one")
    void driversNeedAVehicle() {
        when(vehicles.findByAccountIdAndActiveTrue(ACCOUNT)).thenReturn(Optional.empty());

        assertThat(service.whatBlocksSubmission(account))
            .hasValueSatisfying(blocker -> assertThat(blocker).contains("add a vehicle"));
    }

    @Test
    @DisplayName("a courier is not — a bicycle has no registration to show")
    void couriersDoNotNeedAVehicle() {
        PartnerAccount courier = new PartnerAccount(OWNER, PartnerKind.COURIER, "Amina delivers");

        assertThat(service.isVehicleRequired(PartnerKind.COURIER)).isFalse();
        assertThat(service.whatBlocksSubmission(courier)).isEmpty();
    }

    @Test
    @DisplayName("the missing papers are named, both of them, in one message")
    void missingPapersAreNamedTogether() {
        Vehicle vehicle = activeCar();
        when(vehicles.findByAccountIdAndActiveTrue(ACCOUNT)).thenReturn(Optional.of(vehicle));
        when(documents.findByVehicleIdOrderByKindAsc(vehicle.getId())).thenReturn(List.of());

        assertThat(service.whatBlocksSubmission(account))
            .hasValueSatisfying(blocker -> assertThat(blocker)
                .contains("registration").contains("insurance"));
    }

    @Test
    @DisplayName("papers uploaded but undated is its own refusal, not 'expired'")
    void datesAreRequiredSeparately() {
        Vehicle vehicle = activeCar();
        vehicle.apply(VehicleCategory.CAR.name(), "Dacia", "Logan", 2019, "White",
            "12345-A-6", "Casablanca", null, null);
        when(vehicles.findByAccountIdAndActiveTrue(ACCOUNT)).thenReturn(Optional.of(vehicle));
        when(documents.findByVehicleIdOrderByKindAsc(vehicle.getId())).thenReturn(bothPapers(vehicle));

        assertThat(service.whatBlocksSubmission(account))
            .hasValueSatisfying(blocker -> assertThat(blocker).contains("expiry dates"));
    }

    @Test
    @DisplayName("a flagged vehicle blocks submission, and the message carries the "
        + "reviewer's own words")
    void flaggedVehicleBlocksWithItsNote() {
        Vehicle vehicle = activeCar();
        vehicle.flag("The plate in the photo doesn't match");
        when(vehicles.findByAccountIdAndActiveTrue(ACCOUNT)).thenReturn(Optional.of(vehicle));

        assertThat(service.whatBlocksSubmission(account))
            .hasValueSatisfying(blocker -> assertThat(blocker)
                .contains("doesn't match"));
    }

    @Test
    @DisplayName("a complete, current, papered vehicle blocks nothing")
    void aGoodVehiclePasses() {
        Vehicle vehicle = activeCar();
        when(vehicles.findByAccountIdAndActiveTrue(ACCOUNT)).thenReturn(Optional.of(vehicle));
        when(documents.findByVehicleIdOrderByKindAsc(vehicle.getId())).thenReturn(bothPapers(vehicle));

        assertThat(service.whatBlocksSubmission(account)).isEmpty();
    }

    // MARK: What dispatch is told

    @Test
    @DisplayName("dispatch matches on the active vehicle's category")
    void activeCategoryIsWhatDispatchGets() {
        Vehicle vehicle = activeCar();
        vehicle.apply(VehicleCategory.XL.name(), "Mercedes", "Vito", 2021, "Black",
            "12345-A-6", "Casablanca", TODAY.plusYears(1), TODAY.plusYears(1));
        when(vehicles.findByAccountIdAndActiveTrue(ACCOUNT)).thenReturn(Optional.of(vehicle));

        assertThat(service.activeCategory(ACCOUNT)).contains(VehicleCategory.XL);
    }

    @Test
    @DisplayName("a flagged active vehicle tells dispatch nothing rather than "
        + "a category it must not send work for")
    void aFlaggedVehicleNamesNoCategory() {
        Vehicle vehicle = activeCar();
        setField(vehicle, "active", true);
        vehicle.flag("Insurance expired");
        when(vehicles.findByAccountIdAndActiveTrue(ACCOUNT)).thenReturn(Optional.of(vehicle));

        assertThat(service.activeCategory(ACCOUNT)).isEmpty();
    }

    // MARK: Fixtures

    private Vehicle approvedCar() {
        Vehicle vehicle = new Vehicle(ACCOUNT, OWNER, VehicleCategory.CAR.name());
        setField(vehicle, "id", UUID.randomUUID());
        vehicle.apply(VehicleCategory.CAR.name(), "Dacia", "Logan", 2019, "White",
            "12345-A-6", "Casablanca", TODAY.plusYears(1), TODAY.plusMonths(6));
        vehicle.approve(null);
        return vehicle;
    }

    private Vehicle activeCar() {
        Vehicle vehicle = approvedCar();
        vehicle.setActive(true);
        return vehicle;
    }

    private static List<VehicleDocument> bothPapers(Vehicle vehicle) {
        return List.of(
            new VehicleDocument(vehicle.getId(), VehicleDocumentKind.REGISTRATION,
                "private/partner/x/1", "image/jpeg"),
            new VehicleDocument(vehicle.getId(), VehicleDocumentKind.INSURANCE,
                "private/partner/x/2", "image/jpeg"));
    }

    private static void setField(Object entity, String field, Object value) {
        try {
            Field f = entity.getClass().getDeclaredField(field);
            f.setAccessible(true);
            f.set(entity, value);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }
}
