import Foundation

/// Profile-module API surface (matches backend `profile` module).
@MainActor
final class ProfileStore {

    static let shared = ProfileStore()

    private(set) var me: ProfileDTO?

    func establishSession() async throws -> SessionDTO {
        let session: SessionDTO = try await postEmpty("/v1/auth/session")
        return session
    }

    func fetchMe() async throws -> ProfileDTO {
        let profile: ProfileDTO = try await APIClient.shared.get("/v1/profiles/me")
        me = profile
        return profile
    }

    func updateMe(_ body: UpdateProfileBody) async throws -> ProfileDTO {
        let profile: ProfileDTO = try await APIClient.shared.patch("/v1/profiles/me", body: body)
        me = profile
        return profile
    }

    func view(_ id: UUID) async throws -> ProfileViewDTO {
        try await APIClient.shared.get("/v1/profiles/\(id.uuidString.lowercased())")
    }

    func posts(of id: UUID) async throws -> [PostDTO] {
        try await APIClient.shared.get("/v1/profiles/\(id.uuidString.lowercased())/posts")
    }

    func reset() {
        me = nil
    }

    private struct EmptyBody: Encodable {}

    private func postEmpty<T: Decodable>(_ path: String) async throws -> T {
        try await APIClient.shared.post(path, body: EmptyBody())
    }
}
