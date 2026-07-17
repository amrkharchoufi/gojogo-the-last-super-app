import SwiftUI
import MapKit

/// iMessage-style contact / info sheet for a My World conversation.
struct WorldContactView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: ContactTab = .info

    enum ContactTab: String, CaseIterable, Identifiable {
        case info = "Info"
        case backgrounds = "Backgrounds"
        case photos = "Photos"
        case links = "Links"
        case locations = "Locations"
        var id: String { rawValue }
    }

    private var contact: WorldContact? { app.selectedWorldContact }
    private var convo: WorldConversation? { app.selectedWorldConversation }

    private var displayName: String {
        contact?.name ?? convo?.title ?? "Contact"
    }

    private var avatarURL: String? {
        contact?.avatarURL ?? convo?.avatarURL
    }

    private var gradient: [Color] {
        contact?.avatarGradient ?? convo?.avatarGradient ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    hero
                    quickActions
                    tabPicker
                    tabBody
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var navBar: some View {
        HStack {
            Button { app.closeWorldContact() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(IMColor.blue)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button { } label: {
                Text("Edit")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(IMColor.chrome))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            UserAvatar(
                size: 92,
                gradient: gradient,
                letter: String(displayName.prefix(1)),
                imageURL: avatarURL
            )
            Text(displayName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let user = contact?.username {
                Text("@\(user)")
                    .font(.system(size: 15))
                    .foregroundStyle(IMColor.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var quickActions: some View {
        HStack(spacing: 28) {
            actionButton("phone.fill", "call")
            actionButton("video.fill", "video")
            actionButton("envelope.fill", "mail")
        }
        .padding(.top, 4)
    }

    private func actionButton(_ icon: String, _ label: String) -> some View {
        Button { } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(IMColor.chrome))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ContactTab.allCases) { t in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { tab = t }
                    } label: {
                        Text(t.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tab == t ? .white : IMColor.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(tab == t ? IMColor.chrome : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch tab {
        case .info:
            infoSection
        case .photos:
            photosGrid
        case .locations:
            locationOnly
        case .backgrounds, .links:
            emptyTab(tab.rawValue)
        }
    }

    private var infoSection: some View {
        VStack(spacing: 12) {
            locationCard
            if app.worldSharingLocation {
                Button {
                    withAnimation { app.worldSharingLocation = false }
                } label: {
                    Text("Stop Sharing My Location")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(IMColor.chrome)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }

            if let phone = contact?.phone {
                phoneCard(phone)
            }

            conversationLineCard
        }
    }

    private var locationCard: some View {
        let lat = contact?.latitude ?? 34.0531
        let lon = contact?.longitude ?? -6.7985
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )

        return ZStack(alignment: .topLeading) {
            Map(initialPosition: .region(region)) {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                    UserAvatar(
                        size: 28,
                        gradient: gradient,
                        letter: String(displayName.prefix(1)),
                        imageURL: avatarURL
                    )
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(radius: 4)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .colorScheme(.dark)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(true)

            HStack(spacing: 6) {
                Text("🚗")
                Text("\(contact?.distanceLabel ?? "23 km") · \(contact?.etaLabel ?? "36 min")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(IMColor.blue))
            .padding(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact?.city ?? "Nearby")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Live")
                    .font(.system(size: 13))
                    .foregroundStyle(IMColor.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(.horizontal, 16)
    }

    private func phoneCard(_ phone: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("mobile")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IMColor.secondary)
                    .textCase(.uppercase)
                Text(phone)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "phone.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(IMColor.chrome)
        )
        .padding(.horizontal, 16)
    }

    private var conversationLineCard: some View {
        HStack {
            Text("Conversation Line")
                .font(.system(size: 16))
                .foregroundStyle(.white)
            Spacer()
            HStack(spacing: 6) {
                Text("P")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(IMColor.blue))
                Text("Personal")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IMColor.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(IMColor.chrome)
        )
        .padding(.horizontal, 16)
    }

    private var locationOnly: some View {
        locationCard
    }

    private var photosGrid: some View {
        let chatPhotos = app.worldChatPhotos(for: convo)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 3),
                                   GridItem(.flexible(), spacing: 3),
                                   GridItem(.flexible(), spacing: 3)], spacing: 3) {
            ForEach(Array(chatPhotos.enumerated()), id: \.offset) { _, data in
                MediaImage(data: data, cornerRadius: 0)
                    .frame(minHeight: 110)
                    .clipped()
            }
            ForEach(0..<max(0, 9 - chatPhotos.count), id: \.self) { i in
                MediaImage(url: "https://picsum.photos/seed/mw-photo-\(i)/400/400", cornerRadius: 0)
                    .frame(minHeight: 110)
                    .clipped()
            }
        }
        .padding(.horizontal, 16)
    }

    private func emptyTab(_ name: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(IMColor.secondary)
            Text("No \(name.lowercased()) yet")
                .font(.system(size: 15))
                .foregroundStyle(IMColor.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
