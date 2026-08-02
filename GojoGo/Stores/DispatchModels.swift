import Foundation

// MARK: - Wire types (dispatch module, Phase 3 M1/M2)
//
// Driver Mode's whole server surface. Every field that arrived after a build
// shipped is optional, which is the same forward-compat discipline the rest of
// this app decodes with: a phone on a motorbike does not get to fail on a field
// it has never seen.
//
// Timestamps are `String`, never `Date`, and are parsed with `BackendDate` at
// the point of use. That is the codebase convention and it is load-bearing:
// `APIClient`'s shared decoder has no `dateDecodingStrategy`, so a `Date` field
// throws the moment the server actually sends a value — which is precisely the
// moment the thing being timestamped *succeeded*.

/// One registration — a person's place in the driver or the courier registry.
/// The same human may hold both; accepting anything in either makes them busy in
/// both, because there is one of them.
struct DispatchWorkerDTO: Decodable, Equatable {
    let id: UUID
    /// DRIVER | COURIER
    let kind: String
    /// The active vehicle's category (BIKE, CAR, XL…).
    let category: String
    /// OFFLINE | AVAILABLE | BUSY
    let status: String
    /// The platform's own switch, reported apart from `status` so the app can
    /// explain *why* going available was refused instead of looking broken.
    let suspended: Bool
    let homeRegion: String?
    let rating: Double
    let ratingCount: Int
    let completedCount: Int
    let cancelledCount: Int
    let latitude: Double?
    let longitude: Double?
    let positionAt: String?
    let last30Days: DispatchPerformanceDTO?

    var positionAtDate: Date? { positionAt.flatMap { BackendDate.parse($0) } }
}

/// The rolling window. Rates are `nil` — not zero — until something has been
/// offered: "0% acceptance" on a first day reads as an accusation.
struct DispatchPerformanceDTO: Decodable, Equatable {
    let offered: Int
    let accepted: Int
    let declined: Int
    let acceptanceRate: Double?
    let declineRate: Double?
}

/// A job on screen right now. It lives about thirty seconds.
struct DispatchOfferDTO: Decodable, Equatable, Identifiable {
    let id: UUID
    /// RIDE | DELIVERY
    let jobKind: String
    let jobRefId: UUID
    let workerKind: String
    let pickupLabel: String
    let pickupLatitude: Double
    let pickupLongitude: Double
    let dropoffLabel: String
    let dropoffLatitude: Double?
    let dropoffLongitude: Double?
    let note: String
    /// How far the pickup is from where this worker last reported being.
    let distanceKm: Double
    let expiresAt: String
    let offeredAt: String

    /// An unparseable expiry is treated as already gone rather than as forever:
    /// a stuck card on a driver's screen is worse than a missed offer.
    var expiresAtDate: Date { BackendDate.parse(expiresAt) ?? .distantPast }
    var offeredAtDate: Date? { BackendDate.parse(offeredAt) }
}

/// The job they took. Everything after "who is doing this" belongs to the
/// vertical that asked, which is why there is no fare here.
struct DispatchAssignmentDTO: Decodable, Equatable {
    let jobId: UUID
    let jobKind: String
    let jobRefId: UUID
    let workerId: UUID
    let workerKind: String
    let pickupLabel: String
    let pickupLatitude: Double
    let pickupLongitude: Double
    let dropoffLabel: String
    let dropoffLatitude: Double?
    let dropoffLongitude: Double?
    let note: String
    let assignedAt: String

    var assignedAtDate: Date? { BackendDate.parse(assignedAt) }
}

struct MyDispatchDTO: Decodable, Equatable {
    let workers: [DispatchWorkerDTO]
    let offers: [DispatchOfferDTO]
    let assignment: DispatchAssignmentDTO?
    /// How often to report a position while available. Told by the server
    /// because the cost of it is the server's problem.
    let positionIntervalSeconds: Int
}

struct DispatchAvailabilityBody: Encodable {
    let kind: String
    let available: Bool
}

struct DispatchPositionBody: Encodable {
    let latitude: Double
    let longitude: Double
}

// MARK: - Wire types (partner: the stake and the vehicles, Phase 3 M2)

/// The stake page, answered by the server so the app never hardcodes a price.
struct PartnerStakeDTO: Decodable, Equatable {
    let required: Bool
    let requiredMinor: Int
    let paidMinor: Int
    let kycFeeMinor: Int
    let remainingMinor: Int
    /// Set the instant the ledger movement lands — which made this the field
    /// that broke staking: as a `Date` it decoded fine while it was null and
    /// threw on the very response that reported success.
    let paidAt: String?
    let releasedAt: String?
    let currency: String
    let walletAvailableMinor: Int
    /// What is still missing from the wallet — which is what turns "you can't
    /// afford this" into a top-up button for the right amount.
    let shortfallMinor: Int

    var paidAtDate: Date? { paidAt.flatMap { BackendDate.parse($0) } }
    var releasedAtDate: Date? { releasedAt.flatMap { BackendDate.parse($0) } }

    var isPaid: Bool { paidAt != nil && releasedAt == nil }
}

struct PartnerVehicleDTO: Decodable, Equatable, Identifiable {
    let id: UUID
    let category: String
    let make: String
    let model: String
    let year: Int?
    let color: String
    let plate: String
    let region: String
    /// SUBMITTED | APPROVED | COMMUNITY_VERIFIED | FLAGGED | RETIRED
    let state: String
    let active: Bool
    let registrationExpiresOn: String?
    let insuranceExpiresOn: String?
    /// Computed by the server. An app that got this arithmetic wrong would tell
    /// somebody they can drive when they cannot.
    let papersExpired: Bool
    let reviewNote: String?
    let photoUrls: [String]?
    let missingDocuments: [String]?

    var isRoadworthy: Bool { state == "APPROVED" || state == "COMMUNITY_VERIFIED" }
    var isFlagged: Bool { state == "FLAGGED" }
}

struct SaveVehicleBody: Encodable {
    var category: String
    var make: String
    var model: String
    var year: Int?
    var color: String
    var plate: String
    var region: String
    /// `yyyy-MM-dd`, because a certificate expires on a day.
    var registrationExpiresOn: String?
    var insuranceExpiresOn: String?
    var photoUrls: [String]?
}

/// The full driver/courier application. A superset of the merchant-side
/// `PartnerAccountDTO` this app has decoded since 2b M6 — the same object, with
/// the fields onboarding needs and the merchant dashboard never asked for.
struct DriverApplicationDTO: Decodable, Equatable {
    let id: UUID
    let kind: String
    let status: String
    let businessName: String
    let reviewNote: String?
    let refId: UUID?
    let identityRequired: Bool?
    let identityStatus: String?
    let identityReason: String?
    let stake: PartnerStakeDTO?
    let vehicles: [PartnerVehicleDTO]?
    let vehicleRequired: Bool?
    /// The one sentence the server would refuse a submission with, answered in
    /// advance — so the app renders a checklist rather than discovering the
    /// rules one 400 at a time.
    let submitBlocker: String?
    let canEdit: Bool
    let canSubmit: Bool
    let submittedAt: String?

    var submittedAtDate: Date? { submittedAt.flatMap { BackendDate.parse($0) } }

    var activeVehicle: PartnerVehicleDTO? { (vehicles ?? []).first(where: \.active) }
}

struct MyDriverApplicationDTO: Decodable {
    let account: DriverApplicationDTO?
}

struct CreateDriverApplicationBody: Encodable {
    let kind: String
    let businessName: String
    let contactName: String
    let contactPhone: String
    let city: String
}
