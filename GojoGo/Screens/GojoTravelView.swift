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

    var body: some View {
        ZStack(alignment: .bottom) {
            TravelMapView(
                viewport: $viewport,
                pickup: app.travelPickup,
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
                    colors: [Color.black.opacity(0.72), Color.black.opacity(0)],
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
                    app.cancelTravelRide()
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
                locationLine(dot: .white, title: "Pickup",
                             value: app.travelPickup.name)
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
                }
            }
            .padding(14)
            .glass(cornerRadius: 16, tint: Color.black.opacity(0.35))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(app.filteredTravelPlaces.enumerated()), id: \.element.id) { i, place in
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            searchFocused = false
                            app.selectTravelDestination(place)
                        } label: {
                            placeRow(place)
                        }
                        .buttonStyle(PressableStyle())
                        if i < app.filteredTravelPlaces.count - 1 {
                            Divider().background(GGColor.ink(0.08))
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            .glass(cornerRadius: 16, tint: Color.black.opacity(0.35))
        }
        .padding(16)
        .glass(cornerRadius: 24, tint: Color.black.opacity(0.52), floating: true)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { searchFocused = true }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                app.confirmTravelRide()
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

            Text("Finding your driver")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(GGColor.textPrimary)
            Text("Matching you with a nearby GojoTravel driver…")
                .explanatory(14)
                .foregroundStyle(GGColor.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                app.cancelTravelRide()
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
                        Text(driver.plate)
                            .font(.ggMono(11, .semibold))
                            .foregroundStyle(GGColor.textSecondary)
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

            if app.travelPhase == .enRoute || app.travelPhase == .inTrip {
                Button {
                    app.cancelTravelRide()
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
                        app.travelRating = star
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
