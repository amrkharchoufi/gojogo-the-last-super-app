import SwiftUI
import MapKit

/// A rendered-once map thumbnail for location bubbles.
///
/// A live `Map` in a chat bubble means a full MKMapView per message, which is
/// what made scrolling past a shared pin stutter. `MKMapSnapshotter` gives the
/// same picture as a plain image, cached per coordinate for the session.
struct StaticLocationMap: View {
    let coordinate: CLLocationCoordinate2D
    var span: CLLocationDegrees = 0.01

    @State private var snapshot: UIImage?
    @Environment(\.colorScheme) private var colorScheme

    private var cacheKey: String {
        String(format: "%.5f,%.5f,%.4f,%@", coordinate.latitude, coordinate.longitude, span,
               colorScheme == .dark ? "d" : "l")
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    IMColor.chrome
                }

                Image(systemName: "mappin.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, IMColor.blue)
                    .font(.system(size: 26))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            }
            .task(id: cacheKey) {
                let size = proxy.size
                guard size.width > 1, size.height > 1 else { return }
                let image = await MapSnapshotCache.shared.snapshot(
                    at: coordinate, span: span, size: size, dark: colorScheme == .dark,
                    key: cacheKey)
                withAnimation(.easeOut(duration: 0.2)) { snapshot = image }
            }
        }
        .clipped()
    }
}

/// Session-lived cache of rendered map thumbnails, keyed by coordinate + style.
@MainActor
final class MapSnapshotCache {

    static let shared = MapSnapshotCache()

    private var images: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func snapshot(at coordinate: CLLocationCoordinate2D, span: CLLocationDegrees,
                  size: CGSize, dark: Bool, key: String) async -> UIImage? {
        if let cached = images[key] { return cached }
        if let running = inFlight[key] { return await running.value }

        let task = Task<UIImage?, Never> {
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
            options.size = size
            options.mapType = .standard
            options.showsBuildings = true
            options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
            let snapshotter = MKMapSnapshotter(options: options)
            return await withCheckedContinuation { continuation in
                snapshotter.start { snapshot, _ in
                    continuation.resume(returning: snapshot?.image)
                }
            }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { images[key] = image }
        return image
    }
}
