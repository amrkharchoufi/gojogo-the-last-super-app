package com.gojogo.partner.internal;

import com.gojogo.dispatch.CourierProvisioningApi;
import com.gojogo.dispatch.DriverProvisioningApi;
import com.gojogo.delivery.MerchantProvisioningApi;
import com.gojogo.kyc.IdentityStatus;
import com.gojogo.kyc.IdentityVerificationApi;
import com.gojogo.media.MediaApi;
import com.gojogo.media.MediaDocumentApi;
import com.gojogo.profile.ProfileApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.web.server.ResponseStatusException;

import java.lang.reflect.Field;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * What the server will and won't accept a submission with.
 *
 * <p>Every case here was, at some point, a Submit button that could not be
 * pressed or a 400 nobody could act on. The through-line: a requirement the
 * applicant has no way to satisfy is not a stricter check, it is a wall — so
 * each test is really asking "could a person finish this?".
 */
class PartnerSubmissionGateTests {

    private static final UUID OWNER = UUID.randomUUID();
    private static final UUID ACCOUNT = UUID.randomUUID();

    private PartnerAccountRepository accounts;
    private PartnerDocumentRepository documents;
    private VehicleService vehicles;
    private PartnerStakeService stakes;
    private IdentityVerificationApi identity;
    private PartnerService service;
    private PartnerAccount account;

    @BeforeEach
    void setUp() {
        accounts = mock(PartnerAccountRepository.class);
        documents = mock(PartnerDocumentRepository.class);
        vehicles = mock(VehicleService.class);
        stakes = mock(PartnerStakeService.class);
        identity = mock(IdentityVerificationApi.class);
        when(documents.findByAccountIdOrderByKindAsc(any())).thenReturn(List.of());
        // A vendor is configured and has said yes: this suite is about what
        // happens *after* identity, which is where the driver flow got stuck.
        when(identity.isConfigured()).thenReturn(true);
        when(identity.statusOf(any())).thenReturn(new IdentityVerificationApi.IdentityCheck(
            IdentityStatus.VERIFIED, null, List.of(), null, null));
        when(vehicles.isVehicleRequired(any())).thenReturn(true);
        when(vehicles.isDriverLicenseRequired(any())).thenReturn(true);
        when(vehicles.whatBlocksSubmission(any())).thenReturn(Optional.empty());
        when(vehicles.forAccount(any())).thenReturn(List.of());
        when(stakes.isStakeRequired(any())).thenReturn(false);
        service = new PartnerService(accounts, documents,
            mock(MerchantProvisioningApi.class), mock(DriverProvisioningApi.class),
            mock(CourierProvisioningApi.class), mock(MediaDocumentApi.class),
            mock(MediaApi.class), mock(ProfileApi.class), identity, vehicles, stakes,
            mock(ApplicationEventPublisher.class));
        account = new PartnerAccount(OWNER, PartnerKind.DRIVER, "Amina");
        setField(account, "id", ACCOUNT);
        account.apply("Amina", null, null, null, "Amina", null, null,
            null, null, null, null, null, null);
        when(accounts.findById(ACCOUNT)).thenReturn(Optional.of(account));
    }

    // MARK: The fields a driver is asked for

    @Test
    @DisplayName("a driver is not asked for a cuisine category, a trading address "
        + "or a shop phone — the flow has no field for any of them")
    void driversAreNotAskedForBusinessFields() {
        account.applyDriverLicenseNumber("ADJFIZBEVD");
        uploadedLicence();

        assertThat(service.submit(OWNER, ACCOUNT).status()).isEqualTo("SUBMITTED");
    }

    @Test
    @DisplayName("a restaurant still is — it really does trade somewhere")
    void restaurantsStillAreAskedForThem() {
        PartnerAccount shop = new PartnerAccount(OWNER, PartnerKind.RESTAURANT, "Café Amina");
        setField(shop, "id", ACCOUNT);
        shop.apply("Café Amina", null, null, null, "Amina", null, null,
            null, null, null, null, null, null);
        when(accounts.findById(ACCOUNT)).thenReturn(Optional.of(shop));
        when(vehicles.isDriverLicenseRequired(any())).thenReturn(false);
        when(vehicles.isVehicleRequired(any())).thenReturn(false);

        assertThatThrownBy(() -> service.submit(OWNER, ACCOUNT))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("category")
            .hasMessageContaining("address")
            .hasMessageContaining("city");
    }

    @Test
    @DisplayName("but a driver is asked for the number off their licence — the one "
        + "part of that card they type rather than photograph")
    void driversAreAskedForTheirLicenceNumber() {
        uploadedLicence();

        assertThatThrownBy(() -> service.submit(OWNER, ACCOUNT))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("licence number");
    }

    @Test
    @DisplayName("and not asked for it when nothing they drive needs a licence")
    void trottinetteRidersAreNotAskedForOne() {
        when(vehicles.isDriverLicenseRequired(any())).thenReturn(false);

        assertThat(service.submit(OWNER, ACCOUNT).status()).isEqualTo("SUBMITTED");
    }

    // MARK: The licence itself

    @Test
    @DisplayName("both sides of the licence are required, and the refusal names "
        + "the side that's missing")
    void bothSidesOfTheLicenceAreRequired() {
        account.applyDriverLicenseNumber("ADJFIZBEVD");
        when(documents.findByAccountIdOrderByKindAsc(ACCOUNT))
            .thenReturn(List.of(document(DocumentKind.DRIVER_LICENSE_FRONT)));

        assertThatThrownBy(() -> service.submit(OWNER, ACCOUNT))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("driving licence (back)");
    }

    @Test
    @DisplayName("a verified vendor identity does not stand in for a licence — "
        + "Sumsub says who you are, not that you may drive")
    void identityDoesNotReplaceTheLicence() {
        account.applyDriverLicenseNumber("ADJFIZBEVD");

        assertThatThrownBy(() -> service.submit(OWNER, ACCOUNT))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("driving licence");
    }

    // MARK: What the app renders instead of guessing

    @Test
    @DisplayName("the blocker names the missing papers, so a dead Submit button "
        + "always has a reason attached to it")
    void theBlockerNamesMissingDocuments() {
        account.applyDriverLicenseNumber("ADJFIZBEVD");

        PartnerAccountDto dto = service.saveDriverLicense(OWNER, ACCOUNT,
            new SaveDriverLicenseRequest("ADJFIZBEVD"));

        assertThat(dto.canSubmit()).isFalse();
        assertThat(dto.submitBlocker()).contains("driving licence");
        assertThat(dto.driverLicenseNumber()).isEqualTo("ADJFIZBEVD");
    }

    @Test
    @DisplayName("and says nothing once everything is on file")
    void aCompleteApplicationHasNoBlocker() {
        uploadedLicence();

        PartnerAccountDto dto = service.saveDriverLicense(OWNER, ACCOUNT,
            new SaveDriverLicenseRequest("  ADJFIZBEVD  "));

        assertThat(dto.submitBlocker()).isNull();
        assertThat(dto.canSubmit()).isTrue();
        // Trimmed on the way in — a trailing space is not part of a licence number.
        assertThat(dto.driverLicenseNumber()).isEqualTo("ADJFIZBEVD");
    }

    // MARK: Fixtures

    private void uploadedLicence() {
        when(documents.findByAccountIdOrderByKindAsc(ACCOUNT)).thenReturn(List.of(
            document(DocumentKind.DRIVER_LICENSE_FRONT),
            document(DocumentKind.DRIVER_LICENSE_BACK)));
    }

    private PartnerDocument document(DocumentKind kind) {
        PartnerDocument doc = new PartnerDocument(ACCOUNT, kind,
            "private/partner/" + OWNER + "/" + kind, "image/jpeg");
        setField(doc, "id", UUID.randomUUID());
        setField(doc, "uploadedAt", OffsetDateTime.now());
        return doc;
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
