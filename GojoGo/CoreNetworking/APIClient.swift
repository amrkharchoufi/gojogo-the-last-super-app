import Foundation
import UIKit

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

    /// Timestamps in DTOs are `String` by convention and parsed with
    /// `BackendDate` at the point of use — but the decoder is taught the
    /// backend's format anyway, because the default (`.deferredToDate`, which
    /// wants a *number*) turns any `Date` field somebody adds later into a
    /// decode failure that only fires once the server has a value to send. That
    /// is exactly how the $30 stake broke: `paidAt` was null right up until the
    /// response that said the money had moved.
    private let decoder: JSONDecoder = {
        let json = JSONDecoder()
        json.dateDecodingStrategy = .custom { element in
            let raw = try element.singleValueContainer().decode(String.self)
            guard let date = BackendDate.parse(raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: element.codingPath,
                    debugDescription: "Not a backend timestamp: \(raw)"))
            }
            return date
        }
        return json
    }()
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

    /// Bodyless POST that returns a decoded result — an action whose parameters
    /// are all in the path (e.g. opening a listing's seller thread).
    func post<T: Decodable>(_ path: String) async throws -> T {
        try await request("POST", path, body: nil)
    }

    /// POST a JSON body to an endpoint that returns no content (204).
    func postNoContent(_ path: String, body: some Encodable) async throws {
        _ = try await raw("POST", path, body: try encoder.encode(body))
    }

    func patch<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await request("PATCH", path, body: try encoder.encode(body))
    }

    func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await request("PUT", path, body: try encoder.encode(body))
    }

    /// PUT a JSON body to an endpoint that returns no content (204).
    func putNoContent(_ path: String, body: some Encodable) async throws {
        _ = try await raw("PUT", path, body: try encoder.encode(body))
    }

    func delete(_ path: String) async throws {
        _ = try await raw("DELETE", path, body: nil)
    }

    /// DELETE that answers with the object it changed — a menu editor deletes a
    /// dish and gets the whole restaurant back, so it re-renders from the
    /// server's version rather than patching its own copy.
    func deleteReturning<T: Decodable>(_ path: String) async throws -> T {
        try await request("DELETE", path, body: nil)
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

    /// A plain PUT to a URL the server already signed — the private half of
    /// uploading, used for KYC papers and vehicle documents.
    ///
    /// Deliberately separate from `uploadMedia`: that one mints a *public* URL
    /// under the world-readable prefix and hands it back to be stored. There is
    /// no URL to return here, and there must not be — the caller keeps an object
    /// key that grants nothing on its own, and a reviewer gets a short-lived
    /// signature when they actually look at one.
    func upload(to signedUrl: String, data: Data, contentType: String) async throws {
        guard let url = URL(string: signedUrl) else {
            throw APIError.http(status: -1, message: "Bad upload URL")
        }
        var put = URLRequest(url: url)
        put.httpMethod = "PUT"
        put.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: put, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                                message: "Upload failed")
        }
    }

    /// Presign + direct S3 PUT. Returns the public URL to reference in posts/stories.
    /// `onProgress` is 0…1 for the PUT body (not the presign round-trip).
    func uploadMedia(_ data: Data, contentType: String,
                     onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        // Uploading while acting as a business only decides which profile
        // folder the object lands in; the server re-checks the ownership claim.
        let actAs = await MainActor.run { ActingIdentity.shared.actAsProfileId }
        let presign: PresignDTO = try await post(
            "/v1/media/presign", body: PresignBody(contentType: contentType, actAsProfileId: actAs))
        guard let url = URL(string: presign.uploadUrl) else {
            throw APIError.http(status: -1, message: "Bad upload URL")
        }
        var put = URLRequest(url: url)
        put.httpMethod = "PUT"
        put.setValue(contentType, forHTTPHeaderField: "Content-Type")
        // Replay the signed Cache-Control so the object is written cacheable-forever
        // (content-addressed keys never change). Must match the presign byte-for-byte.
        if let cacheControl = presign.cacheControl {
            put.setValue(cacheControl, forHTTPHeaderField: "Cache-Control")
        }
        let delegate = onProgress.map { UploadProgressDelegate(onProgress: $0) }
        let (_, response) = try await URLSession.shared.upload(for: put, from: data, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                                message: "Media upload failed")
        }
        onProgress?(1)
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

    /// A photo re-encoded for viewing on a phone: long edge capped, EXIF
    /// orientation baked in, paired with the content type to upload it as.
    /// Returns nil when the bytes aren't an image or are an animated GIF, so the
    /// caller uploads them untouched.
    ///
    /// Uploading the camera roll's own file was costing every reader the whole
    /// thing. A modern phone photo is 4000px and several megabytes; the feed
    /// draws it a few hundred points wide and the viewer zooms it to at most a
    /// screen and a half, so all of that resolution was paid for over the
    /// network, on someone else's data plan, and then thrown away at decode.
    /// 2048 is past what any phone screen can resolve and matches the cap
    /// `ImageCache` decodes to.
    ///
    /// A PNG stays a PNG. It is usually the larger encoding for a photograph,
    /// but it is the one that can carry transparency, and flattening a posted
    /// cut-out onto black to save a few hundred kilobytes is not a trade this
    /// gets to make silently.
    static func displayImage(_ data: Data, maxEdge: CGFloat = 2048,
                             quality: CGFloat = 0.85) -> (data: Data, contentType: String)? {
        let type = imageContentType(for: data)
        guard type != "image/gif", let image = UIImage(data: data) else { return nil }
        let keepPNG = type == "image/png"

        let longest = max(image.size.width, image.size.height)
        let ready: UIImage
        if longest > maxEdge {
            let ratio = maxEdge / longest
            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = !keepPNG
            ready = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        } else if keepPNG {
            // Already small enough and already the format we'd write — leave the
            // original bytes alone rather than round-tripping them.
            return (data, type)
        } else {
            ready = image
        }

        if keepPNG {
            guard let png = ready.pngData() else { return nil }
            return (png, "image/png")
        }
        guard let jpeg = ready.jpegData(compressionQuality: quality) else { return nil }
        return (jpeg, "image/jpeg")
    }
}

/// Forwards upload byte progress to a callback. Kept private to APIClient.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
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
