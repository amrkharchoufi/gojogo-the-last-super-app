import Foundation

/// The `services` vertical (Phase 5 M3): the customer's browse/slots/booking
/// surface and the provider's console, which are the two ends of the same seven
/// booking words.
///
/// One asymmetry worth knowing before reading the calls: the customer's verbs
/// are three (`book`, `acceptQuote`, `cancel`) and the provider's are six,
/// because everything that decides what a job is worth happens on their side.
@MainActor
final class ServicesStore {

    static let shared = ServicesStore()

    // MARK: Customer — browse

    func browse(category: String? = nil, providerId: UUID? = nil,
                before: String? = nil, limit: Int = 24) async throws -> ServicePageDTO {
        var path = "/v1/services?limit=\(limit)"
        if let category, category != "All", let enc = Self.query(category) {
            path += "&category=\(enc)"
        }
        if let providerId { path += "&providerId=\(providerId.uuidString)" }
        if let before, let enc = Self.query(before) { path += "&before=\(enc)" }
        return try await APIClient.shared.get(path)
    }

    func service(_ serviceId: UUID) async throws -> ServiceDTO {
        try await APIClient.shared.get("/v1/services/\(serviceId)")
    }

    func provider(_ providerId: UUID) async throws -> ProviderDTO {
        try await APIClient.shared.get("/v1/services/providers/\(providerId)")
    }

    /// The bookable start times over the next `days`. Asked fresh every time
    /// the picker opens: a slot list is stale the moment somebody else books.
    func slots(_ serviceId: UUID, from: Date? = nil, days: Int = 14) async throws -> SlotsDTO {
        var path = "/v1/services/\(serviceId)/slots?days=\(days)"
        if let from { path += "&from=\(Self.day(from))" }
        return try await APIClient.shared.get(path)
    }

    func reviews(_ serviceId: UUID, limit: Int = 50) async throws -> [ServiceReviewDTO] {
        try await APIClient.shared.get("/v1/services/\(serviceId)/reviews?limit=\(limit)")
    }

    func review(_ serviceId: UUID, _ body: ServiceReviewBody) async throws -> ServiceReviewDTO {
        try await APIClient.shared.post("/v1/services/\(serviceId)/reviews", body: body)
    }

    // MARK: Customer — bookings

    func book(_ body: BookingRequestBody) async throws -> BookingDTO {
        try await APIClient.shared.post("/v1/services/bookings", body: body)
    }

    func myBookings(limit: Int = 50) async throws -> [BookingDTO] {
        try await APIClient.shared.get("/v1/services/bookings?limit=\(limit)")
    }

    func booking(_ bookingId: UUID) async throws -> BookingDTO {
        try await APIClient.shared.get("/v1/services/bookings/\(bookingId)")
    }

    /// Pays and confirms in one act — the provider already said yes by naming
    /// the number, so there is no second confirmation to wait for.
    func acceptQuote(_ bookingId: UUID) async throws -> BookingDTO {
        try await APIClient.shared.post("/v1/services/bookings/\(bookingId)/accept-quote")
    }

    /// May cost the fee the booking is carrying in `cancellationFeeCents` —
    /// which is why the UI shows that number before asking.
    func cancelBooking(_ bookingId: UUID) async throws -> BookingDTO {
        try await APIClient.shared.post("/v1/services/bookings/\(bookingId)/cancel")
    }

    // MARK: Provider console

    func myProvider() async throws -> ProviderDTO {
        try await APIClient.shared.get("/v1/services/providers/mine")
    }

    func updateProvider(_ body: ProviderBody) async throws -> ProviderDTO {
        try await APIClient.shared.put("/v1/services/providers/mine", body: body)
    }

    func providerWallet(limit: Int = 50) async throws -> PayeeWalletDTO {
        try await APIClient.shared.get("/v1/services/providers/mine/wallet?limit=\(limit)")
    }

    func myServices(limit: Int = 100) async throws -> [ServiceDTO] {
        try await APIClient.shared.get("/v1/services/providers/mine/services?limit=\(limit)")
    }

    func createService(_ body: ServiceBody) async throws -> ServiceDTO {
        try await APIClient.shared.post("/v1/services/providers/mine/services", body: body)
    }

    func updateService(_ serviceId: UUID, _ body: ServiceBody) async throws -> ServiceDTO {
        try await APIClient.shared.put("/v1/services/providers/mine/services/\(serviceId)",
                                       body: body)
    }

    func setServiceActive(_ serviceId: UUID, _ active: Bool) async throws -> ServiceDTO {
        try await APIClient.shared.put(
            "/v1/services/providers/mine/services/\(serviceId)/active?active=\(active)",
            body: NoBody())
    }

    // MARK: Provider — the calendar

    func availability() async throws -> [AvailabilityRuleDTO] {
        try await APIClient.shared.get("/v1/services/providers/mine/availability")
    }

    /// Replaces the whole week, never patches a day — the same discipline as
    /// the listing editor: what is sent is what the week becomes, so a rule
    /// that vanished from the form is a rule that is gone.
    func replaceAvailability(_ rules: [AvailabilityRuleBody]) async throws -> [AvailabilityRuleDTO] {
        try await APIClient.shared.put("/v1/services/providers/mine/availability",
                                       body: ReplaceAvailabilityBody(rules: rules))
    }

    /// Days off. Decoded as plain `yyyy-MM-dd` strings on both sides.
    func exceptions() async throws -> [String] {
        try await APIClient.shared.get("/v1/services/providers/mine/availability/exceptions")
    }

    func addException(_ day: Date) async throws {
        try await APIClient.shared.postNoContent(
            "/v1/services/providers/mine/availability/exceptions",
            body: AvailabilityExceptionBody(onDate: Self.day(day)))
    }

    func removeException(_ day: Date) async throws {
        try await APIClient.shared.delete(
            "/v1/services/providers/mine/availability/exceptions?onDate=\(Self.day(day))")
    }

    // MARK: Provider — the booking queue

    func providerBookings(status: BookingStatus? = nil, limit: Int = 50) async throws -> [BookingDTO] {
        var path = "/v1/services/providers/mine/bookings?limit=\(limit)"
        if let status { path += "&status=\(status.rawValue)" }
        return try await APIClient.shared.get(path)
    }

    /// Naming a number on a quote-only job. It does not confirm anything — the
    /// customer's acceptance does that, and pays at the same moment.
    func quote(_ bookingId: UUID, priceCents: Int64) async throws -> BookingDTO {
        try await APIClient.shared.post("/v1/services/providers/mine/bookings/\(bookingId)/quote",
                                        body: BookingQuoteBody(priceCents: priceCents))
    }

    func confirm(_ bookingId: UUID) async throws -> BookingDTO {
        try await APIClient.shared.post("/v1/services/providers/mine/bookings/\(bookingId)/confirm")
    }

    func decline(_ bookingId: UUID) async throws -> BookingDTO {
        try await APIClient.shared.post("/v1/services/providers/mine/bookings/\(bookingId)/decline")
    }

    /// Always free to the customer, whenever it happens.
    func cancelAsProvider(_ bookingId: UUID) async throws -> BookingDTO {
        try await APIClient.shared.post("/v1/services/providers/mine/bookings/\(bookingId)/cancel")
    }

    /// Starts the settlement window rather than paying immediately.
    func complete(_ bookingId: UUID) async throws -> BookingDTO {
        try await APIClient.shared.post("/v1/services/providers/mine/bookings/\(bookingId)/complete")
    }

    /// Settles at 100% straight away — there is no work to argue about, only an
    /// empty chair that was paid for.
    func noShow(_ bookingId: UUID) async throws -> BookingDTO {
        try await APIClient.shared.post("/v1/services/providers/mine/bookings/\(bookingId)/no-show")
    }

    func replyToReview(_ reviewId: UUID, body: String) async throws -> ServiceReviewDTO {
        try await APIClient.shared.post("/v1/services/providers/mine/reviews/\(reviewId)/reply",
                                        body: ServiceReplyBody(body: body))
    }

    // MARK: Provider — qualification papers

    /// Private documents: presigned PUT straight to S3, and the app keeps only
    /// the object key. Same shape as a vehicle registration in `partner`.
    func uploadDocument(_ data: Data, label: String,
                        contentType: String) async throws -> ProviderDocumentDTO {
        guard let enc = Self.query(contentType) else {
            throw APIClient.APIError.http(status: -1, message: "Bad content type")
        }
        let upload: ShopUploadDTO = try await APIClient.shared
            .post("/v1/services/providers/mine/documents/presign?contentType=\(enc)")
        try await APIClient.shared.upload(to: upload.uploadUrl, data: data, contentType: contentType)
        return try await APIClient.shared.post(
            "/v1/services/providers/mine/documents",
            body: ProviderDocumentBody(objectKey: upload.objectKey, label: label))
    }

    func documents() async throws -> [ProviderDocumentDTO] {
        try await APIClient.shared.get("/v1/services/providers/mine/documents")
    }

    // MARK: Helpers

    /// `yyyy-MM-dd` in the *device's* zone. A day off is the day the provider
    /// means by it, and they are setting it on their own phone.
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func query(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }
}
