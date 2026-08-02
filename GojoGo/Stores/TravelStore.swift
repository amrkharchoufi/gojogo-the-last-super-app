import Foundation

// MARK: - Wire types (travel module, Phase 3 M3)

/// One category's price, from the server. The app never computes a fare.
struct RideQuoteCategoryDTO: Decodable, Equatable {
    let category: String
    let suggestedFareMinor: Int
    /// The floor a negotiation may not go under — shown, because "make me an
    /// offer" needs a stated bottom.
    let minimumMinor: Int
}

struct RideQuoteDTO: Decodable, Equatable {
    let distanceMetres: Int
    let durationSeconds: Int
    let currency: String
    let categories: [RideQuoteCategoryDTO]
}

/// A price on the table. `party` decides who may accept it — nobody accepts
/// their own.
struct RideOfferDTO: Decodable, Equatable, Identifiable {
    let id: UUID
    let rideId: UUID
    /// RIDER | DRIVER
    let party: String
    let amountMinor: Int
    let round: Int
    let state: String
    let driverId: UUID?
    let driverName: String?
    let driverAvatarUrl: String?
    let expiresAt: Date
    let createdAt: Date
}

/// The ride, from whichever side is looking at it.
struct RideDTO: Decodable, Equatable, Identifiable {
    let id: UUID
    /// REQUESTED | NEGOTIATING | CONFIRMED | ARRIVING | IN_TRIP | COMPLETED
    /// | CANCELLED_RIDER | CANCELLED_DRIVER | EXPIRED
    let state: String
    let category: String
    let pickupLabel: String
    let pickupLatitude: Double
    let pickupLongitude: Double
    let dropoffLabel: String
    let dropoffLatitude: Double
    let dropoffLongitude: Double
    let note: String?
    let distanceMetres: Int
    let durationSeconds: Int
    let suggestedFareMinor: Int
    let offeredFareMinor: Int
    let agreedFareMinor: Int?
    let currency: String
    let cancelFeeMinor: Int?
    /// What this trip cost the driver in ride tokens — **nil to the rider**.
    /// The price list is public; what the driver paid for the job is not a line
    /// on a passenger's receipt.
    let tokenCost: Int?
    let otherPartyId: UUID?
    let otherPartyName: String?
    let otherPartyAvatarUrl: String?
    let vehicleLabel: String?
    let vehiclePlate: String?
    /// Passengers have confirmed this car is what it claims to be (Phase 3 M5).
    /// A snapshot taken when the trip was matched, so an old receipt never
    /// retroactively claims a badge the car didn't have at the time.
    let vehicleVerified: Bool?
    /// Where the car is right now — read from dispatch per request, so it can
    /// never be a stale copy.
    let driverLatitude: Double?
    let driverLongitude: Double?
    let driverPositionAt: Date?
    let conversationId: UUID?
    let offers: [RideOfferDTO]?
    let myRating: Int?
    /// Null until both sides have rated: reading a one-star before writing your
    /// own turns a rating into a reply.
    let theirRating: Int?
    /// When somebody raised an alarm on this trip. Shown to **both** parties —
    /// a driver whose passenger has pressed it needs to know, and an app that
    /// hid it would be pretending nothing happened.
    let sosAt: Date?
    let expiresAt: Date?
    let requestedAt: Date?
    let confirmedAt: Date?
    let startedAt: Date?
    let completedAt: Date?
    let cancelReason: String?

    /// Still looking for somebody.
    var isSearching: Bool { state == "REQUESTED" || state == "NEGOTIATING" }
    var isMatched: Bool { state == "CONFIRMED" || state == "ARRIVING" }
    var isRunning: Bool { state == "IN_TRIP" }
    var isOver: Bool {
        state == "COMPLETED" || state == "EXPIRED"
            || state.hasPrefix("CANCELLED")
    }

    /// Live counteroffers, freshest first. A rider sees all of them; a driver
    /// sees only their own.
    var liveOffers: [RideOfferDTO] {
        (offers ?? []).filter { $0.state == "PENDING" && $0.expiresAt > Date() }
    }
}

struct MyRideDTO: Decodable {
    let ride: RideDTO?
}

/// One band of the token price list: trips up to `upToMetres` cost `tokens`.
struct RideTokenPriceDTO: Decodable, Equatable, Identifiable {
    let category: String
    let upToMetres: Int
    let tokens: Int

    var id: String { "\(category)-\(upToMetres)" }
}

/// The driver's token standing (Phase 3 M4).
///
/// `refusal` is the reason this endpoint exists. Dispatch stops offering trips
/// to a driver who can't pay for them — silently and correctly — so without a
/// sentence from the server the driver watches an empty screen and concludes
/// the app is broken.
struct MyRideTokensDTO: Decodable, Equatable {
    let balance: Int
    /// The least any trip could cost. Zero means the model is off in this market.
    let cheapest: Int
    let canWork: Bool
    let refusal: String?
    let prices: [RideTokenPriceDTO]
}

struct QuoteRideBody: Encodable {
    let pickupLatitude: Double
    let pickupLongitude: Double
    let dropoffLatitude: Double
    let dropoffLongitude: Double
}

struct RequestRideBody: Encodable {
    let category: String
    let pickupLatitude: Double
    let pickupLongitude: Double
    let pickupLabel: String
    let dropoffLatitude: Double
    let dropoffLongitude: Double
    let dropoffLabel: String
    let note: String?
    /// What the rider puts on the table, or nil to take the suggestion.
    let offeredFareMinor: Int?
}

struct OfferAmountBody: Encodable {
    let amountMinor: Int
}

struct CancelRideBody: Encodable {
    let reason: String?
}

struct RateRideBody: Encodable {
    let stars: Int
}

/// GojoTravel's API surface (Phase 3 M3) — both sides of it, because both sides
/// share one object.
///
/// Nothing here decides anything. What a trip costs, whether an offer is in
/// range, who may accept it and when the money moves are all the server's
/// answers; this file only asks.
@MainActor
final class TravelStore {

    static let shared = TravelStore()

    // MARK: The rider

    /// Every category priced at once, so the picker shows real numbers instead
    /// of making somebody tap through six screens to compare them.
    func quote(from: (lat: Double, lon: Double),
               to: (lat: Double, lon: Double)) async throws -> RideQuoteDTO {
        try await APIClient.shared.post("/v1/travel/quote",
            body: QuoteRideBody(pickupLatitude: from.lat, pickupLongitude: from.lon,
                                dropoffLatitude: to.lat, dropoffLongitude: to.lon))
    }

    func request(_ body: RequestRideBody) async throws -> RideDTO {
        try await APIClient.shared.post("/v1/travel/rides", body: body)
    }

    /// The one ride in progress, from whichever side. `nil` rather than a 404 —
    /// "am I in a car" is a question the app asks before it knows.
    func live() async throws -> RideDTO? {
        let response: MyRideDTO = try await APIClient.shared.get("/v1/travel/rides/live")
        return response.ride
    }

    func ride(_ id: UUID) async throws -> RideDTO {
        try await APIClient.shared.get("/v1/travel/rides/\(id)")
    }

    func history(limit: Int = 20) async throws -> [RideDTO] {
        try await APIClient.shared.get("/v1/travel/rides?limit=\(limit)")
    }

    /// Take a driver's price.
    func acceptOffer(_ rideID: UUID, _ offerID: UUID) async throws -> RideDTO {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/offers/\(offerID)/accept")
    }

    func declineOffer(_ rideID: UUID, _ offerID: UUID) async throws {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/offers/\(offerID)/decline")
    }

    /// One more round, addressed to that driver and nobody else.
    func counterBack(_ rideID: UUID, _ offerID: UUID,
                     amountMinor: Int) async throws -> RideOfferDTO {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/offers/\(offerID)/counter",
                                        body: OfferAmountBody(amountMinor: amountMinor))
    }

    // MARK: Either side

    func cancel(_ rideID: UUID, reason: String?) async throws -> RideDTO {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/cancel",
                                        body: CancelRideBody(reason: reason))
    }

    func rate(_ rideID: UUID, stars: Int) async throws -> RideDTO {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/rate",
                                        body: RateRideBody(stars: stars))
    }

    // MARK: The driver

    /// Tokens: what the caller holds, what a trip costs, and — when they can't
    /// work — why. On `travel` rather than `payments` because only the module
    /// that prices a ride can say whether a balance is enough to take one.
    func tokens() async throws -> MyRideTokensDTO {
        try await APIClient.shared.get("/v1/travel/tokens")
    }

    /// "Not at that price." Posting one is also a decline of the dispatch offer.
    func counter(_ rideID: UUID, amountMinor: Int) async throws -> RideOfferDTO {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/offers",
                                        body: OfferAmountBody(amountMinor: amountMinor))
    }

    func takeOffer(_ rideID: UUID, _ offerID: UUID) async throws -> RideDTO {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/offers/\(offerID)/take")
    }

    func arriving(_ rideID: UUID) async throws -> RideDTO {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/arriving")
    }

    func start(_ rideID: UUID) async throws -> RideDTO {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/start")
    }

    func complete(_ rideID: UUID) async throws -> RideDTO {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/complete")
    }

    // MARK: Safety (Phase 3 M5)

    /// A public link to this trip, for somebody who isn't in the app. Either
    /// party may make one — a driver working nights has as much reason to be
    /// watched as a rider does.
    func share(_ rideID: UUID) async throws -> ShareTripDTO {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/share")
    }

    func stopSharing(_ rideID: UUID) async throws {
        try await APIClient.shared.delete("/v1/travel/rides/\(rideID)/share")
    }

    /// The button. Flags the trip, mints a tracking link and pushes to every
    /// emergency contact who is also on GojoGo. **The server never dials** —
    /// it hands back the number and the phone does it.
    func sos(_ rideID: UUID) async throws -> SosDTO {
        try await APIClient.shared.post("/v1/travel/rides/\(rideID)/sos")
    }
}

// MARK: - Safety payloads (Phase 3 M5)

/// A public link to a live trip.
struct ShareTripDTO: Decodable, Equatable {
    let url: String
    let expiresAt: Date?
    /// Whether anybody actually opened it — the one question a person who
    /// shared a trip asks.
    let viewCount: Int
    /// The whole message, already written by the server. Composed there rather
    /// than here because the wording of a safety message is not a place for
    /// every client to have its own idea.
    let message: String
}

/// What comes back from pressing SOS.
///
/// The app dials `emergencyNumber` and opens the message composer for the
/// contacts the server could not push to. It does **not** place a call on
/// anybody's behalf without their tap, and neither does the server.
struct SosDTO: Decodable, Equatable {
    let emergencyNumber: String
    let shareUrl: String
    let message: String
    let contacts: [EmergencyContactDTO]
    /// How many were reached by push — the contacts who are also GojoGo
    /// accounts, and usually fewer than the list.
    let notifiedCount: Int
    let raisedAt: Date?

    /// The ones nobody could push to, which is who the message composer is for.
    var unreachable: [EmergencyContactDTO] { contacts.filter { $0.linkedProfileId == nil } }
}
