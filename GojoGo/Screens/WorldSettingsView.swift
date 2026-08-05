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
    @State private var backupFrequency = WorldBackupSync.frequency
    @State private var messagePreviews = WorldAppGroup.messagePreviewsEnabled
    @State private var backingUpNow = false
    @State private var backupTick = 0
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
                    backupSection
                    storageSection
                    about
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await app.loadWorldProfile()
                cacheSize = app.worldMediaCacheSize
            }
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
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(IMColor.label)
            HStack {
                Spacer()
                Button("Done") { app.worldSheet = nil }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(IMColor.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassCapsule(interactive: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: Profile

    private var profileCard: some View {
        VStack(spacing: 16) {
            avatarPicker(pickedData: app.worldSettingsAvatarData,
                         savedURL: app.worldSetupAvatarURL,
                         initial: initial)

            VStack(spacing: 0) {
                settingsRow("Name", icon: "person") {
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

                settingsRow("Phone", icon: "phone") {
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

            Text("Your name and photo here are what people see in GojoMessages — your public GojoGo profile stays separate.")
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
                .buttonStyle(PressableStyle())
                .disabled(app.worldSettingsBusy)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if app.worldSettingsSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.35))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCapsule(interactive: false)
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
                        MediaImage(url: savedURL, cornerRadius: 50)
                    } else {
                        ZStack {
                            Circle().fill(IMColor.chrome.opacity(0.8))
                            Text(initial)
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(IMColor.secondary)
                        }
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(IMColor.label.opacity(0.12), lineWidth: 1))

                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(IMColor.blue))
                    .overlay(Circle().strokeBorder(IMColor.sheetBG, lineWidth: 3))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change GojoMessages photo")
    }

    private var initial: String {
        let source = app.worldSettingsName.isEmpty ? app.user.name : app.worldSettingsName
        return String(source.prefix(1)).uppercased()
    }

    // MARK: Privacy

    private var privacySection: some View {
        section("PRIVACY") {
            VStack(spacing: 0) {
                toggleRow("Typing indicators", icon: "ellipsis.bubble",
                          isOn: $app.worldTypingIndicatorsEnabled)
                divider
                toggleRow("Share location", icon: "location",
                          isOn: $app.worldLocationSharingEnabled)
            }
            .background(card)
            footnote("Typing indicators let people see when you're writing. "
                     + "Location adds it to the chat apps drawer.")
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        section("NOTIFICATIONS") {
            VStack(spacing: 0) {
                toggleRow("Push notifications", icon: "bell", isOn: $app.worldPushEnabled)
                divider
                // E2EE Phase G. The server has not been able to write a message
                // into a push since Phase A — it only holds ciphertext — so the
                // banner content is decrypted on this device, by the
                // notification extension. Which means the device can also
                // decline to: off leaves the generic "New message" the server
                // sent. Stored in the shared suite, because the process that
                // reads it is not this one.
                toggleRow("Show message previews", icon: "text.bubble",
                          isOn: Binding(get: { messagePreviews },
                                        set: { messagePreviews = $0
                                               WorldAppGroup.messagePreviewsEnabled = $0 }))
                divider
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    settingsRow("iOS notification settings", icon: "gearshape") {
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(IMColor.secondary)
                    }
                }
                .buttonStyle(PressableStyle())
            }
            .background(card)
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        section("NEW CHAT WALLPAPER") {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        // Presets only. This is the wallpaper *new* chats start
                        // with, and one picture behind every future thread is a
                        // different decision from choosing one for a thread you
                        // are looking at — which is where the photo option is.
                        ForEach(WorldChatBackground.presets) { bg in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.ggSnappy) { app.worldDefaultBackground = bg }
                            } label: {
                                VStack(spacing: 7) {
                                    swatch(bg)
                                    Text(bg.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(app.worldDefaultBackground == bg
                                                         ? IMColor.label : IMColor.secondary)
                                }
                            }
                            .buttonStyle(PressableStyle())
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
        let selected = app.worldDefaultBackground == bg
        return ZStack {
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
        .frame(width: 56, height: 56)
        .overlay(
            Circle().strokeBorder(selected ? IMColor.blue : IMColor.label.opacity(0.08),
                                  lineWidth: selected ? 2.5 : 0.5)
        )
        .overlay(alignment: .bottomTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, IMColor.blue)
                    .font(.system(size: 16))
                    .offset(x: 2, y: 2)
            }
        }
    }

    // MARK: Backup (E2EE Phase F)
    //
    // A backup nobody can see is one nobody can trust — and this one matters
    // more than most, because forward secrecy means the device holds the only
    // copy. Every line here is read from what actually happened, so the screen
    // can never claim a backup that did not run.

    private var backupSection: some View {
        section("CHAT BACKUP") {
            VStack(spacing: 0) {
                // A menu rather than four radio rows: the cadence is one
                // decision with one current answer, and the answer belongs on
                // the right of the row like every other value here.
                Menu {
                    Picker("", selection: Binding(
                        get: { backupFrequency },
                        set: { next in
                            WorldBackupSync.frequency = next
                            backupFrequency = next
                            if next != .off, let id = SocialStore.shared.myProfileId {
                                WorldBackupSync.scheduleExport(for: id)
                            }
                        })) {
                        ForEach(WorldBackupSync.Frequency.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    settingsRow("Back up to iCloud", icon: "icloud") {
                        HStack(spacing: 4) {
                            Text(backupFrequency.title)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(IMColor.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(IMColor.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                divider
                valueRow("Last backup", icon: "clock.arrow.circlepath", value: backupStatus)

                if backupFrequency != .off {
                    divider
                    Button {
                        guard let id = SocialStore.shared.myProfileId else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        backingUpNow = true
                        Task {
                            // Forced: someone tapping this is asking for one
                            // upload now, not for the cadence's opinion.
                            await WorldBackupSync.export(for: id, force: true)
                            backingUpNow = false
                            backupTick &+= 1
                        }
                    } label: {
                        settingsRow(backingUpNow ? "Backing up…" : "Back up now",
                                    icon: "arrow.up.to.line") {
                            if backingUpNow { ProgressView().tint(IMColor.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(backingUpNow)
                }
            }
            .background(card)
            .id(backupTick)

            // The honest sentence. Not a reassurance — the point is that we
            // cannot read it, and that turning it off means a lost phone is a
            // lost history, which is a consequence of the encryption rather
            // than a defect.
            footnote("Messages are encrypted on this device before they leave it, so "
                     + "nobody — including us and Apple — can read the backup. "
                     + "With it off, a lost phone means lost messages.")
        }
    }

    private var backupStatus: String {
        guard backupFrequency != .off else { return "Off" }
        guard let at = WorldBackupSync.lastBackupAt else { return "Not yet" }
        let when = RelativeDateTimeFormatter().localizedString(for: at, relativeTo: Date())
        let size = WorldBackupSync.lastBackupBytes
        guard size > 0 else { return when }
        return "\(when) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
    }

    // MARK: Storage

    private var storageSection: some View {
        section("STORAGE") {
            VStack(spacing: 0) {
                settingsRow("Cached media", icon: "internaldrive") {
                    // ByteCountFormatter renders 0 as "Zero KB", which reads oddly.
                    Text(cacheSize == 0
                         ? "Empty"
                         : ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
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
                            .font(.system(size: 16, weight: .medium))
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
            Text("GojoGo · GojoMessages")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IMColor.secondary)
            Text("Version \(Self.appVersion)")
                .font(.system(size: 12))
                .foregroundStyle(IMColor.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glass(cornerRadius: 16, interactive: false)
        .padding(.top, 4)
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: Building blocks

    private var card: some View {
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

    private var divider: some View {
        Rectangle()
            .fill(IMColor.separator.opacity(0.45))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(IMColor.secondary)
                .padding(.leading, 6)
            content()
        }
    }

    /// One row shape for the whole screen.
    ///
    /// The old version took a `tint` and every row picked its own — blue, green,
    /// red, grey — which turned a settings list into a colour chart and made the
    /// two rows that genuinely mean "careful" indistinguishable from the rest.
    /// The chip is neutral now; colour is spent only where it carries meaning.
    private func settingsRow<Trailing: View>(
        _ title: String, icon: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            chip(icon)
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(IMColor.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    /// The right-hand value, borrowed from the feed's settings: a row that only
    /// names a thing makes you open it to find out where you stand.
    private func valueRow(_ title: String, icon: String, value: String) -> some View {
        settingsRow(title, icon: icon) {
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(IMColor.secondary)
                .lineLimit(1)
        }
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        settingsRow(title, icon: icon) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(IMColor.blue)
        }
    }

    private func chip(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(IMColor.label)
            .frame(width: 26, height: 26)
            .background(Circle().fill(IMColor.label.opacity(0.08)))
    }

    /// Explanatory text belongs under a group, not stacked inside every row.
    /// Subtitles on each line tripled the height of the screen and pushed the
    /// things people actually came for below the fold.
    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(IMColor.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}
