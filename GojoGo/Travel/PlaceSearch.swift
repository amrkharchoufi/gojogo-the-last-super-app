import Foundation
import CoreLocation
import MapKit

/// Forward geocoding for the GojoTravel destination field.
///
/// "Where to?" used to filter a hardcoded list, which in this app is an empty
/// one — so typing anything at all produced nothing. This asks a real gazetteer
/// instead, biased toward where the rider actually is, so the first keystrokes
/// of a street or a café name return the same kind of ranked guesses a maps app
/// gives.
///
/// Mapbox is the primary because the map itself is Mapbox: a result you tap is
/// guaranteed to sit on the tiles you're looking at. Apple's MapKit is the
/// fallback rather than a second opinion — it covers the case the token is
/// missing (which is a real one here, the token file is gitignored) or the
/// network call fails, and it needs no key at all.
enum PlaceSearch {

    /// Ranked suggestions for a partial query. Never throws: an empty list and
    /// a failed lookup are the same thing to somebody typing.
    static func suggest(
        _ query: String,
        near proximity: CLLocationCoordinate2D?,
        limit: Int = 8
    ) async -> [TravelPlace] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }

        let mapbox = await mapboxSuggest(q, near: proximity, limit: limit)
        if !mapbox.isEmpty { return mapbox }
        return await appleSuggest(q, near: proximity, limit: limit)
    }

    // MARK: Mapbox Geocoding v6

    private static func mapboxSuggest(
        _ query: String,
        near proximity: CLLocationCoordinate2D?,
        limit: Int
    ) async -> [TravelPlace] {
        let token = MapboxConfig.accessToken
        guard !token.isEmpty else { return [] }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.mapbox.com"
        components.path = "/search/geocode/v6/forward"
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "autocomplete", value: "true"),
            URLQueryItem(name: "limit", value: String(min(limit, 10))),
            // Everything a car can be told to drive to. Countries and regions
            // are excluded on purpose — "France" is not a pickup instruction.
            URLQueryItem(name: "types",
                         value: "poi,address,street,neighborhood,locality,place,postcode"),
            URLQueryItem(name: "access_token", value: token),
        ]
        if let code = Locale.current.language.languageCode?.identifier {
            items.append(URLQueryItem(name: "language", value: code))
        }
        if let proximity {
            items.append(URLQueryItem(
                name: "proximity",
                value: String(format: "%.5f,%.5f", proximity.longitude, proximity.latitude)))
        }
        components.queryItems = items
        guard let url = components.url else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
            return dedupe(decoded.features.compactMap { $0.place })
        } catch {
            return []
        }
    }

    // MARK: MapKit fallback

    private static func appleSuggest(
        _ query: String,
        near proximity: CLLocationCoordinate2D?,
        limit: Int
    ) async -> [TravelPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let proximity {
            request.region = MKCoordinateRegion(
                center: proximity,
                latitudinalMeters: 60_000,
                longitudinalMeters: 60_000)
        }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        let places = response.mapItems.prefix(limit).map { item -> TravelPlace in
            let mark = item.placemark
            let detail = [mark.thoroughfare, mark.locality, mark.administrativeArea, mark.country]
                .compactMap { $0 }
                .joined(separator: ", ")
            return TravelPlace(
                name: item.name ?? mark.name ?? query,
                subtitle: detail.isEmpty ? "Nearby" : detail,
                latitude: mark.coordinate.latitude,
                longitude: mark.coordinate.longitude,
                icon: "mappin")
        }
        return dedupe(Array(places))
    }

    // MARK: Shared

    /// Both providers happily return the same café twice under slightly
    /// different names. Same name at the same corner is one row.
    private static func dedupe(_ places: [TravelPlace]) -> [TravelPlace] {
        var seen = Set<String>()
        return places.filter { place in
            let key = String(format: "%@|%.4f|%.4f",
                             place.name.lowercased(), place.latitude, place.longitude)
            return seen.insert(key).inserted
        }
    }

    static func icon(for featureType: String?) -> String {
        switch featureType {
        case "address": return "house"
        case "street": return "road.lanes"
        case "neighborhood", "locality", "place": return "building.2"
        case "postcode": return "number"
        default: return "mappin"
        }
    }

    // MARK: - Response

    private struct GeocodeResponse: Decodable {
        let features: [Feature]
    }

    private struct Feature: Decodable {
        let properties: Properties
        let geometry: Geometry?

        var place: TravelPlace? {
            // v6 repeats the point in `properties.coordinates`; the GeoJSON
            // geometry is the fallback so one missing field isn't a dropped row.
            let lat = properties.coordinates?.latitude ?? geometry?.coordinates.last
            let lon = properties.coordinates?.longitude ?? geometry?.coordinates.first
            guard let lat, let lon,
                  let name = properties.name_preferred ?? properties.name else { return nil }
            let subtitle = properties.place_formatted
                ?? properties.full_address
                ?? "Tap to set as destination"
            return TravelPlace(
                name: name,
                subtitle: subtitle,
                latitude: lat,
                longitude: lon,
                icon: PlaceSearch.icon(for: properties.feature_type))
        }
    }

    private struct Properties: Decodable {
        let name: String?
        let name_preferred: String?
        let place_formatted: String?
        let full_address: String?
        let feature_type: String?
        let coordinates: Point?
    }

    private struct Point: Decodable {
        let latitude: Double
        let longitude: Double
    }

    private struct Geometry: Decodable {
        /// GeoJSON Point: `[longitude, latitude]`.
        let coordinates: [Double]
    }
}
