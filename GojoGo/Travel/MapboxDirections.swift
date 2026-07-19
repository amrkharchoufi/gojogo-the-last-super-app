import Foundation
import CoreLocation

/// Fetches a road-following polyline via the Mapbox Directions API.
enum MapboxDirections {
    enum Profile: String {
        case driving
        case drivingTraffic = "driving-traffic"
        case walking
        case cycling
    }

    /// Returns GeoJSON coordinates along the road network from `from` → `to`.
    /// Falls back to `nil` if the token is missing or the request fails.
    static func route(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        profile: Profile = .driving
    ) async -> [CLLocationCoordinate2D]? {
        let token = MapboxConfig.accessToken
        guard !token.isEmpty else { return nil }

        // Build path + query separately so the `;` between waypoints isn't
        // misparsed by URLComponents(string:).
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.mapbox.com"
        components.path = String(
            format: "/directions/v5/mapbox/%@/%.6f,%.6f;%.6f,%.6f",
            profile.rawValue,
            from.longitude, from.latitude,
            to.longitude, to.latitude
        )
        components.queryItems = [
            URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "access_token", value: token),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(DirectionsResponse.self, from: data)
            guard let coords = decoded.routes.first?.geometry.coordinates, coords.count >= 2 else {
                return nil
            }
            return coords.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
        } catch {
            return nil
        }
    }

    // MARK: - Response

    private struct DirectionsResponse: Decodable {
        let routes: [Route]
    }

    private struct Route: Decodable {
        let geometry: Geometry
    }

    private struct Geometry: Decodable {
        /// GeoJSON LineString: each point is `[longitude, latitude]`.
        let coordinates: [[Double]]
    }
}
