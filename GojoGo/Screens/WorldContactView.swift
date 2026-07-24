import SwiftUI
import MapKit
import UIKit

/// Contact / conversation info page for a My World thread.
///
/// Everything here reads from the real thread: the person comes from the live
/// conversation's participant record (plus their public GojoGo profile when they
/// have a handle), and every tab is built from the messages that were actually
/// exchanged. The settings rows write through to the backend where the backend
/// owns them (pin, delete) and to device preferences where it doesn't (mute).
struct WorldContactView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: ContactTab = .info
    @State private var confirmingDelete = false

    enum ContactTab: String, CaseIterable, Identifiable {
        case info = "Info"
        case backgrounds = "Backgrounds"
        case photos = "Photos"
        case links = "Links"
        case documents = "Documents"
        case locations = "Locations"
        var id: String { rawValue }
    }

    private var convo: WorldConversation? { app.selectedWorldConversation }
    private var contact: WorldContact? { app.selectedWorldContact }

    /// The resolved person/group; nil until `openWorldContact` has assembled it.
    private var profile: WorldContactProfile? {
        guard let convo, app.worldContactProfile?.conversationID == convo.id else { return nil }
        return app.worldContactProfile
    }

    private var displayName: String {
        profile?.name ?? contact?.name ?? convo?.title ?? "Contact"
    }

    private var avatarURL: String? {
        profile?.avatarURL ?? contact?.avatarURL ?? convo?.avatarURL
    }

    private var gradient: [Color] {
        contact?.avatarGradient ?? convo?.avatarGradient ?? []
    }

    private var handle: String? { profile?.handle ?? contact?.username.nilIfBlank }
    private var phone: String? { profile?.phone ?? contact?.phone.nilIfBlank }
    private var isGroup: Bool { convo?.isGroup ?? false }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    hero
                    quickActions
                    tabPicker
                    tabBody
                }
                .padding(.bottom, 48)
            }
        }
        .background {
            IMColor.bg.ignoresSafeArea()
            RadialGradient(
                colors: [IMColor.blue.opacity(0.14), .clear],
                center: .top, startRadius: 20, endRadius: 320)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .confirmationDialog("Delete this conversation?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(isGroup ? "Leave Conversation" : "Delete Conversation", role: .destructive) {
                if let id = convo?.id { app.deleteWorldConversation(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isGroup
                 ? "You'll stop receiving messages from this group."
                 : "The conversation and its messages are removed from your My World.")
        }
    }

    private var navBar: some View {
        HStack {
            Button { app.closeWorldContact() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(IMColor.blue)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glass(cornerRadius: 20, interactive: true)

            Spacer()

            if let handle {
                Button {
                    app.closeWorldContact()
                    app.openUserProfile(handle: handle, name: displayName,
                                        avatarURL: avatarURL, avatarGradient: gradient)
                } label: {
                    Text("Profile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(IMColor.label)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .glassCapsule(interactive: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Group {
                if isGroup {
                    Circle()
                        .fill(IMColor.chrome.opacity(0.7))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(IMColor.label.opacity(0.8))
                        )
                        .overlay(Circle().strokeBorder(IMColor.label.opacity(0.1), lineWidth: 0.5))
                } else {
                    UserAvatar(size: 100, gradient: gradient,
                               letter: String(displayName.prefix(1)), imageURL: avatarURL)
                        .overlay(Circle().strokeBorder(IMColor.label.opacity(0.12), lineWidth: 1))
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
                }
            }

            Text(displayName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(IMColor.label)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if isGroup {
                Text("\(max(profile?.members.count ?? 0, 2)) people")
                    .font(.system(size: 15))
                    .foregroundStyle(IMColor.secondary)
            } else if let handle {
                Text("@\(handle)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(IMColor.secondary)
            }

            if let bio = profile?.bio.nilIfBlank {
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundStyle(IMColor.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                    .padding(.top, 2)
            }

            if let profile, profile.postCount > 0 || profile.followerCount > 0 {
                HStack(spacing: 8) {
                    publicStat(profile.postCount, "posts")
                    publicStat(profile.followerCount, "followers")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassCapsule(interactive: false)
                .padding(.top, 4)
            }
        }
        .padding(.top, 8)
    }

    private func publicStat(_ value: Int, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(Self.compact(value))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IMColor.label)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(IMColor.secondary)
        }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        HStack(spacing: 22) {
            actionButton("phone.fill", "Call", enabled: phone != nil) {
                open(scheme: "tel")
            }
            actionButton("video.fill", "FaceTime", enabled: phone != nil) {
                open(scheme: "facetime")
            }
            actionButton(isMuted ? "bell.slash.fill" : "bell.fill",
                         isMuted ? "Unmute" : "Mute", enabled: true) {
                guard let id = convo?.id else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.toggleWorldMute(id)
            }
        }
        .padding(.top, 2)
    }

    private var isMuted: Bool {
        guard let id = convo?.id else { return false }
        return app.isWorldMuted(id)
    }

    /// Hands the number to the system dialer / FaceTime — the only real call
    /// path there is, since My World has no calling backend of its own.
    private func open(scheme: String) {
        guard let phone else { return }
        let digits = phone.filter { "+0123456789".contains($0) }
        guard let url = URL(string: "\(scheme)://\(digits)"),
              UIApplication.shared.canOpenURL(url) else {
            app.showWorldNotice("This device can't place that call.")
            return
        }
        UIApplication.shared.open(url)
    }

    private func actionButton(_ icon: String, _ label: String,
                              enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(enabled ? IMColor.label : IMColor.secondary.opacity(0.55))
                    .frame(width: 58, height: 58)
                    .glass(cornerRadius: 29, interactive: enabled)
                    .opacity(enabled ? 1 : 0.72)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(enabled ? IMColor.secondary : IMColor.secondary.opacity(0.55))
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ContactTab.allCases) { t in
                    let selected = tab == t
                    Button {
                        withAnimation(.ggSnappy) { tab = t }
                    } label: {
                        Text(t.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected ? IMColor.label : IMColor.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background {
                                if selected {
                                    Capsule().fill(Color.clear)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .modifier(SelectedTabGlass(active: selected))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
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
            locationsSection
        case .backgrounds:
            backgroundsGrid
        case .links:
            linksSection
        case .documents:
            documentsSection
        }
    }

    // MARK: Info

    private var infoSection: some View {
        VStack(spacing: 12) {
            if let phone {
                phoneCard(phone)
            }

            if isGroup, let members = profile?.members, !members.isEmpty {
                membersCard(members)
            }

            statsCard
            settingsCard
        }
    }

    private func phoneCard(_ phone: String) -> some View {
        Button { open(scheme: "tel") } label: {
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
                    .foregroundStyle(IMColor.blue)
            }
            .padding(16)
            .background(cardShape)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func membersCard(_ members: [WorldContactMember]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.element.id) { i, member in
                HStack(spacing: 12) {
                    UserAvatar(size: 38,
                               gradient: SocialStore.gradient(for: member.handle ?? member.name),
                               letter: String(member.name.prefix(1)),
                               imageURL: member.avatarURL)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(.system(size: 16))
                            .foregroundStyle(IMColor.label)
                        if let h = member.handle {
                            Text("@\(h)")
                                .font(.system(size: 12))
                                .foregroundStyle(IMColor.secondary)
                        }
                    }
                    Spacer()
                    if !member.isYou, let h = member.handle {
                        Button {
                            app.closeWorldContact()
                            app.openUserProfile(handle: h, name: member.name,
                                                avatarURL: member.avatarURL)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(IMColor.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if i < members.count - 1 { rowDivider }
            }
        }
        .background(cardShape)
        .padding(.horizontal, 16)
    }

    private var statsCard: some View {
        let messages = (convo?.messages ?? []).filter { $0.kind != .timestamp && $0.kind != .system }
        let photos = app.worldChatPhotos(for: convo).count
        let voice = messages.filter { $0.kind == .audio }.count
        return HStack(spacing: 0) {
            stat("\(messages.count)", "messages")
            statDivider
            stat("\(photos)", "media")
            statDivider
            stat("\(voice)", "voice notes")
        }
        .padding(.vertical, 14)
        .background(cardShape)
        .padding(.horizontal, 16)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(IMColor.label)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(IMColor.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(IMColor.separator.opacity(0.5)).frame(width: 0.5, height: 28)
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { isMuted },
                set: { _ in if let id = convo?.id { app.toggleWorldMute(id) } }
            )) {
                Label {
                    Text("Mute notifications").font(.system(size: 16))
                } icon: {
                    Image(systemName: "bell.slash.fill").foregroundStyle(IMColor.blue)
                }
                .foregroundStyle(IMColor.label)
            }
            .tint(IMColor.blue)
            .padding(.horizontal, 16)
            .frame(height: 52)

            rowDivider

            Toggle(isOn: Binding(
                get: { convo?.pinned ?? false },
                set: { _ in if let id = convo?.id { app.togglePinWorldConversation(id) } }
            )) {
                Label {
                    Text("Pin to top").font(.system(size: 16))
                } icon: {
                    Image(systemName: "pin.fill").foregroundStyle(IMColor.blue)
                }
                .foregroundStyle(IMColor.label)
            }
            .tint(IMColor.blue)
            .padding(.horizontal, 16)
            .frame(height: 52)

            rowDivider

            Button {
                withAnimation(.easeOut(duration: 0.2)) { tab = .backgrounds }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(IMColor.blue)
                    Text("Chat wallpaper")
                        .font(.system(size: 16))
                        .foregroundStyle(IMColor.label)
                    Spacer()
                    Text((convo?.background ?? .none).title)
                        .font(.system(size: 15))
                        .foregroundStyle(IMColor.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IMColor.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            rowDivider

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                confirmingDelete = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23))
                    Text(isGroup ? "Leave conversation" : "Delete conversation")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(cardShape)
        .padding(.horizontal, 16)
    }

    // MARK: Locations

    private var locationsSection: some View {
        let pins = app.worldChatLocations(for: convo)
        return Group {
            if pins.isEmpty {
                emptyTab("Locations")
            } else {
                VStack(spacing: 12) {
                    ForEach(pins) { pin in
                        locationCard(pin)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func locationCard(_ pin: WorldMessage) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: pin.latitude ?? 0,
                                                longitude: pin.longitude ?? 0)
        return Button {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = pin.text.nilIfBlank ?? "Shared Location"
            item.openInMaps()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                StaticLocationMap(coordinate: coordinate)
                    .frame(height: 150)
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(IMColor.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.text.nilIfBlank ?? "Shared Location")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(IMColor.label)
                            .lineLimit(1)
                        Text(pin.fromUser ? "Shared by you" : "Shared with you")
                            .font(.system(size: 12))
                            .foregroundStyle(IMColor.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IMColor.secondary)
                }
                .padding(14)
            }
            .background(cardShape)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
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
        let links = sharedLinks
        return Group {
            if links.isEmpty {
                emptyTab("Links")
            } else {
                VStack(spacing: 12) {
                    ForEach(links, id: \.self) { url in
                        Button {
                            guard let target = Self.url(from: url) else { return }
                            UIApplication.shared.open(target)
                        } label: {
                            linkCard(icon: "link", tint: IMColor.blue,
                                     title: url, subtitle: "Shared link")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
        }
    }

    /// Links actually pasted into the thread, newest first, de-duplicated.
    private var sharedLinks: [String] {
        var seen = Set<String>()
        return (convo?.messages ?? []).reversed().flatMap { msg -> [String] in
            guard msg.kind == .text else { return [] }
            return msg.text
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .map(String.init)
                .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") || $0.hasPrefix("www.") }
        }
        .filter { seen.insert($0).inserted }
    }

    private static func url(from raw: String) -> URL? {
        URL(string: raw.hasPrefix("www.") ? "https://\(raw)" : raw)
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
        .background(cardShape)
        .contentShape(Rectangle())
    }

    // MARK: Documents

    private var documentsSection: some View {
        let docs = (convo?.messages ?? []).filter { $0.kind == .file }
        return Group {
            if docs.isEmpty {
                emptyTab("Documents")
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

    // MARK: Photos

    private var photosGrid: some View {
        let photos = app.worldChatPhotos(for: convo)
        return Group {
            if photos.isEmpty {
                emptyTab("Photos")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3),
                          spacing: 3) {
                    ForEach(photos) { photo in
                        MediaImage(url: photo.url, data: photo.data, cornerRadius: 0)
                            .frame(height: 118)
                            .overlay(alignment: .bottomTrailing) {
                                if photo.isVideo {
                                    Image(systemName: "play.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.45))
                                        .font(.system(size: 18))
                                        .padding(5)
                                }
                            }
                            .clipped()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Shared bits

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(IMColor.chrome.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(IMColor.label.opacity(0.08), lineWidth: 0.5)
            )
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(IMColor.separator.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 16)
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

    private static func compact(_ value: Int) -> String {
        switch value {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return String(format: "%.1fK", Double(value) / 1_000)
        default: return String(format: "%.1fM", Double(value) / 1_000_000)
        }
    }
}

/// Applies liquid glass only when a contact tab chip is selected.
private struct SelectedTabGlass: ViewModifier {
    var active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            content.glassCapsule(interactive: true, dense: true)
        } else {
            content
        }
    }
}
