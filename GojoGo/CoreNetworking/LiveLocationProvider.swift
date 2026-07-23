import CoreLocation

/// One-shot device location for "Send Location" in My World.
///
/// Deliberately not a long-lived tracker: it asks for a single fix, hands it
/// back, and stops the manager, so nothing keeps the GPS warm after the bubble
/// is sent. The place name comes from a reverse geocode when one is available —
/// the coordinates are what actually matter, so a failed geocode is not an error.
@MainActor
final class LiveLocationProvider: NSObject, CLLocationManagerDelegate {

    static let shared = LiveLocationProvider()

    enum LocationError: Error {
        /// The user declined (or restricted) location access.
        case denied
        /// No fix arrived in time.
        case unavailable
    }

    struct Place {
        var coordinate: CLLocationCoordinate2D
        /// Short human label, e.g. "Boulevard d'Anfa, Casablanca".
        var name: String
    }

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation, Error>] = []
    private var timeout: Task<Void, Never>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Requests permission if needed, waits for one fix, then reverse geocodes it.
    func currentPlace() async throws -> Place {
        let location = try await currentLocation()
        return Place(coordinate: location.coordinate,
                     name: await Self.placeName(for: location) ?? "Current Location")
    }

    func currentLocation() async throws -> CLLocation {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { throw LocationError.denied }

        // A recent fix is good enough and avoids a second cold start.
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -60 {
            return cached
        }
        let awaitingPermission = status == .notDetermined
        return try await withCheckedThrowingContinuation { cont in
            waiters.append(cont)
            if awaitingPermission {
                // A fix requested before the user answers is dropped by
                // CoreLocation — wait for the authorization callback to ask.
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
            startTimeout(seconds: awaitingPermission ? 45 : 12)
        }
    }

    private func startTimeout(seconds: Double) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finish(.failure(LocationError.unavailable))
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeout?.cancel(); timeout = nil
        let pending = waiters
        waiters = []
        manager.stopUpdatingLocation()
        for cont in pending { cont.resume(with: result) }
    }

    private static func placeName(for location: CLLocation) async -> String? {
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        let street = mark.thoroughfare ?? mark.name
        let city = mark.locality ?? mark.administrativeArea
        return [street, city].compactMap { $0 }.joined(separator: ", ").nilIfEmpty
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.finish(.success(last)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // `locationUnknown` is transient — the manager keeps trying, so let the
        // timeout decide rather than failing the send on a first stumble.
        if (error as? CLError)?.code == .locationUnknown { return }
        Task { @MainActor in self.finish(.failure(error)) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted:
                self.finish(.failure(LocationError.denied))
            case .authorizedWhenInUse, .authorizedAlways:
                // Permission just granted — the request made while `.notDetermined`
                // is dropped by CoreLocation, so ask again now that we may.
                if !self.waiters.isEmpty { manager.requestLocation() }
            default:
                break
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
