import Foundation

// MARK: - Wire types (kyc module)

/// Where the caller's identity check stands, as the server sees it.
///
/// The app never receives documents, extracted personal data, or any Sumsub
/// identifier — the whole point of an IDV vendor is that neither this app nor
/// our backend ends up holding a copy of everyone's passport. What comes back is
/// a verdict and, when it's bad news, something to show the person.
struct IdentityVerificationDTO: Decodable, Equatable {
    let status: String
    /// Why it was refused, in the vendor's client-facing words. Nil on a pass.
    let reason: String?
    let rejectLabels: [String]
    let levelName: String
    /// False when no vendor is configured on this environment — the app must not
    /// offer a button that can only fail.
    let available: Bool
    let canStart: Bool
    let verifiedAt: Date?
    let updatedAt: Date?
}

/// The short-lived token the SDK launches with, plus the state it launches into.
struct KycAccessTokenDTO: Decodable {
    let token: String
    let levelName: String
    let verification: IdentityVerificationDTO
}

// MARK: - UI model

/// Mirrors the server's enum. Anything unrecognised reads as `.notStarted`, so a
/// newer backend can add a state without bricking an older build — the same
/// forward-compat convention as `ListingStatus` and `MerchantApplicationStatus`.
enum IdentityStatus: String, Equatable {
    case notStarted = "NOT_STARTED"
    case pending = "PENDING"
    case inReview = "IN_REVIEW"
    case verified = "VERIFIED"
    case resubmissionRequested = "RESUBMISSION_REQUESTED"
    case rejected = "REJECTED"

    init(wire: String) { self = IdentityStatus(rawValue: wire) ?? .notStarted }

    var label: String {
        switch self {
        case .notStarted:             return "Not started"
        case .pending:                return "Continue"
        case .inReview:               return "Checking"
        case .verified:               return "Verified"
        case .resubmissionRequested:  return "Try again"
        case .rejected:               return "Didn't pass"
        }
    }

    /// What the person is told is happening. Deliberately plain: a verification
    /// screen is stressful enough without jargon.
    var detail: String {
        switch self {
        case .notStarted:
            return "Scan your ID and take a quick selfie. It usually takes a minute."
        case .pending:
            return "You started this but didn't finish. Pick up where you left off."
        case .inReview:
            return "We're checking your documents. You'll get a notification the moment it's done."
        case .verified:
            return "Your identity is confirmed."
        case .resubmissionRequested:
            return "Something wasn't clear enough. You can go again."
        case .rejected:
            return "We couldn't verify this. Contact support if you think that's wrong."
        }
    }

    var icon: String {
        switch self {
        case .verified:                        return "checkmark.seal.fill"
        case .inReview:                        return "clock.fill"
        case .rejected:                        return "xmark.seal.fill"
        case .resubmissionRequested:           return "arrow.clockwise"
        case .notStarted, .pending:            return "person.text.rectangle.fill"
        }
    }

    /// Whether launching the SDK is worth offering.
    var isStartable: Bool {
        self == .notStarted || self == .pending || self == .resubmissionRequested
    }

    var isPending: Bool { self == .pending || self == .inReview }
}

/// The identity check as the app renders it.
struct IdentityVerification: Equatable {
    var status: IdentityStatus
    var reason: String?
    var rejectLabels: [String]
    /// False when the backend has no IDV vendor configured. The whole card
    /// hides rather than offering a flow that would 503.
    var isAvailable: Bool
    var canStart: Bool
    var verifiedAt: Date?

    static let unavailable = IdentityVerification(
        status: .notStarted, reason: nil, rejectLabels: [],
        isAvailable: false, canStart: false, verifiedAt: nil)

    var isVerified: Bool { status == .verified }

    /// What to put on the button, or nil when there's nothing to press.
    var actionTitle: String? {
        guard isAvailable, canStart else { return nil }
        switch status {
        case .notStarted:            return "Verify my identity"
        case .pending:               return "Finish verifying"
        case .resubmissionRequested: return "Try again"
        default:                     return nil
        }
    }

    /// The refusal in the vendor's own words when we have them, and a plain
    /// sentence when we don't — never a raw reject label, which reads as
    /// `UNSATISFACTORY_PHOTOS` and helps nobody.
    var message: String {
        if let reason, !reason.trimmed.isEmpty { return reason }
        return status.detail
    }
}
