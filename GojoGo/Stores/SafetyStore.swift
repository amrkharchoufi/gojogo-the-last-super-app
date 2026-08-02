import Foundation

// MARK: - Trust & safety API surface (Phase 2e M5)
//
// Reporting, blocking and account deletion, which sit across three backend
// modules (`moderation`, `social`, `profile`) but are one thing to a person:
// the controls that let them get away from someone, or get out entirely.
//
// One store rather than three additions to existing ones, because the screens
// that use them are shared: the same report sheet is opened from a post, a
// comment, a video, a listing and a profile.

/// What can be reported. Must stay in step with the backend's
/// `ModerationTargetKind` — an unknown kind is a 400 naming it, deliberately,
/// so a mismatch is loud rather than a report that vanishes.
enum ReportTargetKind: String, Codable {
    case post = "POST"
    case comment = "COMMENT"
    case story = "STORY"
    case video = "VIDEO"
    case profile = "PROFILE"
    case listing = "LISTING"
}

/// A reason from the server's closed list, with the wording a person reads.
/// The raw values come from `GET /v1/reports/reasons`; the labels are here
/// because a picker showing `INTELLECTUAL_PROPERTY` is not a picker.
struct ReportReason: Identifiable, Hashable {
    let raw: String
    var id: String { raw }

    var label: String {
        switch raw {
        case "SPAM": return "Spam"
        case "ADULT_CONTENT": return "Nudity or sexual content"
        case "HATE_SPEECH": return "Hate speech"
        case "VIOLENCE": return "Violence"
        case "HARASSMENT": return "Harassment or bullying"
        case "IMPERSONATION": return "Pretending to be someone else"
        case "SCAM": return "Scam or fraud"
        case "ILLEGAL": return "Something illegal"
        case "SELF_HARM": return "Suicide or self-harm"
        case "INTELLECTUAL_PROPERTY": return "Copyright or trademark"
        case "OTHER": return "Something else"
        default:
            // A reason the server grew and this build doesn't know: show it
            // rather than dropping it, because a picker missing an option is
            // worse than one with an ugly label.
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The order a person scans. Deliberately not alphabetical: the reasons
    /// that need a human fastest are near the top, and "something else" is last
    /// because an escape hatch offered first is the one everybody picks.
    static let displayOrder = [
        "SELF_HARM", "HARASSMENT", "HATE_SPEECH", "VIOLENCE", "ADULT_CONTENT",
        "SCAM", "SPAM", "IMPERSONATION", "INTELLECTUAL_PROPERTY", "ILLEGAL", "OTHER"
    ]

    static func sorted(_ raws: [String]) -> [ReportReason] {
        raws.map(ReportReason.init(raw:)).sorted {
            let a = displayOrder.firstIndex(of: $0.raw) ?? displayOrder.count
            let b = displayOrder.firstIndex(of: $1.raw) ?? displayOrder.count
            return a == b ? $0.raw < $1.raw : a < b
        }
    }

    /// What the picker shows before the server has answered — the same list the
    /// backend ships, so the sheet is never empty on a cold open.
    static let fallback = sorted(displayOrder)
}

struct ReportReceiptDTO: Decodable {
    var id: UUID
    var status: String
    /// They had already reported this. The sheet says "you've already reported
    /// this" rather than pretending a second one was filed.
    var alreadyReported: Bool
}

struct BlockedProfileDTO: Decodable, Identifiable {
    var id: UUID
    var name: String
    var handle: String?
    var avatarUrl: String?
    var blockedAt: String?
}

struct DeletionStatusDTO: Decodable {
    var pending: Bool
    var requestedAt: String?
    /// When the scrub becomes due — the date the confirmation screen shows.
    var graceEndsAt: String?
    var anonymizedAt: String?
}

@MainActor
final class SafetyStore {

    static let shared = SafetyStore()

    private struct CreateReportBody: Encodable {
        var targetKind: String
        var targetId: String
        var reason: String
        var note: String?
    }

    func reasons() async throws -> [ReportReason] {
        let raws: [String] = try await APIClient.shared.get("/v1/reports/reasons")
        return ReportReason.sorted(raws)
    }

    func report(kind: ReportTargetKind, id: UUID, reason: String,
                note: String?) async throws -> ReportReceiptDTO {
        try await APIClient.shared.post("/v1/reports", body: CreateReportBody(
            targetKind: kind.rawValue,
            targetId: id.uuidString.lowercased(),
            reason: reason,
            note: note?.isEmpty == true ? nil : note))
    }

    // MARK: Blocking

    func blocked() async throws -> [BlockedProfileDTO] {
        try await APIClient.shared.get("/v1/me/blocks")
    }

    func block(_ profileId: UUID) async throws {
        try await APIClient.shared.post("/v1/profiles/\(profileId.uuidString.lowercased())/block")
    }

    func unblock(_ profileId: UUID) async throws {
        try await APIClient.shared.delete("/v1/profiles/\(profileId.uuidString.lowercased())/block")
    }

    // MARK: Leaving

    /// Starts the deletion. The server disables sign-in the same instant, so
    /// this is the last authenticated call this account will make.
    func deleteAccount() async throws -> DeletionStatusDTO {
        try await APIClient.shared.deleteReturning("/v1/me")
    }

    // MARK: Emergency contacts (Phase 3 M5)

    func emergencyContacts() async throws -> EmergencyContactsDTO {
        try await APIClient.shared.get("/v1/me/emergency-contacts")
    }

    func addEmergencyContact(name: String, phone: String,
                             relationship: String) async throws -> EmergencyContactDTO {
        try await APIClient.shared.post("/v1/me/emergency-contacts",
            body: SaveEmergencyContactBody(name: name, phone: phone,
                                           relationship: relationship, linkedProfileId: nil))
    }

    func removeEmergencyContact(_ id: UUID) async throws {
        try await APIClient.shared.delete(
            "/v1/me/emergency-contacts/\(id.uuidString.lowercased())")
    }

    // MARK: Community vehicle verification (Phase 3 M5)

    /// Open invitations only. An answered or lapsed one is not a card.
    func verificationInvites() async throws -> [VerificationInviteDTO] {
        try await APIClient.shared.get("/v1/partner/verifications")
    }

    func answerVerification(_ id: UUID, driverMatched: Bool, photosMatched: Bool,
                            plateMatched: Bool, roadworthy: Bool, noFraud: Bool,
                            comment: String?) async throws -> VerificationInviteDTO {
        try await APIClient.shared.post(
            "/v1/partner/verifications/\(id.uuidString.lowercased())",
            body: AnswerVerificationBody(
                driverMatched: driverMatched, photosMatched: photosMatched,
                plateMatched: plateMatched, roadworthy: roadworthy, noFraud: noFraud,
                comment: (comment?.isEmpty ?? true) ? nil : comment))
    }
}

// MARK: - Safety pack payloads (Phase 3 M5)

/// Somebody to tell when a person is in trouble.
///
/// The phone number is the required half and the GojoGo account is the bonus,
/// which is the opposite of what an app-first design would do — the person you
/// would call in an emergency is usually not a user of the app you happen to be
/// sitting in.
struct EmergencyContactDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let phone: String
    let relationship: String?
    /// Set when this contact is also on GojoGo, which is what turns an alarm
    /// into a push rather than a message somebody has to send by hand.
    let linkedProfileId: UUID?
}

struct EmergencyContactsDTO: Decodable {
    let contacts: [EmergencyContactDTO]
    /// How many are allowed, so the screen says "3 of 5" instead of finding out
    /// by being refused.
    let max: Int
}

struct SaveEmergencyContactBody: Encodable {
    let name: String
    let phone: String
    let relationship: String
    let linkedProfileId: UUID?
}

/// A passenger being asked whether the car they just rode in was the car.
///
/// Deliberately thin about the driver — a first name and no id — because the
/// question is "was the person driving the person in the app", and a card
/// showing their profile has answered it for them.
struct VerificationInviteDTO: Decodable, Equatable, Identifiable {
    let id: UUID
    let status: String
    let vehicleId: UUID
    let vehicleLabel: String
    let vehiclePlate: String
    let vehicleYear: Int?
    let driverFirstName: String
    let rewardMinor: Int
    let currency: String
    let expiresAt: Date?
    let createdAt: Date?
}

struct AnswerVerificationBody: Encodable {
    let driverMatched: Bool
    let photosMatched: Bool
    let plateMatched: Bool
    let roadworthy: Bool
    let noFraud: Bool
    let comment: String?
}
