import SwiftUI

/// The shared track catalog (`music` module). Read-only from the app — tracks
/// are inserted by the operator, so there is no create path here.
@MainActor
final class MusicStore {

    static let shared = MusicStore()

    /// Trending is the default browse and doesn't change between openings of
    /// the picker, so it's worth not re-fetching on every sheet present.
    private var trendingCache: [MusicTrack] = []

    func reset() {
        trendingCache = []
    }

    /// Blank query → trending. Trending is cached; searches never are.
    func browse(query: String = "", limit: Int = 30) async throws -> [MusicTrack] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty, !trendingCache.isEmpty {
            return trendingCache
        }
        var path = "/v1/music/tracks?limit=\(limit)"
        if !cleaned.isEmpty,
           let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&q=\(encoded)"
        }
        let list: [MusicTrackDTO] = try await APIClient.shared.get(path)
        let tracks = list.map { map($0) }
        if cleaned.isEmpty {
            trendingCache = tracks
        }
        return tracks
    }

    private func map(_ dto: MusicTrackDTO) -> MusicTrack {
        MusicTrack(
            id: dto.id,
            title: dto.title,
            artist: dto.artist ?? "Unknown artist",
            artworkURL: dto.artworkUrl,
            audioURL: dto.audioUrl,
            durationMs: max(dto.durationMs, 1))
    }
}
