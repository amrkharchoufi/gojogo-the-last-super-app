import SwiftUI
import PhotosUI
import UIKit

/// My World settings — the account you show inside My World (name + photo, which
/// are separate from your public GojoGo profile) plus the device preferences that
/// change how the chats behave.
///
/// Everything here does something real: the profile card writes to the World
/// profile endpoint, notifications register/unregister this device for push, and
/// the toggles are read by the composer and apps drawer.
struct WorldSettingsView: View {
    @EnvironmentObject var app: AppState

    @State private var avatarItem: PhotosPickerItem?
    @State private var cacheSize: Int64 = 0
    @FocusState private var nameFocused: Bool

    private var dirty: Bool {
        app.worldSettingsAvatarData != nil
            || app.worldSettingsName.trimmingCharacters(in: .whitespacesAndNewlines)
                != app.worldSetupName
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    profileCard
                    privacySection
                    notificationsSection
                    appearanceSection
                    storageSection
                    about
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(IMColor.sheetBG.ignoresSafeArea())
        .task { cacheSize = app.worldMediaCacheSize }
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    app.worldSettingsAvatarData = data
                    app.worldSettingsSaved = false
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("My World Settings")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(IMColor.label)
            HStack {
                Spacer()
                Button("Done") { app.worldSheet = nil }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(IMColor.blue)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: Profile

    private var profileCard: some View {
        VStack(spacing: 16) {
            avatarPicker(pickedData: app.worldSettingsAvatarData,
                         savedURL: app.worldSetupAvatarURL,
                         initial: initial)

            VStack(spacing: 0) {
                settingsRow("Name", icon: "person.fill", tint: IMColor.blue) {
                    TextField("Your name", text: $app.worldSettingsName)
                        .font(.system(size: 16))
                        .foregroundStyle(IMColor.label)
                        .multilineTextAlignment(.trailing)
                        .tint(IMColor.blue)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { app.saveWorldSettingsProfile() }
                }

                divider

                settingsRow("Phone", icon: "phone.fill",
                            tint: Color(red: 0.2, green: 0.78, blue: 0.35)) {
                    HStack(spacing: 6) {
                        Text(app.worldPhone ?? "Not verified")
                            .font(.system(size: 16))
                            .foregroundStyle(IMColor.secondary)
                        if app.worldPhone != nil {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(IMColor.blue)
                        }
                    }
                }
            }
            .background(card)

            Text("Your name and photo here are what people see in My World — your public GojoGo profile stays separate.")
                .font(.system(size: 12))
                .foregroundStyle(IMColor.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = app.worldSettingsError {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if dirty || app.worldSettingsBusy {
                Button {
                    nameFocused = false
                    app.saveWorldSettingsProfile()
                } label: {
                    Text(app.worldSettingsBusy ? "Saving…" : "Save changes")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(IMColor.blue))
                }
                .buttonStyle(.plain)
                .disabled(app.worldSettingsBusy)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if app.worldSettingsSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.35))
                    .transition(.opacity)
            }
        }
        .animation(.ggSnappy, value: dirty)
        .animation(.ggSnappy, value: app.worldSettingsBusy)
        .padding(.top, 4)
    }

    /// Values are read on the main actor and handed in, because the picker's
    /// label closure is not actor-isolated.
    private func avatarPicker(pickedData: Data?, savedURL: String?,
                              initial: String) -> some View {
        PhotosPicker(selection: $avatarItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let pickedData, let ui = UIImage(data: pickedData) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else if let savedURL {
                        MediaImage(url: savedURL, cornerRadius: 48)
                    } else {
                        ZStack {
                            Circle().fill(IMColor.chrome)
                            Text(initial)
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(IMColor.secondary)
                        }
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())

                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(IMColor.blue))
                    .overlay(Circle().strokeBorder(IMColor.sheetBG, lineWidth: 3))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change My World photo")
    }

    private var initial: String {
        let source = app.worldSettingsName.isEmpty ? app.user.name : app.worldSettingsName
        return String(source.prefix(1)).uppercased()
    }

    // MARK: Privacy

    private var privacySection: some View {
        section("PRIVACY") {
            VStack(spacing: 0) {
                toggleRow("Typing indicators", icon: "ellipsis.bubble.fill", tint: IMColor.blue,
                          subtitle: "Let people see when you're writing",
                          isOn: $app.worldTypingIndicatorsEnabled)
                divider
                toggleRow("Share location", icon: "location.fill",
                          tint: Color(red: 0.2, green: 0.78, blue: 0.35),
                          subtitle: "Show Location in the chat apps drawer",
                          isOn: $app.worldLocationSharingEnabled)
            }
            .background(card)
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        section("NOTIFICATIONS") {
            VStack(spacing: 0) {
                toggleRow("Push notifications", icon: "bell.fill",
                          tint: Color(red: 1, green: 0.27, blue: 0.23),
                          subtitle: "New messages and activity on this device",
                          isOn: $app.worldPushEnabled)
                divider
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    settingsRow("iOS notification settings", icon: "gearshape.fill",
                                tint: IMColor.secondary) {
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(IMColor.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .background(card)
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        section("NEW CHAT WALLPAPER") {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(WorldChatBackground.allCases) { bg in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.ggSnappy) { app.worldDefaultBackground = bg }
                            } label: {
                                VStack(spacing: 6) {
                                    swatch(bg)
                                    Text(bg.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(app.worldDefaultBackground == bg
                                                         ? IMColor.label : IMColor.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
                .background(card)

                Text("Applied to chats you start. Change any chat's wallpaper from its contact page.")
                    .font(.system(size: 12))
                    .foregroundStyle(IMColor.secondary)
                    .padding(.horizontal, 2)
            }
        }
    }

    private func swatch(_ bg: WorldChatBackground) -> some View {
        ZStack {
            if bg == .none {
                Circle().fill(IMColor.bg)
                    .overlay(Circle().strokeBorder(IMColor.separator, lineWidth: 1))
                    .overlay(
                        Image(systemName: "circle.slash")
                            .font(.system(size: 18))
                            .foregroundStyle(IMColor.secondary)
                    )
            } else {
                Circle().fill(
                    LinearGradient(colors: bg.gradient,
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: 54, height: 54)
        .overlay(
            Circle().strokeBorder(app.worldDefaultBackground == bg ? IMColor.blue : .clear,
                                  lineWidth: 2.5)
        )
    }

    // MARK: Storage

    private var storageSection: some View {
        section("STORAGE") {
            VStack(spacing: 0) {
                settingsRow("Cached media", icon: "internaldrive.fill", tint: IMColor.secondary) {
                    Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                        .font(.system(size: 16))
                        .foregroundStyle(IMColor.secondary)
                }
                divider
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    app.clearWorldMediaCache()
                    withAnimation(.ggSnappy) { cacheSize = app.worldMediaCacheSize }
                } label: {
                    HStack {
                        Text("Clear voice notes & stickers cache")
                            .font(.system(size: 16))
                            .foregroundStyle(cacheSize > 0 ? IMColor.blue : IMColor.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(cacheSize == 0)
            }
            .background(card)
        }
    }

    // MARK: About

    private var about: some View {
        VStack(spacing: 6) {
            Text("GojoGo · My World")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IMColor.secondary)
            Text("Version \(Self.appVersion)")
                .font(.system(size: 12))
                .foregroundStyle(IMColor.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: Building blocks

    private var card: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(IMColor.chrome)
    }

    private var divider: some View {
        Rectangle()
            .fill(IMColor.separator.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(IMColor.secondary)
                .padding(.leading, 4)
            content()
        }
    }

    private func settingsRow<Trailing: View>(
        _ title: String, icon: String, tint: Color,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint))
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(IMColor.label)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func toggleRow(_ title: String, icon: String, tint: Color,
                           subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(IMColor.label)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(IMColor.secondary)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(IMColor.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
