import SwiftUI
import CoreLocation
import PhotosUI
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
    /// The token screen. Local state rather than `AppState`, and presented only
    /// from here: this cover is the one owner, so there is no second live screen
    /// that could quietly win the presentation.
    @State private var showTokens = false

    private var role: PartnerRole { app.partnerDashboardRole ?? .driver }

    /// True while heading to pickup or dropoff — show the live route map.
    private var navigating: Bool {
        app.partnerJobPhase == .toPickup || app.partnerJobPhase == .toDropoff
    }

    /// Stable key so we refetch when the leg endpoints change. Three decimals
    /// (~110 m) on purpose: on a real trip the origin is the driver's live
    /// position, and a key at GPS precision would call Mapbox Directions on
    /// every jitter of the antenna.
    private var routeFetchKey: String {
        guard navigating, let job = app.partnerJob else { return "" }
        let a = legFrom(job), b = legTo(job)
        return String(format: "%.3f,%.3f→%.3f,%.3f", a.latitude, a.longitude, b.latitude, b.longitude)
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
        .sheet(isPresented: $showTokens) {
            TokensView().environmentObject(app)
        }
        .task { await app.refreshTokens() }
        // A courier may have accepted on another device, or closed the app
        // holding somebody's dinner. Either way the order is still theirs.
        .task { await app.refreshCourierJob() }
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

            // This screen has been calling `showWalletNotice` since Phase 3 and
            // never drawing it — a refused go-online, a lost race for an offer,
            // and now a refused payout all went to a banner nothing rendered.
            // Money made that unaffordable: a withdrawal that quietly does
            // nothing is the worst thing a screen about money can do.
            if let notice = app.walletNotice {
                EconomyNoticeBanner(message: notice) { app.walletNotice = nil }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    statsRow
                    tokenCard
                    courierDeliveryCard
                    onlineCard
                    workerWalletCard
                    stageContent
                    negotiationCard
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .dismissesKeyboard()
        }
        .animation(.ggOverlay, value: app.walletNotice)
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

    // MARK: Ride tokens (Phase 3 M4)

    /// The one place an empty Driver Mode gets explained.
    ///
    /// Dispatch stops offering trips to a driver who can't pay for them —
    /// silently, which is the correct behaviour and an invisible one. Without
    /// this card, going online with no tokens looks exactly like going online in
    /// a quiet city, and the driver has no way to tell those apart.
    ///
    /// Only for a real driver. The demo has no tokens because it has no trips,
    /// and a currency for a job somebody hasn't been approved for is a screen
    /// that raises a question the app can't answer yet.
    @ViewBuilder
    private var tokenCard: some View {
        if app.isDispatchRegistered, role == .driver, app.partnerJobPhase == .idle {
            Button {
                showTokens = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: app.tokensNeedAttention
                          ? "exclamationmark.circle.fill" : "ticket.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(GGColor.ink(0.1)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(app.tokenBalance) ride \(app.tokenBalance == 1 ? "token" : "tokens")")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(GGColor.textPrimary)
                        // The server's sentence, never one composed here: only
                        // the module that prices a ride knows whether a balance
                        // is enough to take one.
                        Text(app.tokenRefusal ?? "Tap to see what a trip costs, or top up.")
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GGColor.textTertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .glass(cornerRadius: 20, fillOpacity: 0.05, borderOpacity: 0.08)
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: The delivery they are carrying (Phase 4 M1/M2)

    @ViewBuilder
    private var courierDeliveryCard: some View {
        if let job = app.courierJob {
            // Keyed on the order, so the next delivery gets empty fields. A card
            // that kept its `@State` across two orders would offer the last
            // customer's PIN to this one's door.
            CourierDeliveryCard(job: job)
                .id(job.id)
        }
    }

    // MARK: What the work paid (Phase 4 M2)

    /// Shown to anybody in a registry, in either mode, because the surface is
    /// `dispatch`'s and a person who drives and delivers has one balance.
    @ViewBuilder
    private var workerWalletCard: some View {
        if app.isDispatchRegistered {
            WorkerWalletCard()
        }
    }

    // MARK: Online status card (radar / prompt)

    @ViewBuilder
    private var onlineCard: some View {
        // Not while they are carrying something. A radar saying "looking for
        // delivery requests" above an order somebody is holding is the app
        // contradicting itself, and dispatch is not offering them anything
        // anyway — accepting made them BUSY.
        if app.partnerJobPhase == .idle && app.courierJob == nil {
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

    // MARK: The price on the table (driver-side negotiation, Phase 3 M3)

    @ViewBuilder
    private var negotiationCard: some View {
        if let ride = app.driverNegotiation {
            DriverNegotiationCard(ride: ride)
                .id(ride.id)
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

// MARK: - The delivery being carried (Phase 4 M1), and its handoff (M2)

/// The other half of Courier Mode. Dispatch found the work; this is what the
/// work turned out to be, and it is the whole screen while it is on it — above
/// the online card, because somebody holding a bag of food is not looking for
/// the go-offline button.
///
/// M1 gave it two taps and no more: collected, and handed over. Both are
/// deliberate rather than inferred from a position, because being *at* a counter
/// is not the same as having what is on it, and a delivery confirmed by geofence
/// is a delivery somebody can be paid for without doing.
///
/// M2 made each tap prove something, and everything about how it is drawn comes
/// from the same constraint: this is read at a counter with a bag in one hand,
/// or on a doorstep in the rain. So the digits are large enough to check at
/// arm's length, the refusal appears *under the field* with what was typed still
/// in it, and there is never more than one primary action on screen.
private struct CourierDeliveryCard: View {
    @EnvironmentObject var app: AppState
    let job: CourierJobDTO

    /// The two codes are separate pieces of state on purpose: they are two
    /// different numbers from two different people, and carrying one into the
    /// other's field is how a courier hands over using the restaurant's code.
    @State private var pickupCode = ""
    @State private var deliveryPin = ""
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?

    private var busy: Bool { app.courierHandoffBusy || app.courierProofUploading }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: job.isCollected ? "figure.wave" : "bag.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(GGColor.ink(0.1)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.courierInstruction ?? "")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text("\(job.itemCount) \(job.itemCount == 1 ? "item" : "items") · "
                         + DeliveryStore.money(cents: job.payMinor) + " for this delivery")
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                }
                Spacer(minLength: 4)
            }

            courierLeg(icon: "storefront.fill", title: job.merchantName,
                       detail: job.isCollected ? "Collected" : "Pick up here",
                       dim: job.isCollected)
            courierLeg(icon: "house.fill", title: job.addressLabel,
                       detail: job.addressLine.isEmpty ? "Delivery address" : job.addressLine,
                       dim: !job.isCollected)

            // The customer's note is the one piece of free text a courier
            // genuinely needs — "second floor, no bell" is the difference
            // between a delivery and a phone call.
            if !job.note.isEmpty || !job.addressNote.isEmpty {
                Text([job.note, job.addressNote].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // And when the note isn't enough, the thread the server opened when
            // this was assigned — the other half of an address.
            if job.conversationId != nil {
                Button {
                    app.messageDeliveryCustomer()
                } label: {
                    Label("Message the customer", systemImage: "message.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glass(cornerRadius: 16)
                }
                .buttonStyle(PressableStyle())
            }

            if job.isCollected { handOver } else { collect }

            // The server's own words, kept under the field that produced them.
            // Never a sentence composed here: only the server knows whether the
            // attempt that just failed was the last one.
            if let notice = app.courierHandoffNotice {
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GGColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Strictly positive. `-1` is "nobody is counting" — always
                    // so at a counter, and so for any order that never asked
                    // for a code — and drawing it as a number would tell a
                    // courier on a contactless drop that they were out of
                    // chances. Zero says its own thing in the message above,
                    // which is that the photo is now the way through.
                    if app.courierAttemptsLeft > 0 {
                        Text("\(app.courierAttemptsLeft) "
                             + (app.courierAttemptsLeft == 1 ? "try" : "tries") + " left")
                            .font(.ggMono(11, .semibold))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(GGColor.ink(0.10)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.3), floating: true)
        .animation(.ggSnappy, value: app.courierHandoffNotice)
        .animation(.ggSnappy, value: job.isCollected)
        // The picked bytes go up as they came off the picker; re-encoding to the
        // format the server signed for is `courierHandOverWithPhoto`'s job, and
        // it belongs there rather than here because it is a fact about the
        // upload, not about the button that started it.
        .modifier(ProofPhotoPickers(showLibrary: $showLibrary, showCamera: $showCamera,
                                    libraryItem: $libraryItem,
                                    onPicked: { app.courierHandOverWithPhoto($0) }))
    }

    // MARK: Collect

    /// The code the counter reads out. Typing is the primary path and the only
    /// one built: a scanner needs a camera the Simulator does not have, and a
    /// number somebody can say out loud works through a hatch, in the dark, and
    /// on a phone with a cracked lens.
    private var collect: some View {
        VStack(alignment: .leading, spacing: 10) {
            CourierCodeField(
                title: "Pickup code",
                caption: "Ask \(job.merchantName) for it",
                code: $pickupCode)

            Button {
                Keyboard.dismiss()
                app.courierPickedUp(code: pickupCode)
            } label: {
                primaryLabel("I've collected the order")
            }
            .buttonStyle(PressableStyle())
            .disabled(busy)
            .opacity(busy ? 0.55 : 1)
        }
    }

    // MARK: Hand over

    /// One screen for all three doors: the PIN field and the camera are always
    /// both on it, and the server decides which one actually completes the
    /// handoff.
    ///
    /// That is the right shape rather than a concession. A courier at a door is
    /// not classifying an order; they are doing whichever of two things the
    /// person in front of them makes possible. Typing the six digits works on a
    /// PIN order. Tapping "Delivered" with the field empty completes a
    /// contactless or no-code one *and* is the deliberate way to spend an
    /// attempt at a door nobody is answering. The photo completes a
    /// leave-at-door order, and after three failed attempts it completes a PIN
    /// one too — which is the whole reason the fallback exists. Nothing is ever
    /// hidden, so a mode this screen has misread still cannot dead-end a
    /// delivery.
    ///
    /// What moves is the **emphasis**, for the two reasons in
    /// `courierPhotoIsTheWayOut`: the customer asked for contactless, or the
    /// PIN has run out and the camera is the only thing left. The first is the
    /// app relaying an instruction rather than making a guess — `handoffMode`
    /// is on the job precisely because "leave it at the door" is something the
    /// customer said and a courier should not have to discover from a refusal.
    @ViewBuilder
    private var handOver: some View {
        VStack(alignment: .leading, spacing: 10) {
            if app.courierPhotoIsTheWayOut {
                photoAction(primary: true)
                pinField
                pinSubmit(primary: false)
            } else {
                pinField
                pinSubmit(primary: true)
                photoAction(primary: false)
            }
        }
    }

    private var pinField: some View {
        CourierCodeField(
            title: "Delivery PIN",
            caption: "If they have one on their order screen",
            code: $deliveryPin)
    }

    /// Live on an empty field, deliberately, and the one rule on this screen
    /// that looks like a bug until you have stood outside a flat where nobody
    /// is answering. There is no PIN to type at that door and there never will
    /// be; submitting nothing is how the courier spends their three attempts
    /// and reaches the photo fallback that exists for exactly this — and on an
    /// order that never wanted a code, it is simply the delivery. A button
    /// greyed out until six digits arrive would be the app refusing to let
    /// somebody finish.
    private func pinSubmit(primary: Bool) -> some View {
        Button {
            Keyboard.dismiss()
            app.courierDelivered(pin: deliveryPin)
        } label: {
            primary ? AnyView(primaryLabel("Delivered"))
                    : AnyView(secondaryLabel("Delivered with a PIN"))
        }
        .buttonStyle(PressableStyle())
        .disabled(busy)
        .opacity(busy ? 0.55 : 1)
    }

    /// Contactless, and the way out of a PIN nobody can produce. When it is the
    /// second of those it says so — the courier did not choose this door and
    /// should know why they are standing in it.
    @ViewBuilder
    private func photoAction(primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if primary {
                Text("Photograph where you left it and we'll complete the delivery. "
                     + "The customer sees the photo.")
                    .explanatory(12)
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Menu {
                // The camera is absent in the Simulator and on a device without
                // a usable one, where offering it presents an empty controller.
                if CameraCaptureView.isAvailable {
                    Button { showCamera = true } label: {
                        Label("Take a photo", systemImage: "camera.fill")
                    }
                }
                Button { showLibrary = true } label: {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                }
            } label: {
                if app.courierProofUploading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(GGColor.onAccent)
                        Text("Sending the photo…")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(GGColor.white))
                } else if primary {
                    primaryLabel("Take a photo instead")
                } else {
                    secondaryLabel("Left it at the door — take a photo")
                }
            }
            .disabled(busy)
            .opacity(busy ? 0.55 : 1)
        }
    }

    // MARK: Pieces

    private func primaryLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(GGColor.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(GGColor.white))
    }

    private func secondaryLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(GGColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(GGColor.ink(0.08)))
    }

    private func courierLeg(icon: String, title: String, detail: String,
                            dim: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(dim ? GGColor.textTertiary : GGColor.textPrimary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(GGColor.ink(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(dim ? GGColor.textSecondary : GGColor.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            }
            Spacer(minLength: 4)
        }
    }
}

// MARK: - Six digits, read at arm's length

/// The one input on the courier's screen, and the whole reason it looks like
/// this: it is filled in one-handed, standing up, often in the sun, by somebody
/// who has just been told six digits across a counter. So the field is a single
/// tap target the width of the card, the digits are mono and large enough to
/// check against what they were told without leaning in, and the number pad is
/// the only keyboard that ever appears.
///
/// It clamps to digits and to six of them rather than validating: a length rule
/// enforced by refusing the seventh keystroke is a rule nobody has to read.
private struct CourierCodeField: View {
    let title: String
    let caption: String
    @Binding var code: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.ggMono(10, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(GGColor.textTertiary)
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }

            TextField("", text: $code, prompt: Text("······")
                .foregroundColor(GGColor.textTertiary))
                .font(.ggMono(30, .bold))
                .tracking(10)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .foregroundStyle(GGColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(GGColor.ink(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(focused ? GGColor.ink(0.30) : GGColor.ink(0.12),
                                  lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture { focused = true }
                .onChange(of: code) { _, typed in
                    let digits = String(typed.filter(\.isNumber).prefix(6))
                    if digits != typed { code = digits }
                }
        }
    }
}

// MARK: - Camera or library, for the drop-off photo

/// The same two sources the partner flow's document tiles offer, and the same
/// reason the *choice* is a menu on the button rather than a dialog on the page:
/// a dialog is anchored to the view that presents it, so one presented from the
/// card would open wherever the card happens to have scrolled to.
private struct ProofPhotoPickers: ViewModifier {
    @Binding var showLibrary: Bool
    @Binding var showCamera: Bool
    @Binding var libraryItem: PhotosPickerItem?
    let onPicked: (Data) -> Void

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                libraryItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    onPicked(data)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView(
                    onCapture: { capture in
                        showCamera = false
                        guard case .photo(let data) = capture else { return }
                        onPicked(data)
                    },
                    onCancel: { showCamera = false },
                    photosOnly: true)
                .ignoresSafeArea()
            }
    }
}

// MARK: - What the work paid (Phase 4 M2)

/// The worker's earnings and the way out to a bank — one card for Driver Mode
/// and Courier Mode both, because the surface is `dispatch`'s and a person who
/// does both jobs has one balance.
///
/// Modelled on the restaurant's earnings card, down to the Stripe sentence,
/// with one thing that card does not need: **a cap, said out loud.** A worker is
/// paid into the same AVAILABLE bucket a card top-up lands in, so the server
/// bounds a withdrawal by what the work actually earned. Without the sentence,
/// somebody with $40 on screen and $12 of it earned would tap "Pay out" and be
/// refused by a number they had no way to predict.
private struct WorkerWalletCard: View {
    @EnvironmentObject var app: AppState

    /// Round amounts rather than a keypad, capped at what can actually leave —
    /// the same call the wallet's top-up made, for the same reason: this is
    /// tapped by somebody who has just parked, and four taps beats a number pad.
    private static let steps = [1_000, 2_500, 5_000]

    private var wallet: WorkerWalletDTO? { app.workerWallet }
    private var currency: String { wallet?.currency ?? "USD" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EARNINGS")
                        .font(.ggMono(10, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(GGColor.textTertiary)
                    Text(WalletStore.money(wallet?.availableMinor ?? 0, currency: currency))
                        .font(.ggMono(26, .bold))
                        .foregroundStyle(GGColor.textPrimary)
                }
                Spacer()
                if let earned = wallet?.lifetimeEarnedMinor, earned > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("EARNED")
                            .font(.ggMono(9, .semibold))
                            .tracking(0.6)
                            .foregroundStyle(GGColor.textTertiary)
                        Text(WalletStore.money(earned, currency: currency))
                            .font(.ggMono(13, .semibold))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                }
            }

            if let wallet {
                if !wallet.payoutsConfigured {
                    Button { app.startWorkerPayoutOnboarding() } label: {
                        payoutCapsule("Set up payouts")
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(app.workerMoneyBusy)
                    Text("Payouts go through Stripe, which asks for your bank details directly.")
                        .explanatory(11)
                        .foregroundStyle(GGColor.textTertiary)
                } else if !wallet.payoutsReady {
                    Text(wallet.payoutsNeedSentence)
                        .font(.system(size: 12))
                        .foregroundStyle(GGColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { app.startWorkerPayoutOnboarding() } label: {
                        payoutCapsule("Finish setting up payouts")
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(app.workerMoneyBusy)
                } else {
                    withdrawal(wallet)
                }

                if !wallet.recent.isEmpty {
                    Divider().background(GGColor.ink(0.1))
                    ForEach(wallet.recent.prefix(4)) { line in
                        HStack {
                            Text(line.memo.isEmpty ? line.kind.capitalized : line.memo)
                                .font(.system(size: 12))
                                .foregroundStyle(GGColor.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(WalletStore.money(line.amountMinor, currency: currency))
                                .font(.ggMono(12, .medium))
                                .foregroundStyle(GGColor.textPrimary)
                        }
                    }
                }
            } else {
                Text("Reading what you've earned…")
                    .explanatory(11)
                    .foregroundStyle(GGColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glass(cornerRadius: 18, tint: GGColor.ink(0.05))
        .task { await app.refreshWorkerWallet() }
    }

    /// The amounts, the cap and the one honest sentence about it.
    @ViewBuilder
    private func withdrawal(_ wallet: WorkerWalletDTO) -> some View {
        let ceiling = wallet.payoutCeilingMinor

        if ceiling < wallet.payoutMinMinor {
            Text("Payouts start at \(WalletStore.money(wallet.payoutMinMinor, currency: currency)).")
                .explanatory(11)
                .foregroundStyle(GGColor.textTertiary)
        } else {
            // At most three: two round amounts and the whole thing. A row of
            // five capsules on a phone card is five tap targets too small to
            // hit with a thumb, which is the only way this is ever tapped.
            HStack(spacing: 8) {
                ForEach(Self.steps.filter { $0 >= wallet.payoutMinMinor && $0 < ceiling }.suffix(2),
                        id: \.self) { amount in
                    amountButton(WalletStore.money(amount, currency: currency), amount)
                }
                amountButton("All · " + WalletStore.money(ceiling, currency: currency), ceiling)
            }
        }

        // Said whenever the two numbers differ, and only then. The wallet on
        // this screen can hold money that arrived some other way — a top-up, a
        // refund — and this surface will not send that to a bank.
        if wallet.cappedBelowBalance {
            Text("You can withdraw \(WalletStore.money(wallet.withdrawableMinor, currency: currency)) "
                 + "— withdrawals are limited to what you've earned working.")
                .explanatory(11)
                .foregroundStyle(GGColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func amountButton(_ title: String, _ amountMinor: Int) -> some View {
        Button {
            app.requestWorkerPayout(amountMinor)
        } label: {
            Text(title)
                .font(.ggMono(12, .semibold))
                .foregroundStyle(GGColor.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(GGColor.white))
        }
        .buttonStyle(PressableStyle())
        .disabled(app.workerMoneyBusy)
        .opacity(app.workerMoneyBusy ? 0.5 : 1)
    }

    private func payoutCapsule(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(GGColor.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Capsule().fill(GGColor.white))
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

// MARK: - The price on the table (driver-side negotiation)

/// What "not at that price" looks like while the rider decides. One card per
/// negotiation, because a driver has at most one: their own pending price, and
/// — if the rider comes back — the rider's number with a take-it button.
private struct DriverNegotiationCard: View {
    @EnvironmentObject var app: AppState
    let ride: RideDTO

    /// The driver's own live price on this ride.
    private var myOffer: RideOfferDTO? {
        ride.liveOffers.first { $0.party == "DRIVER" }
    }

    /// The rider's counter, addressed to this driver.
    private var riderOffer: RideOfferDTO? {
        ride.liveOffers.first { $0.party == "RIDER" }
    }

    private func money(_ minor: Int) -> String {
        WalletStore.money(minor, currency: ride.currency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(riderOffer == nil ? "Your price is on the table"
                                        : "The rider came back",
                      systemImage: riderOffer == nil ? "hourglass" : "arrow.uturn.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer()
                Button {
                    app.dismissDriverNegotiation()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GGColor.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(GGColor.ink(0.08)))
                }
                .buttonStyle(.plain)
            }

            Text("\(ride.pickupLabel) → \(ride.dropoffLabel)")
                .font(.system(size: 12))
                .foregroundStyle(GGColor.textSecondary)
                .lineLimit(2)

            if let mine = myOffer {
                HStack {
                    Text("You asked \(money(mine.amountMinor))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Spacer()
                    Text("rider asked \(money(ride.offeredFareMinor))")
                        .font(.ggMono(12, .medium))
                        .foregroundStyle(GGColor.textTertiary)
                }
            }

            if let theirs = riderOffer {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ride.otherPartyName ?? "The rider")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                        Text("offers \(money(theirs.amountMinor))")
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        app.takeRiderOffer(theirs)
                    } label: {
                        Text("Take it")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(GGColor.onAccent)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Capsule().fill(GGColor.white))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(app.driverRideBusy)
                    .opacity(app.driverRideBusy ? 0.5 : 1)
                }
                .padding(10)
                .glass(cornerRadius: 14, fillOpacity: 0.05, borderOpacity: 0.08)
            } else {
                Text("If the rider takes your price, the trip starts here. If they counter, you'll see their number.")
                    .explanatory(12)
                    .foregroundStyle(GGColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 20, fillOpacity: 0.05, borderOpacity: 0.08)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Incoming request card

private struct PartnerOfferCard: View {
    @EnvironmentObject var app: AppState
    let job: PartnerJob

    /// The counteroffer field, open or not. Local state, reset with the card —
    /// a price typed for one trip must never survive into the next.
    @State private var countering = false
    @State private var counterText = ""
    @FocusState private var counterFocused: Bool

    /// A real ride can be countered; a delivery or a demo job cannot.
    private var canCounter: Bool { job.role == .driver && job.rideId != nil }

    private var counterAmountMinor: Int {
        Int((Double(counterText.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100)
    }

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
                metric(icon: "location.north.line.fill", value: job.distanceLabel, label: "Trip")
                if job.minutes > 0 {
                    metric(icon: "clock.fill", value: "\(job.minutes) min", label: "Est. time")
                }
                metric(icon: "person.fill", value: job.customerName, label: job.role == .driver ? "Rider" : "Customer")
            }

            PartnerRouteView(job: job, progress: 0)

            if countering {
                counterField
            }

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

            // The negotiation, driver-side (Phase 3 M3): "not at that price".
            // Below Accept/Decline because most trips are taken as asked, and a
            // counter is a decline of the dispatch offer — the server treats it
            // that way, so the button says what it does.
            if canCounter && !countering {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.ggSnappy) { countering = true }
                    counterFocused = true
                } label: {
                    Text("Offer another price")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(18)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.3), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var counterField: some View {
        HStack(spacing: 10) {
            Text("$")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
            TextField("Your price", text: $counterText)
                .font(.ggMono(16, .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .keyboardType(.decimalPad)
                .focused($counterFocused)
            Button {
                app.counterDispatchOffer(amountMinor: counterAmountMinor)
            } label: {
                Text("Send")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(counterAmountMinor <= 0 || app.driverRideBusy)
            .opacity(counterAmountMinor <= 0 || app.driverRideBusy ? 0.45 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.08)
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

            // A real trip advances by the driver saying so — these buttons are
            // the state machine (arrived → rider aboard → complete), and the
            // server is the judge of each. The demo keeps its passive line.
            if let ride = app.driverRide, ride.id == job.rideId {
                tripActions(ride)
            } else {
                // Demo action — the simulation advances itself.
                Text(headingToPickup
                     ? "Navigating to \(job.pickupName)…"
                     : "En route to \(job.dropoffName)…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(GGColor.ink(0.08)))
            }
        }
        .padding(18)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.3), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// One primary action per state, because a driver reads this at a red
    /// light: CONFIRMED → "I've arrived", ARRIVING → "start trip",
    /// IN_TRIP → "Complete trip". Cancelling stays available until the rider
    /// is in the car — after that, the only way out is to end the trip.
    @ViewBuilder
    private func tripActions(_ ride: RideDTO) -> some View {
        VStack(spacing: 10) {
            switch ride.state {
            case "CONFIRMED":
                primaryAction("I've arrived at the pickup", icon: "mappin.and.ellipse") {
                    app.driverArrived()
                }
                secondaryAction("Rider's already aboard — start the trip") {
                    app.driverStartTrip()
                }
            case "ARRIVING":
                primaryAction("Rider aboard — start the trip", icon: "figure.wave") {
                    app.driverStartTrip()
                }
            case "IN_TRIP":
                primaryAction("Complete trip", icon: "flag.checkered") {
                    app.driverCompleteTrip()
                }
            default:
                EmptyView()
            }
            if ride.state == "CONFIRMED" || ride.state == "ARRIVING" {
                secondaryAction("Cancel this trip") {
                    app.driverCancelTrip()
                }
            }
        }
    }

    private func primaryAction(_ title: String, icon: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GGColor.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(GGColor.white))
        }
        .buttonStyle(PressableStyle())
        .disabled(app.driverRideBusy)
        .opacity(app.driverRideBusy ? 0.5 : 1)
    }

    private func secondaryAction(_ title: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(app.driverRideBusy)
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
