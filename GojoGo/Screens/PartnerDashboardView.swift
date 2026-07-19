import SwiftUI
import CoreLocation
import UIKit
@_spi(Experimental) import MapboxMaps

// MARK: - Partner working dashboard (online driver / courier)

struct PartnerDashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var viewport: Viewport = .camera(
        center: CLLocationCoordinate2D(latitude: 33.5731, longitude: -7.5898),
        zoom: 13, bearing: 0, pitch: 0)
    /// Road-snapped polyline for the active leg (Mapbox Directions).
    @State private var activeRoute: [CLLocationCoordinate2D] = []

    private var role: PartnerRole { app.partnerDashboardRole ?? .driver }

    /// True while heading to pickup or dropoff — show the live route map.
    private var navigating: Bool {
        app.partnerJobPhase == .toPickup || app.partnerJobPhase == .toDropoff
    }

    /// Stable key so we refetch when the leg endpoints change.
    private var routeFetchKey: String {
        guard navigating, let job = app.partnerJob else { return "" }
        let a = legFrom(job), b = legTo(job)
        return String(format: "%.5f,%.5f→%.5f,%.5f", a.latitude, a.longitude, b.latitude, b.longitude)
    }

    var body: some View {
        ZStack {
            GGColor.bg.ignoresSafeArea()

            if navigating, let job = app.partnerJob {
                navigationLayout(job)
                    .transition(.opacity)
            } else {
                dashboardLayout
                    .transition(.opacity)
            }
        }
        // Don't animate the map↔dashboard swap with the phase spring — it can
        // leave the nav layout stuck showing a "Trip complete" card over the map.
        .animation(.easeInOut(duration: 0.25), value: navigating)
        .animation(.easeInOut(duration: 0.3), value: app.partnerOnline)
        .onAppear {
            MapboxOptions.accessToken = MapboxConfig.accessToken
            refreshCamera(animated: false)
        }
        .onChange(of: app.partnerJobPhase) { _, phase in
            if phase == .toPickup || phase == .toDropoff {
                refreshCamera(animated: true)
            }
        }
        // Camera follows less often so the marker can glide without the map jumping.
        .onChange(of: app.partnerJobProgress) { _, new in
            let tick = Int((new * 20).rounded())
            if tick % 5 == 0 || new >= 0.99 { refreshCamera(animated: true) }
        }
        .task(id: routeFetchKey) {
            guard navigating, let job = app.partnerJob else {
                activeRoute = []
                return
            }
            let from = legFrom(job), to = legTo(job)
            // Show endpoints immediately, then replace with the road network path.
            activeRoute = [from, to]
            refreshCamera(animated: false)
            if let road = await MapboxDirections.route(from: from, to: to), road.count >= 2 {
                activeRoute = road
                refreshCamera(animated: true)
            }
        }
    }

    private var dashboardLayout: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    statsRow
                    onlineCard
                    stageContent
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
    }

    // MARK: Navigation (live route map + info card)

    private func navigationLayout(_ job: PartnerJob) -> some View {
        ZStack(alignment: .bottom) {
            PartnerMapView(
                viewport: $viewport,
                route: legRoute(job),
                progress: app.partnerJobProgress,
                destinationLabel: destinationLabel(job),
                destinationIcon: destinationIcon(job),
                partnerIcon: role.icon
            )

            LinearGradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Spacer()
            }

            PartnerActiveJobCard(job: job)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }

    private func coord(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func legFrom(_ job: PartnerJob) -> CLLocationCoordinate2D {
        app.partnerJobPhase == .toPickup
            ? coord(job.originLat, job.originLon)
            : coord(job.pickupLat, job.pickupLon)
    }

    private func legTo(_ job: PartnerJob) -> CLLocationCoordinate2D {
        app.partnerJobPhase == .toPickup
            ? coord(job.pickupLat, job.pickupLon)
            : coord(job.dropoffLat, job.dropoffLon)
    }

    /// Road route for the current leg (origin→pickup, then pickup→dropoff).
    private func legRoute(_ job: PartnerJob) -> [CLLocationCoordinate2D] {
        if activeRoute.count >= 2 { return activeRoute }
        return [legFrom(job), legTo(job)]
    }

    private func destinationLabel(_ job: PartnerJob) -> String {
        if app.partnerJobPhase == .toPickup {
            return job.role == .driver ? "Pickup" : "Restaurant"
        }
        return job.role == .driver ? "Dropoff" : "Customer"
    }

    private func destinationIcon(_ job: PartnerJob) -> String {
        if app.partnerJobPhase == .toPickup {
            return job.role == .driver ? "person.fill" : "fork.knife"
        }
        return job.role == .driver ? "flag.checkered" : "house.fill"
    }

    private func refreshCamera(animated: Bool) {
        guard navigating, let job = app.partnerJob else { return }
        // Fit the remaining driver → destination line, kept above the info card
        // (big bottom padding) and oriented so the way ahead points up.
        let ahead = PartnerRoute.split(legRoute(job), at: app.partnerJobProgress).ahead
        guard ahead.count >= 2, let driver = ahead.first, let dest = ahead.last else { return }
        let dy = dest.latitude - driver.latitude
        let dx = (dest.longitude - driver.longitude) * cos(driver.latitude * .pi / 180)
        let bearing = atan2(dx, dy) * 180 / .pi
        let next: Viewport = .overview(
            geometry: LineString(ahead),
            bearing: bearing,
            pitch: 42,
            geometryPadding: .init(top: 96, leading: 52, bottom: 300, trailing: 52),
            maxZoom: 15.6)
        if animated {
            withViewportAnimation(.easeInOut(duration: 0.55)) { viewport = next }
        } else {
            viewport = next
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                app.closePartnerDashboard()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 36, height: 36)
                    .glassCapsule(tint: Color.black.opacity(0.35), interactive: false, dense: true)
            }
            .buttonStyle(PressableStyle())

            Spacer()

            VStack(spacing: 2) {
                Text("\(role.title.uppercased()) MODE")
                    .font(.ggMono(11, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Wordmark(size: 20, trailing: role.wordmarkTrailing)
            }

            Spacer()

            onlinePill
        }
    }

    private var onlinePill: some View {
        Button {
            app.togglePartnerOnline()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(app.partnerOnline ? GGColor.white : GGColor.textTertiary)
                    .frame(width: 7, height: 7)
                Text(app.partnerOnline ? "Online" : "Offline")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .glassCapsule(tint: Color.black.opacity(0.35), interactive: false, dense: true)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(value: String(format: "$%.2f", app.partnerEarnings(role)), label: "Today")
            statTile(value: "\(app.partnerJobs(role))",
                     label: role == .driver ? "Trips" : "Deliveries")
            statTile(value: String(format: "%.1f★", app.partnerRating(role)), label: "Rating")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.ggMono(10, .semibold))
                .foregroundStyle(GGColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glass(cornerRadius: 18, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    // MARK: Online status card (radar / prompt)

    @ViewBuilder
    private var onlineCard: some View {
        if app.partnerJobPhase == .idle {
            VStack(spacing: 16) {
                PartnerRadar(active: app.partnerOnline, icon: role.icon)
                    .frame(width: 132, height: 132)

                VStack(spacing: 6) {
                    Text(app.partnerOnline ? "Looking for \(role.jobNoun) requests" : "You're offline")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(app.partnerOnline
                         ? "Stay near busy areas to get matched faster. We'll ping you the moment a request comes in."
                         : "Go online to start receiving \(role.jobNoun) requests near you.")
                        .explanatory(14)
                        .foregroundStyle(GGColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    app.togglePartnerOnline()
                } label: {
                    Text(app.partnerOnline ? "Go offline" : "Go online")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(app.partnerOnline ? GGColor.textPrimary : GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            Capsule().fill(app.partnerOnline ? GGColor.ink(0.1) : GGColor.white))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .glass(cornerRadius: 24, tint: Color.black.opacity(0.3), floating: true)
        }
    }

    // MARK: Job stages

    @ViewBuilder
    private var stageContent: some View {
        switch app.partnerJobPhase {
        case .idle:
            EmptyView()
        case .offer:
            if let job = app.partnerJob { PartnerOfferCard(job: job) }
        case .toPickup, .toDropoff:
            if let job = app.partnerJob { PartnerActiveJobCard(job: job) }
        case .completed:
            if let job = app.partnerJob { PartnerJobCompleteCard(job: job) }
        }
    }
}

// MARK: - Radar pulse

private struct PartnerRadar: View {
    let active: Bool
    let icon: String
    @State private var pulse = false

    var body: some View {
        ZStack {
            if active {
                ForEach(0..<2) { i in
                    Circle()
                        .stroke(GGColor.ink(0.14), lineWidth: 1.5)
                        .scaleEffect(pulse ? 1.35 : 0.7)
                        .opacity(pulse ? 0 : 0.8)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.9), value: pulse)
                }
            }
            Circle()
                .fill(active ? GGColor.white : GGColor.ink(0.1))
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(active ? GGColor.onAccent : GGColor.textSecondary))
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Incoming request card

private struct PartnerOfferCard: View {
    @EnvironmentObject var app: AppState
    let job: PartnerJob

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("New \(job.role.jobNoun) request", systemImage: "bell.badge.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer()
                Text(job.fareLabel)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }

            HStack(spacing: 12) {
                metric(icon: "location.north.line.fill", value: job.distanceLabel, label: "Distance")
                metric(icon: "clock.fill", value: "\(job.minutes) min", label: "Est. time")
                metric(icon: "person.fill", value: job.customerName, label: job.role == .driver ? "Rider" : "Customer")
            }

            PartnerRouteView(job: job, progress: 0)

            HStack(spacing: 12) {
                Button {
                    app.declinePartnerJob()
                } label: {
                    Text("Decline")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().fill(GGColor.ink(0.1)))
                }
                .buttonStyle(PressableStyle())

                Button {
                    app.acceptPartnerJob()
                } label: {
                    Text("Accept")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().fill(GGColor.white))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(18)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.3), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func metric(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.ggMono(9, .semibold))
                .foregroundStyle(GGColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GGColor.ink(0.05)))
    }
}

// MARK: - Active job card

private struct PartnerActiveJobCard: View {
    @EnvironmentObject var app: AppState
    let job: PartnerJob

    private var headingToPickup: Bool { app.partnerJobPhase == .toPickup }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.partnerStatusLine)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(headingToPickup
                         ? (job.role == .driver ? "Pick up \(job.customerName)" : "Collect the order")
                         : "Drop off at \(job.dropoffName)")
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                }
                Spacer()
                Text(job.fareLabel)
                    .font(.ggMono(14, .semibold))
                    .foregroundStyle(GGColor.onAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(GGColor.white))
            }

            // Turn-by-turn destination line (the map above shows the full route).
            HStack(spacing: 10) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(GGColor.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(headingToPickup ? job.pickupName : job.dropoffName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .lineLimit(1)
                    Text(headingToPickup ? job.pickupSubtitle : job.dropoffSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(job.distanceLabel) · \(job.minutes) min")
                    .font(.ggMono(11, .medium))
                    .foregroundStyle(GGColor.textSecondary)
            }
            .padding(12)
            .glass(cornerRadius: 16)

            // Customer / contact row
            HStack(spacing: 12) {
                UserAvatar(size: 46, letter: String(job.customerName.prefix(1)),
                           imageURL: job.customerAvatarURL)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.customerName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(headingToPickup ? job.pickupName : job.dropoffName)
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                contactButton("phone.fill")
                contactButton("message.fill")
            }
            .padding(12)
            .glass(cornerRadius: 16)

            // Primary action — arrive / navigate (auto-advances, this is a manual nudge)
            Text(headingToPickup
                 ? "Navigating to \(job.pickupName)…"
                 : "En route to \(job.dropoffName)…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GGColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(GGColor.ink(0.08)))
        }
        .padding(18)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.3), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func contactButton(_ icon: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(GGColor.ink(0.1)))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Completed card

private struct PartnerJobCompleteCard: View {
    @EnvironmentObject var app: AppState
    let job: PartnerJob

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(GGColor.white)

            VStack(spacing: 4) {
                Text("\(job.role.jobNoun.capitalized) complete")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Text("Paid to your balance")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
            }

            Text("+ \(job.fareLabel)")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)

            HStack {
                Text("Today's earnings")
                    .font(.system(size: 13))
                    .foregroundStyle(GGColor.textSecondary)
                Spacer()
                Text(String(format: "$%.2f", app.partnerEarnings(job.role)))
                    .font(.ggMono(14, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            .padding(14)
            .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.08)

            Button {
                app.clearCompletedPartnerJob()
            } label: {
                Text(app.partnerOnline ? "Next request" : "Done")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.3), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Stylised route (pickup → dropoff) with a moving marker

private struct PartnerRouteView: View {
    let job: PartnerJob
    let progress: Double   // 0…1 marker position along the route

    var body: some View {
        VStack(spacing: 0) {
            endpoint(dot: GGColor.white, filled: true,
                     title: job.pickupName, subtitle: job.pickupSubtitle)
            // Connector with a moving marker
            HStack(spacing: 12) {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(GGColor.ink(0.14))
                        .frame(width: 2, height: 34)
                    Circle()
                        .fill(GGColor.white)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: job.role.icon)
                                .font(.system(size: 6, weight: .black))
                                .foregroundStyle(GGColor.onAccent))
                        .offset(y: 34 * progress - 1)
                }
                .frame(width: 12)
                Text(job.distanceLabel + " · " + "\(job.minutes) min")
                    .font(.ggMono(10, .medium))
                    .foregroundStyle(GGColor.textTertiary)
                Spacer()
            }
            .padding(.leading, 5)
            endpoint(dot: GGColor.textSecondary, filled: false,
                     title: job.dropoffName, subtitle: job.dropoffSubtitle)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GGColor.ink(0.05)))
    }

    private func endpoint(dot: Color, filled: Bool, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Group {
                if filled {
                    Circle().fill(dot).frame(width: 12, height: 12)
                } else {
                    Circle().strokeBorder(dot, lineWidth: 2).frame(width: 12, height: 12)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Route geometry helpers (progress along a polyline)

enum PartnerRoute {
    /// The point at fractional arc-length `t` along the polyline.
    static func point(on pts: [CLLocationCoordinate2D], at t: Double) -> CLLocationCoordinate2D {
        locate(pts, at: t).point
    }

    /// Splits the polyline at `t` into the traveled part and the remaining part
    /// (both include the split point), for drawing them differently.
    static func split(_ pts: [CLLocationCoordinate2D], at t: Double)
        -> (behind: [CLLocationCoordinate2D], ahead: [CLLocationCoordinate2D]) {
        guard pts.count > 1 else { return (pts, pts) }
        let loc = locate(pts, at: t)
        let behind = Array(pts[0...loc.index]) + [loc.point]
        let ahead = [loc.point] + Array(pts[(loc.index + 1)...])
        return (behind, ahead)
    }

    private static func locate(_ pts: [CLLocationCoordinate2D], at t: Double)
        -> (point: CLLocationCoordinate2D, index: Int) {
        guard pts.count > 1 else {
            return (pts.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0), 0)
        }
        var segLens: [Double] = []
        var total = 0.0
        for i in 1..<pts.count {
            let d = dist(pts[i - 1], pts[i]); segLens.append(d); total += d
        }
        let target = max(0, min(1, t)) * total
        var acc = 0.0
        for i in 1..<pts.count {
            let d = segLens[i - 1]
            if acc + d >= target || i == pts.count - 1 {
                let local = d == 0 ? 0 : min(1, (target - acc) / d)
                let p = CLLocationCoordinate2D(
                    latitude: pts[i - 1].latitude + (pts[i].latitude - pts[i - 1].latitude) * local,
                    longitude: pts[i - 1].longitude + (pts[i].longitude - pts[i - 1].longitude) * local)
                return (p, i - 1)
            }
            acc += d
        }
        return (pts[pts.count - 1], pts.count - 2)
    }

    private static func dist(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dl = a.latitude - b.latitude, dg = a.longitude - b.longitude
        return (dl * dl + dg * dg).squareRoot()
    }
}

// MARK: - Live route map (navigation guide for the active leg)

struct PartnerMapView: View {
    @Binding var viewport: Viewport
    var route: [CLLocationCoordinate2D]
    var progress: Double
    var destinationLabel: String
    var destinationIcon: String
    var partnerIcon: String

    private var partner: CLLocationCoordinate2D {
        PartnerRoute.point(on: route, at: progress)
    }

    private var legs: (behind: [CLLocationCoordinate2D], ahead: [CLLocationCoordinate2D]) {
        PartnerRoute.split(route, at: progress)
    }

    var body: some View {
        Map(viewport: $viewport) {
            PolylineAnnotationGroup {
                if legs.behind.count >= 2 {
                    PolylineAnnotation(lineCoordinates: legs.behind)
                        .lineWidth(6)
                        .lineOpacity(0.35)
                }
                if legs.ahead.count >= 2 {
                    PolylineAnnotation(lineCoordinates: legs.ahead)
                        .lineWidth(6)
                        .lineOpacity(1)
                }
            }
            .lineColor(UIColor.white)
            .lineColorUseTheme(.none)
            .lineJoin(.round)
            .lineCap(.round)
            .lineEmissiveStrength(1)
            // Above buildings/POIs so the white route isn't buried (looked black).
            .slot(.top)

            if let dest = route.last {
                MapViewAnnotation(coordinate: dest) {
                    DeliveryMapPin(icon: destinationIcon, label: destinationLabel, accent: true)
                }
                .allowOverlap(true)
            }

            MapViewAnnotation(coordinate: partner) {
                PartnerMapMarker(icon: partnerIcon)
            }
            .allowOverlap(true)
        }
        .mapStyle(.standard(lightPreset: .night, show3dObjects: true))
        .ignoresSafeArea()
    }
}

struct PartnerMapMarker: View {
    var icon: String
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(GGColor.onAccent)
            .frame(width: 38, height: 38)
            .background(Circle().fill(GGColor.white))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
    }
}
