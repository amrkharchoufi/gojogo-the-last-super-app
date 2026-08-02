import Foundation

/// Driver Mode's API surface, and the driver-side half of partner onboarding
/// (Phase 3 M1/M2).
///
/// Two things live here because they are two ends of one journey: `partner`
/// owns everything up to a human saying yes, and `dispatch` owns everything
/// after it. Nothing in this file decides anything — the stake amount, whether a
/// submission is allowed, which vehicle dispatch matches on and how often to
/// report a position are all the server's answers, read rather than computed.
@MainActor
final class DispatchStore {

    static let shared = DispatchStore()

    // MARK: Driver Mode

    /// Registrations, whatever is on screen, and the job already taken — one
    /// call, because a phone on a motorbike should make as few round trips as it
    /// can.
    func me() async throws -> MyDispatchDTO {
        try await APIClient.shared.get("/v1/dispatch/me")
    }

    func setAvailable(_ available: Bool, kind: String) async throws -> DispatchWorkerDTO {
        try await APIClient.shared.post("/v1/dispatch/me/availability",
            body: DispatchAvailabilityBody(kind: kind, available: available))
    }

    /// The highest-frequency call this app makes. 204 and no body by design.
    func reportPosition(latitude: Double, longitude: Double) async throws {
        try await APIClient.shared.postNoContent("/v1/dispatch/me/position",
            body: DispatchPositionBody(latitude: latitude, longitude: longitude))
    }

    /// Takes the job — or throws a 409 naming who got there first, which is a
    /// normal outcome and not an error to hide.
    func accept(_ offerID: UUID) async throws -> DispatchAssignmentDTO {
        try await APIClient.shared.post("/v1/dispatch/offers/\(offerID)/accept")
    }

    func decline(_ offerID: UUID) async throws {
        try await APIClient.shared.post("/v1/dispatch/offers/\(offerID)/decline")
    }

    // MARK: Onboarding — the application

    func application(kind: String) async throws -> DriverApplicationDTO? {
        let response: MyDriverApplicationDTO =
            try await APIClient.shared.get("/v1/partner/me?kind=\(kind)")
        return response.account
    }

    func createApplication(kind: String, name: String, phone: String,
                           city: String) async throws -> DriverApplicationDTO {
        try await APIClient.shared.post("/v1/partner/applications",
            body: CreateDriverApplicationBody(kind: kind, businessName: name,
                                              contactName: name, contactPhone: phone,
                                              city: city))
    }

    /// Locks the stake. A 402 here carries the shortfall — the app's cue to
    /// offer a top-up for the right amount rather than a dead end.
    func payStake(_ applicationID: UUID) async throws -> DriverApplicationDTO {
        try await APIClient.shared.post("/v1/partner/applications/\(applicationID)/stake")
    }

    func submit(_ applicationID: UUID) async throws -> DriverApplicationDTO {
        try await APIClient.shared.post("/v1/partner/applications/\(applicationID)/submit")
    }

    func withdraw(_ applicationID: UUID) async throws -> DriverApplicationDTO {
        try await APIClient.shared.post("/v1/partner/applications/\(applicationID)/withdraw")
    }

    /// The one part of a licence that is typed rather than photographed. Its own
    /// endpoint because `POST /applications` is a whole-object upsert — sending
    /// that to record one number would blank everything the app doesn't know.
    func saveDriverLicenseNumber(_ applicationID: UUID,
                                 _ number: String) async throws -> DriverApplicationDTO {
        try await APIClient.shared.put(
            "/v1/partner/applications/\(applicationID)/driver-licence",
            body: SaveDriverLicenseBody(number: number))
    }

    /// Uploads a paper that belongs to the *applicant* rather than to a car —
    /// their driving licence. Same private prefix and the same two-step presign
    /// as a vehicle document; a different owner, which is why it hangs off the
    /// application and survives selling the car.
    func uploadApplicationDocument(_ applicationID: UUID, kind: String, data: Data,
                                   contentType: String) async throws -> DriverApplicationDTO {
        let presign: DocumentUploadDTO = try await APIClient.shared.post(
            "/v1/partner/applications/\(applicationID)/documents/presign",
            body: DocumentPresignBody(kind: kind, contentType: contentType))
        try await APIClient.shared.upload(to: presign.uploadUrl, data: data,
                                          contentType: presign.contentType)
        return try await APIClient.shared.put(
            "/v1/partner/applications/\(applicationID)/documents",
            body: AttachDocumentBody(kind: kind, objectKey: presign.objectKey,
                                     contentType: presign.contentType))
    }

    // MARK: Onboarding — the vehicle

    func addVehicle(_ applicationID: UUID,
                    _ body: SaveVehicleBody) async throws -> PartnerVehicleDTO {
        try await APIClient.shared.post("/v1/partner/applications/\(applicationID)/vehicles",
                                        body: body)
    }

    func editVehicle(_ applicationID: UUID, _ vehicleID: UUID,
                     _ body: SaveVehicleBody) async throws -> PartnerVehicleDTO {
        try await APIClient.shared.put(
            "/v1/partner/applications/\(applicationID)/vehicles/\(vehicleID)", body: body)
    }

    /// Which car you're driving today. Allowed after approval too — it is the
    /// one field dispatch matches on, and it changes more often than anything
    /// else on an application.
    func activateVehicle(_ applicationID: UUID,
                         _ vehicleID: UUID) async throws -> PartnerVehicleDTO {
        try await APIClient.shared.post(
            "/v1/partner/applications/\(applicationID)/vehicles/\(vehicleID)/activate")
    }

    /// Uploads one of the vehicle's papers. Private prefix — these never become
    /// a public URL, and the app keeps an object key it cannot read back.
    func uploadVehicleDocument(_ applicationID: UUID, _ vehicleID: UUID,
                               kind: String, data: Data,
                               contentType: String) async throws -> PartnerVehicleDTO {
        let presign: DocumentUploadDTO = try await APIClient.shared.post(
            "/v1/partner/applications/\(applicationID)/vehicles/\(vehicleID)/documents/presign",
            body: DocumentPresignBody(kind: kind, contentType: contentType))
        try await APIClient.shared.upload(to: presign.uploadUrl, data: data,
                                          contentType: presign.contentType)
        return try await APIClient.shared.put(
            "/v1/partner/applications/\(applicationID)/vehicles/\(vehicleID)/documents",
            body: AttachDocumentBody(kind: kind, objectKey: presign.objectKey,
                                     contentType: presign.contentType))
    }
}

// MARK: - Private-upload wire types

/// The wire names for the papers this app uploads. Strings rather than enums
/// because the server owns both lists — a build that doesn't know a kind should
/// ignore it, not fail to decode an application because of it.
enum PartnerDocumentKind {
    /// Both hang off the application rather than off a vehicle: a licence
    /// belongs to the person holding it, and stays theirs when the car is sold.
    /// Two kinds because the back is where the categories somebody may drive and
    /// the expiry are printed.
    static let driverLicenseFront = "DRIVER_LICENSE_FRONT"
    static let driverLicenseBack = "DRIVER_LICENSE_BACK"

    static let driverLicense = [driverLicenseFront, driverLicenseBack]
}

enum VehicleDocumentKind {
    static let registration = "REGISTRATION"
    static let insurance = "INSURANCE"
}

struct DocumentPresignBody: Encodable {
    let kind: String
    let contentType: String
}

struct DocumentUploadDTO: Decodable {
    let uploadUrl: String
    let objectKey: String
    let contentType: String
    let expiresSeconds: Int
}

struct SaveDriverLicenseBody: Encodable {
    let number: String
}

struct AttachDocumentBody: Encodable {
    let kind: String
    let objectKey: String
    let contentType: String
}
