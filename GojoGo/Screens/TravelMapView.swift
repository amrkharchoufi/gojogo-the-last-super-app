import SwiftUI
import CoreLocation
import UIKit
@_spi(Experimental) import MapboxMaps

/// Mapbox map surface for GojoTravel — dark night style to match the app.
struct TravelMapView: View {
    @Binding var viewport: Viewport
    var pickup: TravelPlace?
    var dropoff: TravelPlace?
    var driver: TravelDriver?
    var showRoute: Bool

    @State private var routeCoordinates: [CLLocationCoordinate2D] = []

    private var routeKey: String {
        guard showRoute, let pickup, let dropoff else { return "" }
        return String(format: "%.5f,%.5f→%.5f,%.5f",
                      pickup.latitude, pickup.longitude,
                      dropoff.latitude, dropoff.longitude)
    }

    var body: some View {
        Map(viewport: $viewport) {
            if showRoute, routeCoordinates.count >= 2 {
                PolylineAnnotationGroup {
                    PolylineAnnotation(lineCoordinates: routeCoordinates)
                        .lineWidth(5)
                        .lineOpacity(1)
                }
                .lineColor(UIColor.white)
                .lineColorUseTheme(.none)
                .lineJoin(.round)
                .lineCap(.round)
                .lineEmissiveStrength(1)
                .slot(.top)
            }

            if let pickup {
                MapViewAnnotation(coordinate: coord(pickup)) {
                    TravelPin(kind: .pickup, label: "Pickup")
                }
                .allowOverlap(true)
            }

            if let dropoff {
                MapViewAnnotation(coordinate: coord(dropoff)) {
                    TravelPin(kind: .dropoff, label: "Dropoff")
                }
                .allowOverlap(true)
            }

            if let driver {
                MapViewAnnotation(coordinate: CLLocationCoordinate2D(
                    latitude: driver.latitude, longitude: driver.longitude
                )) {
                    DriverMapMarker()
                }
                .allowOverlap(true)
            }
        }
        .mapStyle(.standard(lightPreset: .night, show3dObjects: true))
        .ignoresSafeArea()
        .task(id: routeKey) {
            guard showRoute, let pickup, let dropoff else {
                routeCoordinates = []
                return
            }
            let from = coord(pickup), to = coord(dropoff)
            routeCoordinates = [from, to]
            if let road = await MapboxDirections.route(from: from, to: to), road.count >= 2 {
                routeCoordinates = road
            }
        }
    }

    private func coord(_ place: TravelPlace) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }
}

enum TravelPinKind { case pickup, dropoff }

struct TravelPin: View {
    var kind: TravelPinKind
    var label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.ggMono(9, .semibold))
                .foregroundStyle(GGColor.onAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(GGColor.white))
            ZStack {
                Circle()
                    .fill(GGColor.white)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(Color.black)
                    .frame(width: kind == .pickup ? 8 : 10, height: kind == .pickup ? 8 : 10)
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        }
    }
}

struct DriverMapMarker: View {
    var body: some View {
        Image(systemName: "car.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(GGColor.onAccent)
            .frame(width: 34, height: 34)
            .background(Circle().fill(GGColor.white))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
    }
}

enum TravelCamera {
    static let homePitch: CGFloat = 58
    static let homeBearing: CLLocationDirection = 28

    static func fit(pickup: TravelPlace, dropoff: TravelPlace?) -> Viewport {
        guard let dropoff else {
            return .camera(
                center: CLLocationCoordinate2D(latitude: pickup.latitude, longitude: pickup.longitude),
                zoom: 14.8,
                bearing: homeBearing,
                pitch: homePitch
            )
        }
        let mid = CLLocationCoordinate2D(
            latitude: (pickup.latitude + dropoff.latitude) / 2,
            longitude: (pickup.longitude + dropoff.longitude) / 2
        )
        let span = max(
            abs(pickup.latitude - dropoff.latitude),
            abs(pickup.longitude - dropoff.longitude)
        )
        let zoom = max(11.5, min(14.6, 14.8 - span * 38))
        return .camera(center: mid, zoom: zoom, bearing: homeBearing, pitch: min(homePitch, 52))
    }

    static func follow(driver: TravelDriver) -> Viewport {
        .camera(
            center: CLLocationCoordinate2D(latitude: driver.latitude, longitude: driver.longitude),
            zoom: 15.2,
            bearing: homeBearing + 12,
            pitch: 62
        )
    }
}

// MARK: - GojoDelivery map (same Mapbox night style as Travel)

struct DeliveryMapView: View {
    @Binding var viewport: Viewport
    var restaurant: CLLocationCoordinate2D
    var home: CLLocationCoordinate2D
    var courier: CLLocationCoordinate2D?
    var showRoute: Bool

    @State private var routeCoordinates: [CLLocationCoordinate2D] = []

    private var routeKey: String {
        guard showRoute else { return "" }
        return String(format: "%.5f,%.5f→%.5f,%.5f",
                      restaurant.latitude, restaurant.longitude,
                      home.latitude, home.longitude)
    }

    var body: some View {
        Map(viewport: $viewport) {
            if showRoute, routeCoordinates.count >= 2 {
                PolylineAnnotationGroup {
                    PolylineAnnotation(lineCoordinates: routeCoordinates)
                        .lineWidth(5)
                        .lineOpacity(1)
                }
                .lineColor(UIColor.white)
                .lineColorUseTheme(.none)
                .lineJoin(.round)
                .lineCap(.round)
                .lineEmissiveStrength(1)
                .slot(.top)
            }

            MapViewAnnotation(coordinate: restaurant) {
                DeliveryMapPin(icon: "fork.knife", label: "Restaurant", accent: false)
            }
            .allowOverlap(true)

            MapViewAnnotation(coordinate: home) {
                DeliveryMapPin(icon: "house.fill", label: "You", accent: false)
            }
            .allowOverlap(true)

            if let courier {
                MapViewAnnotation(coordinate: courier) {
                    DeliveryCourierMarker()
                }
                .allowOverlap(true)
            }
        }
        .mapStyle(.standard(lightPreset: .night, show3dObjects: true))
        .ignoresSafeArea()
        .task(id: routeKey) {
            guard showRoute else {
                routeCoordinates = []
                return
            }
            routeCoordinates = [restaurant, home]
            if let road = await MapboxDirections.route(from: restaurant, to: home), road.count >= 2 {
                routeCoordinates = road
            }
        }
    }
}

struct DeliveryMapPin: View {
    var icon: String
    var label: String
    var accent: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.ggMono(9, .semibold))
                .foregroundStyle(GGColor.onAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(GGColor.white))
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accent ? GGColor.onAccent : .white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(accent ? GGColor.white : Color(white: 0.12)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        }
    }
}

struct DeliveryCourierMarker: View {
    var body: some View {
        Image(systemName: "bicycle")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(GGColor.onAccent)
            .frame(width: 36, height: 36)
            .background(Circle().fill(GGColor.white))
            .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
    }
}

enum DeliveryCamera {
    static let pitch: CGFloat = 52
    static let bearing: CLLocationDirection = 22

    static func fit(restaurant: CLLocationCoordinate2D,
                    home: CLLocationCoordinate2D,
                    followCourier: CLLocationCoordinate2D? = nil) -> Viewport {
        if let courier = followCourier {
            return .camera(
                center: courier,
                zoom: 15.0,
                bearing: bearing + 10,
                pitch: 58
            )
        }
        let mid = CLLocationCoordinate2D(
            latitude: (restaurant.latitude + home.latitude) / 2,
            longitude: (restaurant.longitude + home.longitude) / 2
        )
        let span = max(
            abs(restaurant.latitude - home.latitude),
            abs(restaurant.longitude - home.longitude)
        )
        let zoom = max(12.2, min(14.8, 14.9 - span * 40))
        return .camera(center: mid, zoom: zoom, bearing: bearing, pitch: pitch)
    }
}
