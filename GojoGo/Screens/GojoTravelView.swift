import SwiftUI
import CoreLocation
import MapboxMaps

struct GojoTravelView: View {
    @EnvironmentObject var app: AppState
    @State private var viewport: Viewport = TravelCamera.fit(
        pickup: SampleData.travelDefaultCenter, dropoff: nil
    )
    @State private var pulse = false
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var scheme

    /// The fade the header sits on. It exists to keep dark chrome legible over
    /// whatever the map is showing — so in light mode, where the wordmark and
    /// the Drive chip are near-black, it has to fade from white. A black band
    /// under black text was the light-mode bug: the chip read as a dark pill
    /// with dark writing on it.
    private var headerScrim: Color {
        scheme == .light ? Color.white : Color.black
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TravelMapView(
                viewport: $viewport,
                pickup: mapPickup,
                dropoff: app.travelDropoff,
                driver: app.travelDriver,
                showRoute: app.travelDropoff != nil
                    && [.choosingRide, .matching, .enRoute, .inTrip, .completed]
                        .contains(app.travelPhase)
            )
            // Don't let the map eat taps meant for the ride sheet.
            .allowsHitTesting(app.travelPhase == .home || app.travelPhase == .enRoute || app.travelPhase == .inTrip)

            // Top fade + brand chrome
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [headerScrim.opacity(0.72), headerScrim.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 120)
                .allowsHitTesting(false)
                Spacer()
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }

            bottomChrome
                .padding(.horizontal, 16)
                .padding(.bottom, tabBarInset - 12)
        }
        .onAppear {
            MapboxOptions.accessToken = MapboxConfig.accessToken
            refreshCamera(animated: false)
            // Ask on arrival rather than when the rider taps "Where to?" — the
            // permission sheet in the middle of booking a car is the worst
            // moment for it, and the map is wrong until the fix lands anyway.
            app.refreshTravelPickup()
        }
        .onChange(of: app.travelPickup.latitude) { _, _ in
            // The first fix moves the pin off the placeholder; fly there unless
            // the camera is busy following a car.
            guard app.travelPhase == .home || app.travelPhase == .searching else { return }
            refreshCamera(animated: true)
        }
        .onChange(of: app.travelPhase) { _, _ in refreshCamera(animated: true) }
        .onChange(of: app.travelDropoff?.id) { _, _ in refreshCamera(animated: true) }
        .onChange(of: app.travelDriver?.id) { _, _ in refreshCamera(animated: true) }
        .onChange(of: app.travelDriver?.latitude) { _, _ in
            // Follow the moving car without a heavy camera animation each tick.
            guard app.travelPhase == .enRoute || app.travelPhase == .inTrip,
                  let driver = app.travelDriver else { return }
            viewport = TravelCamera.follow(driver: driver)
        }
        // Phase 3 M5. Both present from this screen and nowhere else — one
        // owner per AppState-driven sheet, or it silently refuses to present.
        .task { await app.loadVerificationInvites() }
        .sheet(isPresented: $app.confirmingSos) {
            SosSheet().environmentObject(app)
        }
        .sheet(item: $app.openVerification) { invite in
            VehicleVerificationSheet(invite: invite).environmentObject(app)
        }
    }

    /// The pickup pin, but only once it means something. Before the first fix
    /// the coordinate is a placeholder, and a labelled "Pickup" pin sitting on
    /// a street the rider has never seen is worse than no pin at all. From the
    /// moment a ride is being priced the pickup is whatever was booked, so it
    /// is always shown then.
    private var mapPickup: TravelPlace? {
        if app.travelPickupState.isReal { return app.travelPickup }
        return app.travelPhase == .home || app.travelPhase == .searching ? nil : app.travelPickup
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GOJOTRAVEL")
                    .font(.ggMono(12, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Wordmark(size: 22, trailing: "travel")
            }
            Spacer()
            if app.travelPhase != .home && app.travelPhase != .completed {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    app.cancelRide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .glassCapsule(tint: Color.black.opacity(0.45), interactive: false, dense: true)
                }
                .buttonStyle(PressableStyle())
            } else {
                // Sit left of the Mapbox compass so it isn't covered.
                PartnerHeaderButton(role: .driver)
                    .padding(.trailing, 46)
            }
        }
    }

    // MARK: Bottom chrome by phase

    @ViewBuilder
    private var bottomChrome: some View {
        switch app.travelPhase {
        case .home:
            homeSheet
        case .searching:
            searchSheet
        case .choosingRide:
            rideSheet
        case .matching:
            matchingSheet
        case .enRoute:
            driverSheet(title: "Driver on the way", subtitle: "Heading to your pickup")
        case .inTrip:
            driverSheet(title: "On the way", subtitle: destinationLine)
        case .completed:
            completedSheet
        }
    }

    private var destinationLine: String {
        if let d = app.travelDropoff { return "To \(d.name)" }
        return "Enjoy the ride"
    }

    // MARK: Home

    private var homeSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Phase 3 M5. Above "Where to?" rather than in a notification
            // centre, because this is the one screen the person who can answer
            // it is already looking at — and it disappears the moment they do.
            if let invite = app.verificationInvites.first {
                VerificationInviteCard(invite: invite)
                    .padding(.bottom, 2)
            }

            pickupStatusLine

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.openTravelSearch()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                    Text("Where to?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GGColor.onAccent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(GGColor.white))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            ForEach(Array(app.travelRecent.prefix(2).enumerated()), id: \.element.id) { i, place in
                if i == 0 {
                    Divider().background(GGColor.ink(0.10))
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    app.selectTravelDestination(place)
                    Task { await app.quoteRide(to: place) }
                } label: {
                    placeRowCompact(place)
                }
                .buttonStyle(PressableStyle())
                if i < min(1, app.travelRecent.count - 1) {
                    Divider().background(GGColor.ink(0.10))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glass(cornerRadius: 22, tint: Color.black.opacity(0.52), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Where the app thinks you are, before you ask it for a car. Quiet when
    /// the fix is real, and the only thing worth tapping when it isn't.
    private var pickupStatusLine: some View {
        Button {
            if app.travelPickupState == .denied {
                openLocationSettings()
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.refreshTravelPickup(force: true)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: app.travelPickupState.isReal
                      ? "location.fill" : "location.slash.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(app.travelPickupState.isReal
                                     ? GGColor.textSecondary : GGColor.textTertiary)
                Text(app.travelPickupLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GGColor.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if app.travelPickupState == .locating {
                    ProgressView().controlSize(.mini).tint(GGColor.textTertiary)
                }
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(app.travelPickupState == .locating)
    }

    // MARK: Search

    private var searchSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    app.closeTravelSearch()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .glassCapsule(tint: Color.black.opacity(0.35), interactive: false, dense: true)
                }
                .buttonStyle(PressableStyle())

                Text("Choose destination")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                // Tappable, because the two states worth acting on — location
                // refused and no fix — are both fixed by trying again, and this
                // row is where somebody looks when the pickup looks wrong.
                Button {
                    if app.travelPickupState == .denied {
                        openLocationSettings()
                    } else {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.refreshTravelPickup(force: true)
                    }
                } label: {
                    HStack(spacing: 10) {
                        locationLine(dot: pickupDotColor, title: "Pickup",
                                     value: app.travelPickupLabel)
                        Spacer(minLength: 0)
                        if app.travelPickupState == .locating {
                            ProgressView().controlSize(.mini).tint(GGColor.textSecondary)
                        } else if !app.travelPickupState.isReal {
                            Image(systemName: "location.slash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GGColor.textSecondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())

                Rectangle()
                    .fill(GGColor.ink(0.12))
                    .frame(width: 1, height: 10)
                    .padding(.leading, 5)
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(GGColor.white, lineWidth: 2)
                        .frame(width: 12, height: 12)
                    TextField("Where to?", text: $app.travelQuery)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GGColor.textPrimary)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .onChange(of: app.travelQuery) { _, text in
                            app.travelQueryChanged(text)
                        }
                    if app.travelSearching {
                        ProgressView().controlSize(.mini).tint(GGColor.textSecondary)
                    } else if !app.travelQuery.isEmpty {
                        Button {
                            app.travelQuery = ""
                            app.travelQueryChanged("")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(GGColor.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .glass(cornerRadius: 16, tint: Color.black.opacity(0.35))

            suggestionList
        }
        .padding(16)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.52), floating: true)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { searchFocused = true }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var pickupDotColor: Color {
        app.travelPickupState.isReal ? .white : GGColor.textTertiary
    }

    @ViewBuilder
    private var suggestionList: some View {
        let places = app.filteredTravelPlaces
        Group {
            if places.isEmpty {
                // Three different silences, and telling them apart is the
                // difference between "keep typing" and "that place isn't there".
                VStack(spacing: 6) {
                    Image(systemName: app.travelSearchIsEmpty ? "mappin.slash" : "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(GGColor.textTertiary)
                    Text(emptyStateText)
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(places.enumerated()), id: \.element.id) { i, place in
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                searchFocused = false
                                app.selectTravelDestination(place)
                                Task { await app.quoteRide(to: place) }
                            } label: {
                                placeRow(place)
                            }
                            .buttonStyle(PressableStyle())
                            if i < places.count - 1 {
                                Divider().background(GGColor.ink(0.08))
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .glass(cornerRadius: 16, tint: Color.black.opacity(0.35))
    }

    private var emptyStateText: String {
        if app.travelSearchIsEmpty { return "No places match “\(app.travelQuery)”" }
        if app.travelQuery.isEmpty { return "Search a place, address, or landmark" }
        return "Keep typing…"
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Ride options

    private var rideSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    app.backFromRideChoice()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(width: 44, height: 44)
                        .glassCapsule(tint: Color.black.opacity(0.35), interactive: false, dense: true)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose a ride")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    if let drop = app.travelDropoff {
                        Text("To \(drop.name)")
                            .font(.system(size: 12))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                ForEach(app.travelRideOptions) { option in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.ggSnappy) { app.selectedRide = option }
                    } label: {
                        rideRow(option, selected: app.selectedRide?.id == option.id)
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                app.requestRide()
            } label: {
                Text(confirmLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(GGColor.white))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(app.selectedRide == nil)
            .opacity(app.selectedRide == nil ? 0.45 : 1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.52), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var confirmLabel: String {
        if let ride = app.selectedRide {
            return "Confirm \(ride.name) · \(ride.price)"
        }
        return "Confirm ride"
    }

    // MARK: Matching / driver / complete

    private var matchingSheet: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(GGColor.ink(0.12), lineWidth: 2)
                    .frame(width: 72, height: 72)
                    .scaleEffect(pulse ? 1.35 : 1)
                    .opacity(pulse ? 0 : 0.8)
                Circle()
                    .fill(GGColor.white)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "car.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(GGColor.onAccent)
                    )
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }

            Text(counterOffers.isEmpty ? "Finding your driver" : "Drivers have replied")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text(counterOffers.isEmpty
                 ? "Matching you with a nearby GojoTravel driver…"
                 : "They'd like a different fare. Take one, or wait for somebody at your price.")
                .explanatory(14)
                .foregroundStyle(GGColor.textSecondary)
                .multilineTextAlignment(.center)

            // The counteroffers — the one thing a ride has that a delivery order
            // doesn't. Each is one driver's private answer, so they stack rather
            // than merging into a single "best price": picking is the rider's,
            // and an auction is not what this is.
            if !counterOffers.isEmpty {
                VStack(spacing: 8) {
                    ForEach(counterOffers) { offer in
                        counterRow(offer)
                    }
                }
                .padding(.horizontal, 4)
            }

            Button {
                app.cancelRide()
            } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .glassCapsule(tint: Color.black.opacity(0.35), interactive: false, dense: true)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.52), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func driverSheet(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(GGColor.textSecondary)
                }
                Spacer()
                if let driver = app.travelDriver {
                    Text("\(driver.etaMinutes) min")
                        .font(.ggMono(13, .semibold))
                        .foregroundStyle(GGColor.onAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(GGColor.white))
                }
            }

            if let driver = app.travelDriver {
                HStack(spacing: 12) {
                    UserAvatar(size: 48, letter: String(driver.name.prefix(1)), imageURL: driver.avatarURL)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(driver.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text(String(format: "%.2f · %d trips", driver.rating, driver.trips))
                                .font(.ggMono(11, .medium))
                        }
                        .foregroundStyle(GGColor.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(driver.vehicle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(GGColor.textPrimary)
                        HStack(spacing: 4) {
                            // Earned by other passengers checking this exact car
                            // (Phase 3 M5). Beside the plate because the plate
                            // is what it is a claim about.
                            if app.ride?.vehicleVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(GGColor.accent)
                            }
                            Text(driver.plate)
                                .font(.ggMono(11, .semibold))
                                .foregroundStyle(GGColor.textSecondary)
                        }
                    }

                    // Sits on the driver, not down with Share/SOS: it is a way
                    // to reach *this person*, and the safety bar is for the
                    // moments when reaching them is not what you want.
                    if app.canMessageRideDriver {
                        Button {
                            app.messageRideDriver()
                        } label: {
                            Image(systemName: "message.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(GGColor.textPrimary)
                                .frame(width: 38, height: 38)
                                .glass(cornerRadius: 19)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Message \(driver.name)")
                    }
                }
                .padding(14)
                .glass(cornerRadius: 18)
            }

            if let ride = app.selectedRide {
                HStack {
                    Label(ride.name, systemImage: ride.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                    Spacer()
                    Text(ride.price)
                        .font(.ggMono(13, .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                }
            }

            // Phase 3 M5: share and SOS sit *above* Cancel, because the person
            // who needs them is not looking for the cancel button.
            if app.travelPhase == .enRoute || app.travelPhase == .inTrip {
                TripSafetyBar()
                TripShareStatus()
            }

            if app.travelPhase == .enRoute || app.travelPhase == .inTrip {
                Button {
                    app.cancelRide()
                } label: {
                    Text("Cancel ride")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glass(cornerRadius: 16)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(18)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.52), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var completedSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(GGColor.white)

            Text("You've arrived")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)

            if let drop = app.travelDropoff {
                Text(drop.name)
                    .explanatory(14)
                    .foregroundStyle(GGColor.textSecondary)
            }

            if let ride = app.selectedRide {
                Text(ride.price)
                    .font(.ggMono(18, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
            }

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.rateRide(star)
                    } label: {
                        Image(systemName: star <= app.travelRating ? "star.fill" : "star")
                            .font(.system(size: 26))
                            .foregroundStyle(GGColor.white.opacity(star <= app.travelRating ? 1 : 0.28))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.vertical, 4)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                app.finishTravelTrip()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.52), floating: true)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Live counteroffers, freshest first.
    private var counterOffers: [RideOfferDTO] {
        app.ride?.liveOffers.filter { $0.party == "DRIVER" } ?? []
    }

    @ViewBuilder
    private func counterRow(_ offer: RideOfferDTO) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(GGColor.ink(0.1))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(offer.driverName ?? "A driver")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text("asks \(WalletStore.money(offer.amountMinor, currency: app.ride?.currency ?? "USD"))")
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                app.declineRideOffer(offer)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(GGColor.ink(0.08)))
            }
            .buttonStyle(.plain)
            Button {
                app.acceptRideOffer(offer)
            } label: {
                Text("Accept")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GGColor.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(GGColor.white))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(10)
        .glass(cornerRadius: 16, fillOpacity: 0.05, borderOpacity: 0.08)
    }

    // MARK: Rows

    private func placeRow(_ place: TravelPlace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: place.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(GGColor.ink(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(place.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func placeRowCompact(_ place: TravelPlace) -> some View {
        HStack(spacing: 10) {
            Image(systemName: place.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GGColor.textSecondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(place.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func rideRow(_ option: RideOption, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: option.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(selected ? GGColor.onAccent : GGColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(selected ? GGColor.white : GGColor.ink(0.08))
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(option.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text("· \(option.capacity)")
                        .font(.ggMono(11, .medium))
                        .foregroundStyle(GGColor.textTertiary)
                }
                .foregroundStyle(GGColor.textPrimary)
                Text(option.tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(GGColor.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(option.price)
                    .font(.ggMono(14, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text("\(option.etaMinutes) min")
                    .font(.system(size: 11))
                    .foregroundStyle(GGColor.textTertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? GGColor.ink(0.12) : GGColor.ink(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? GGColor.ink(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func locationLine(dot: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.ggMono(9, .semibold))
                    .foregroundStyle(GGColor.textTertiary)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GGColor.textPrimary)
            }
        }
    }

    // MARK: Camera

    private func refreshCamera(animated: Bool) {
        let next: Viewport = {
            switch app.travelPhase {
            case .enRoute, .inTrip:
                if let driver = app.travelDriver {
                    return TravelCamera.follow(driver: driver)
                }
                fallthrough
            default:
                return TravelCamera.fit(pickup: app.travelPickup, dropoff: app.travelDropoff)
            }
        }()
        if animated {
            withViewportAnimation(.easeInOut(duration: 0.65)) { viewport = next }
        } else {
            viewport = next
        }
    }
}
