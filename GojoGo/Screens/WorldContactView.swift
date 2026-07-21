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
        case documents = "Documents"
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
        .background(IMColor.bg.ignoresSafeArea())
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
                    .foregroundStyle(IMColor.label)
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
                .foregroundStyle(IMColor.label)
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
                .foregroundStyle(IMColor.label)
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
                            .foregroundStyle(tab == t ? IMColor.label : IMColor.secondary)
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
        case .backgrounds:
            backgroundsGrid
        case .links:
            linksSection
        case .documents:
            documentsSection
        }
    }

    // MARK: Backgrounds

    private var backgroundsGrid: some View {
        let current = convo?.background ?? .none
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                         spacing: 18) {
            ForEach(WorldChatBackground.allCases) { bg in
                Button {
                    app.setWorldBackground(bg)
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            if bg == .none {
                                Circle().fill(IMColor.chrome)
                                    .overlay(
                                        Image(systemName: "circle.slash")
                                            .font(.system(size: 22))
                                            .foregroundStyle(IMColor.secondary)
                                    )
                            } else {
                                Circle().fill(
                                    LinearGradient(colors: bg.gradient,
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                        }
                        .frame(width: 84, height: 84)
                        .overlay(
                            Circle().strokeBorder(
                                current == bg ? IMColor.blue : Color.clear, lineWidth: 3)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            if current == bg {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, IMColor.blue)
                                    .font(.system(size: 22))
                                    .offset(x: 2, y: 2)
                            }
                        }

                        Text(bg.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(current == bg ? IMColor.label : IMColor.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    // MARK: Links

    private var linksSection: some View {
        VStack(spacing: 12) {
            linkCard(icon: "video.fill", tint: Color(red: 0.2, green: 0.78, blue: 0.35),
                     title: "FaceTime", subtitle: "Link")
            ForEach(sharedLinks, id: \.self) { url in
                linkCard(icon: "link", tint: IMColor.blue, title: url, subtitle: "Shared link")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var sharedLinks: [String] {
        (convo?.messages ?? []).flatMap { msg -> [String] in
            guard msg.kind == .text else { return [] }
            return msg.text
                .split(separator: " ")
                .map(String.init)
                .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") || $0.hasPrefix("www.") }
        }
    }

    private func linkCard(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint)
                .frame(width: 54, height: 54)
                .overlay(Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(IMColor.label)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(IMColor.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IMColor.chrome))
    }

    // MARK: Documents

    private var documentsSection: some View {
        let docs = (convo?.messages ?? []).filter { $0.kind == .file }
        return Group {
            if docs.isEmpty {
                emptyTab("documents")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(docs) { doc in
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(IMColor.chrome)
                                .frame(height: 120)
                                .overlay(
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(IMColor.blue)
                                )
                            Text(doc.fileName ?? "Document")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(IMColor.label)
                                .lineLimit(1)
                            Text(doc.fileMeta ?? "File")
                                .font(.system(size: 11))
                                .foregroundStyle(IMColor.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
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
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(true)

            HStack(spacing: 6) {
                Text("🚗")
                Text("\(contact?.distanceLabel ?? "23 km") · \(contact?.etaLabel ?? "36 min")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(IMColor.blue))
            .padding(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact?.city ?? "Nearby")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(IMColor.label)
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
                    .foregroundStyle(IMColor.label)
            }
            Spacer()
            Image(systemName: "phone.fill")
                .font(.system(size: 18))
                .foregroundStyle(IMColor.label)
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
                .foregroundStyle(IMColor.label)
            Spacer()
            HStack(spacing: 6) {
                Text("P")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(IMColor.label)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(IMColor.blue))
                Text("Personal")
                    .font(.system(size: 16))
                    .foregroundStyle(IMColor.label)
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
        return Group {
            if chatPhotos.isEmpty {
                emptyTab("Photos")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 3),
                                   GridItem(.flexible(), spacing: 3),
                                   GridItem(.flexible(), spacing: 3)], spacing: 3) {
                    ForEach(Array(chatPhotos.enumerated()), id: \.offset) { _, data in
                        MediaImage(data: data, cornerRadius: 0)
                            .frame(minHeight: 110)
                            .clipped()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
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
