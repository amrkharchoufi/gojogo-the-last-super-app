import SwiftUI
import CoreLocation
import UIKit
import MapboxMaps

/// Mapbox map surface for GojoTravel — dark night style to match the app.
struct TravelMapView: View {
    @Binding var viewport: Viewport
    var pickup: TravelPlace?
    var dropoff: TravelPlace?
    var driver: TravelDriver?
    var showRoute: Bool

    var body: some View {
        Map(viewport: $viewport) {
            if showRoute, let pickup, let dropoff {
                PolylineAnnotation(lineCoordinates: routeCoordinates(from: pickup, to: dropoff))
                    .lineColor(StyleColor(UIColor.white))
                    .lineWidth(4)
                    .lineOpacity(0.85)
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
    }

    private func coord(_ place: TravelPlace) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }

    /// Soft bezier-ish polyline between pickup and dropoff (prototype route).
    private func routeCoordinates(from a: TravelPlace, to b: TravelPlace) -> [CLLocationCoordinate2D] {
        let start = coord(a)
        let end = coord(b)
        let mid = CLLocationCoordinate2D(
            latitude: (start.latitude + end.latitude) / 2 + 0.004,
            longitude: (start.longitude + end.longitude) / 2 - 0.003
        )
        var points: [CLLocationCoordinate2D] = []
        let steps = 24
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let u = 1 - t
            let lat = u * u * start.latitude + 2 * u * t * mid.latitude + t * t * end.latitude
            let lon = u * u * start.longitude + 2 * u * t * mid.longitude + t * t * end.longitude
            points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        return points
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
