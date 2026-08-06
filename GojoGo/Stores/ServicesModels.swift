import Foundation

// MARK: - Services vertical DTOs (Phase 5 · Milestone 3)
//
// Booking somebody's time, which is not shopping: there is no stock, the thing
// being sold is an hour on a calendar, and half the prices in it are not known
// until the provider has looked at the job.
//
// Two shapes carry most of the vertical's rules. A `ServiceDTO` with a nil
// `priceCents` is quote-only — the customer asks, the provider names a number,
// and accepting that quote *pays and confirms in one act*, because the provider
// already said yes by naming it. And a `BookingDTO` carries all seven of SPECS
// §7's words rather than collapsing them: "the customer cancelled" and "the
// provider cancelled" cost different money and must never render the same.

// MARK: Provider

struct ProviderDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let logoUrl: String?
    let bio: String?
    let qualifications: String?
    let serviceAreas: String?
    let languages: String?
    /// An IANA zone, on the provider from day one — the delivery vertical spent
    /// a milestone discovering that opening hours without one are a guess.
    let timezone: String?
    let portfolioUrls: [String]?
    let suspended: Bool
    let createdAt: String
}

struct ProviderBody: Encodable {
    let displayName: String
    let logoUrl: String?
    let bio: String
    let qualifications: String
    let serviceAreas: String
    let languages: String
    let timezone: String
    let portfolioUrls: [String]
}

struct ProviderDocumentDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let label: String
    let readUrl: String?
    let uploadedAt: String
}

struct ProviderDocumentBody: Encodable {
    let objectKey: String
    let label: String
}

// MARK: Catalog

/// Where the work happens. Drives one line of copy and nothing else today, but
/// it is the difference between "come to me" and "I'll come to you", which is
/// the first thing a customer wants to know.
enum ServiceLocationKind: String, CaseIterable, Identifiable {
    case atProvider = "AT_PROVIDER"
    case atCustomer = "AT_CUSTOMER"
    case remote = "REMOTE"

    var id: String { rawValue }

    init(wire: String?) {
        self = wire.flatMap { ServiceLocationKind(rawValue: $0.uppercased()) } ?? .atProvider
    }

    var label: String {
        switch self {
        case .atProvider: return "At their place"
        case .atCustomer: return "They come to you"
        case .remote: return "Remote"
        }
    }

    var formLabel: String {
        switch self {
        case .atProvider: return "At my place"
        case .atCustomer: return "I travel to them"
        case .remote: return "Remote"
        }
    }

    var icon: String {
        switch self {
        case .atProvider: return "building.2"
        case .atCustomer: return "house"
        case .remote: return "video"
        }
    }
}

struct ServiceDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let providerId: UUID
    let providerName: String
    let providerLogoUrl: String?
    let name: String
    let description: String?
    let category: String?
    let durationMinutes: Int
    let priceCents: Int64?
    /// True when the price is nil by design rather than by omission.
    let priceOnQuote: Bool
    let currency: String?
    let locationKind: String?
    let requirements: String?
    let active: Bool
    let averageRating: Double?
    let ratingCount: Int
    let createdAt: String

    var location: ServiceLocationKind { ServiceLocationKind(wire: locationKind) }

    var priceLabel: String {
        priceOnQuote || priceCents == nil
            ? "Price on quote"
            : EconomyStore.formatPrice(cents: priceCents, currency: currency ?? "USD")
    }

    var durationLabel: String { Self.duration(durationMinutes) }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
}

struct ServicePageDTO: Decodable {
    let items: [ServiceDTO]
    let nextBefore: String?
}

struct ServiceBody: Encodable {
    let name: String
    let description: String
    let category: String
    let durationMinutes: Int
    /// Nil means quote-only, and that is a decision rather than a blank: the
    /// provider is saying "I need to see the job first".
    let priceCents: Int64?
    let locationKind: String
    let requirements: String
}

// MARK: Availability

/// One open window on the weekly template. `dayOfWeek` is 1–7 Monday-first,
/// matching `java.time.DayOfWeek` — the enum the backend actually stores.
struct AvailabilityRuleDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let dayOfWeek: Int
    let startMinute: Int
    let endMinute: Int
}

struct AvailabilityRuleBody: Encodable, Equatable {
    let dayOfWeek: Int
    let startMinute: Int
    let endMinute: Int
}

struct ReplaceAvailabilityBody: Encodable {
    let rules: [AvailabilityRuleBody]
}

struct AvailabilityExceptionBody: Encodable {
    /// A plain `yyyy-MM-dd` — a day off is a date, not an instant.
    let onDate: String
}

/// The offerable start times: the weekly template, minus exception days, minus
/// live bookings, minus the buffer between jobs. Computed server-side, because
/// a client that computed it would be racing every other customer's booking.
struct SlotsDTO: Decodable {
    let serviceId: UUID
    let durationMinutes: Int
    let timezone: String?
    let slots: [String]
}

// MARK: Bookings

/// All seven of SPECS §7's words. They are not collapsed into "cancelled"
/// because the two cancellations settle differently: a customer's may carry a
/// fee, a provider's is always free to the customer.
enum BookingStatus: String, CaseIterable, Identifiable {
    case requested = "REQUESTED"
    case confirmed = "CONFIRMED"
    case completed = "COMPLETED"
    case declined = "DECLINED"
    case cancelledCustomer = "CANCELLED_CUSTOMER"
    case cancelledProvider = "CANCELLED_PROVIDER"
    case noShow = "NO_SHOW"

    var id: String { rawValue }

    init(wire: String?) {
        self = wire.flatMap { BookingStatus(rawValue: $0.uppercased()) } ?? .requested
    }

    /// What the *customer* is told.
    var label: String {
        switch self {
        case .requested: return "Waiting on them"
        case .confirmed: return "Confirmed"
        case .completed: return "Done"
        case .declined: return "Declined"
        case .cancelledCustomer: return "You cancelled"
        case .cancelledProvider: return "They cancelled"
        case .noShow: return "Marked no-show"
        }
    }

    /// What the *provider* is told about the same row. "Waiting on them" and
    /// "Needs your answer" are the same status seen from the two ends of it.
    var providerLabel: String {
        switch self {
        case .requested: return "Needs your answer"
        case .confirmed: return "Confirmed"
        case .completed: return "Done"
        case .declined: return "You declined"
        case .cancelledCustomer: return "Customer cancelled"
        case .cancelledProvider: return "You cancelled"
        case .noShow: return "No-show"
        }
    }

    var icon: String {
        switch self {
        case .requested: return "clock"
        case .confirmed: return "checkmark.circle.fill"
        case .completed: return "checkmark.seal.fill"
        case .declined: return "hand.raised"
        case .cancelledCustomer, .cancelledProvider: return "xmark.circle"
        case .noShow: return "person.fill.xmark"
        }
    }

    var isOpen: Bool { self == .requested || self == .confirmed }
}

struct BookingDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let serviceId: UUID
    let serviceName: String
    let providerId: UUID
    let providerName: String
    let customerId: UUID
    let status: String
    let startsAt: String
    let durationMinutes: Int
    let priceCents: Int64?
    let currency: String?
    /// HELD / SETTLED / RELEASED / NONE — the money's own state, which is not
    /// the booking's: a completed job is still holding money for 48 hours.
    let paymentStatus: String?
    let note: String?
    /// Every booking opens a thread with a booking context card.
    let conversationId: UUID?
    /// What cancelling *right now* would cost the customer. Tiered on how close
    /// the start is, so it is a live number and not a policy sentence.
    let cancellationFeeCents: Int64
    let requestedAt: String
    let quotedAt: String?
    let confirmedAt: String?
    let completedAt: String?
    let cancelledAt: String?

    var state: BookingStatus { BookingStatus(wire: status) }

    var priceLabel: String {
        priceCents == nil
            ? "Awaiting quote"
            : EconomyStore.formatPrice(cents: priceCents, currency: currency ?? "USD")
    }

    var cancellationFeeLabel: String {
        EconomyStore.formatPrice(cents: cancellationFeeCents, currency: currency ?? "USD")
    }

    /// A quote the customer has not answered: priced by the provider, still
    /// REQUESTED, and one tap away from being paid for and confirmed.
    var awaitingQuoteAcceptance: Bool {
        state == .requested && quotedAt != nil && priceCents != nil
    }

    var startDate: Date? { BackendDate.parse(startsAt) }
}

struct BookingRequestBody: Encodable {
    let serviceId: UUID
    let startsAt: String
    let note: String
}

struct BookingQuoteBody: Encodable {
    let priceCents: Int64
}

// MARK: Reviews

struct ServiceReviewDTO: Decodable, Identifiable, Equatable {
    let id: UUID
    let serviceId: UUID
    let authorId: UUID
    let authorName: String?
    let authorAvatarUrl: String?
    let rating: Int
    let body: String?
    let replyBody: String?
    let repliedAt: String?
    let createdAt: String
}

struct ServiceReviewBody: Encodable {
    /// Verified booking: the review names the completed booking behind it.
    let bookingId: UUID
    let rating: Int
    let body: String
}

struct ServiceReplyBody: Encodable {
    let body: String
}
