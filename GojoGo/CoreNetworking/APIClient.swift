import Foundation

/// Async/await client for the GojoGo backend: attaches the Cognito ID token,
/// refreshes it once on 401, decodes JSON responses.
final class APIClient {

    static let shared = APIClient()

    enum APIError: LocalizedError {
        case http(status: Int, message: String?)
        case notAuthenticated

        var errorDescription: String? {
            switch self {
            case .http(let status, let message):
                return message ?? "Request failed (\(status))"
            case .notAuthenticated:
                return "Not signed in."
            }
        }
    }

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request("GET", path, body: nil as Data?)
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await request("POST", path, body: try encoder.encode(body))
    }

    func post(_ path: String) async throws {
        _ = try await raw("POST", path, body: nil)
    }

    func patch<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await request("PATCH", path, body: try encoder.encode(body))
    }

    func delete(_ path: String) async throws {
        _ = try await raw("DELETE", path, body: nil)
    }

    private func request<T: Decodable>(_ method: String, _ path: String, body: Data?) async throws -> T {
        let data = try await raw(method, path, body: body)
        return try decoder.decode(T.self, from: data)
    }

    private func raw(_ method: String, _ path: String, body: Data?) async throws -> Data {
        func attempt(forceRefresh: Bool) async throws -> (Data, HTTPURLResponse) {
            let token = try await AuthSession.shared.validIdToken(forceRefresh: forceRefresh)
            // Not appendingPathComponent — that would percent-encode "?" in query strings.
            guard let url = URL(string: path, relativeTo: BackendConfig.apiBaseURL) else {
                throw APIError.http(status: -1, message: "Bad path \(path)")
            }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.http(status: -1, message: nil)
            }
            return (data, http)
        }

        var (data, http) = try await attempt(forceRefresh: false)
        if http.statusCode == 401 {
            (data, http) = try await attempt(forceRefresh: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["message"] as? String }
            throw APIError.http(status: http.statusCode, message: message)
        }
        return data
    }

    /// Presign + direct S3 PUT. Returns the public URL to reference in posts/stories.
    func uploadMedia(_ data: Data, contentType: String) async throws -> String {
        let presign: PresignDTO = try await post("/v1/media/presign", body: PresignBody(contentType: contentType))
        guard let url = URL(string: presign.uploadUrl) else {
            throw APIError.http(status: -1, message: "Bad upload URL")
        }
        var put = URLRequest(url: url)
        put.httpMethod = "PUT"
        put.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: put, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                                message: "Media upload failed")
        }
        return presign.publicUrl
    }

    /// Sniff image bytes → S3 content type (backend whitelists these).
    static func imageContentType(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if data.count > 11, data[4...11].elementsEqual([0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]) {
            return "image/heic"
        }
        return "image/jpeg"
    }
}

// MARK: - Token lifecycle

/// Owns the Cognito token set in the keychain and keeps the ID token fresh.
actor AuthSession {

    static let shared = AuthSession()

    private let cognito = CognitoAuthClient()
    private var refreshTask: Task<String, Error>?

    nonisolated var isAuthenticated: Bool {
        KeychainStore.get(.refreshToken) != nil
    }

    nonisolated var accountEmail: String? {
        KeychainStore.get(.accountEmail)
    }

    func store(_ tokens: CognitoAuthClient.Tokens, email: String) {
        KeychainStore.set(tokens.idToken, for: .idToken)
        KeychainStore.set(tokens.accessToken, for: .accessToken)
        if let refresh = tokens.refreshToken {
            KeychainStore.set(refresh, for: .refreshToken)
        }
        let expiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn - 120))
        KeychainStore.set(String(expiry.timeIntervalSince1970), for: .tokenExpiry)
        KeychainStore.set(email, for: .accountEmail)
    }

    func validIdToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh,
           let token = KeychainStore.get(.idToken),
           let expiryRaw = KeychainStore.get(.tokenExpiry),
           let expiry = Double(expiryRaw),
           Date().timeIntervalSince1970 < expiry {
            return token
        }
        if let running = refreshTask {
            return try await running.value
        }
        guard let refreshToken = KeychainStore.get(.refreshToken) else {
            throw APIClient.APIError.notAuthenticated
        }
        let email = accountEmail ?? ""
        let task = Task<String, Error> {
            let tokens = try await cognito.refresh(refreshToken: refreshToken)
            store(tokens, email: email)
            return tokens.idToken
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    nonisolated func clear() {
        KeychainStore.clearAll()
    }
}
