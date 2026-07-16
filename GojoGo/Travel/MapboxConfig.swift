import Foundation

/// Mapbox access configuration for GojoTravel.
///
/// Put your **public** token (`pk.…`) in `GojoGo/MapboxAccessToken` (gitignored).
/// Mapbox also auto-reads that filename from the app bundle.
/// Secret `sk.` tokens belong only in `~/.netrc` for SPM downloads.
enum MapboxConfig {
    static var accessToken: String {
        if let bundled = bundledToken(), !bundled.isEmpty { return bundled }
        if let env = ProcessInfo.processInfo.environment["MAPBOX_ACCESS_TOKEN"], !env.isEmpty {
            return env
        }
        return ""
    }

    static var isPublicToken: Bool { accessToken.hasPrefix("pk.") }

    private static func bundledToken() -> String? {
        let candidates = [
            Bundle.main.url(forResource: "MapboxAccessToken", withExtension: nil),
            Bundle.main.url(forResource: "MapboxAccessToken", withExtension: "txt"),
        ]
        for url in candidates.compactMap({ $0 }) {
            if let raw = try? String(contentsOf: url, encoding: .utf8) {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        // Dev fallback: read from source tree when running from Xcode without copy yet.
        let src = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MapboxAccessToken")
        if let raw = try? String(contentsOf: src, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
