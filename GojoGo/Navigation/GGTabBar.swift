import SwiftUI
import PhotosUI
import UIKit

private enum Msg {
    static let blue = Color.white
    static let sendFill = Color.white.opacity(0.18)
    static let label = Color.white.opacity(0.95)
    static let placeholder = Color.white.opacity(0.38)
    static let spring = Animation.spring(response: 0.40, dampingFraction: 0.88)
    static let tabHit: CGFloat = 44
    static let plusHit: CGFloat = 52
}

/// Bottom chrome: glass tabs + plus · morphs into liquid-glass Messages composer.
struct GGTabBar: View {
    @EnvironmentObject var app: AppState
    var ghosted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if app.isComposing {
                composeStack
                    .transition(.opacity.combined(with: .offset(y: 10)))
            } else {
                navRow
                    .transition(.opacity.combined(with: .offset(y: 10)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
        // Absorb taps in the bar chrome so scroll views underneath can't steal them.
        .background {
            Color.black.opacity(0.001)
                .padding(.horizontal, -20)
                .padding(.top, 12)
                .padding(.bottom, -8)
                .contentShape(Rectangle())
        }
        .animation(Msg.spring, value: app.isComposing)
        .animation(Msg.spring, value: app.showAttachMenu)
        .animation(Msg.spring, value: app.composeAttachments.count)
        .animation(Msg.spring, value: app.canSendCompose)
    }

    // MARK: Navigation

    private var navRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                tabButton(.home)  { HomeIcon() }
                tabButton(.watch) { WatchIcon() }
                madeleineButton
                tabButton(.travel) { TravelIcon() }
                tabButton(.economy) { BagIcon() }
                tabButton(.search)  { SearchIcon() }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            // Charcoal tinted Liquid Glass — map/content refracts through.
            .glassCapsule(tint: Color.black.opacity(0.58), interactive: true, dense: true)
            .contentShape(Capsule())
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .opacity(ghosted ? 0.72 : 1)

            if app.activeTab == .home {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    app.openComposer()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Msg.blue)
                        .frame(width: Msg.plusHit, height: Msg.plusHit)
                        .contentShape(Circle())
                        .glassCapsule(tint: Color.black.opacity(0.58), interactive: true, dense: true)
                }
                .buttonStyle(TabPressStyle())
                .accessibilityLabel("New post")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Msg.spring, value: app.activeTab)
    }

    private func tabButton<Icon: View>(_ tab: AppTab, @ViewBuilder icon: () -> Icon) -> some View {
        let active = app.activeTab == tab
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.2)) { app.activeTab = tab }
        } label: {
            icon()
                .environment(\.ggTabActive, active)
                .frame(width: Msg.tabHit, height: Msg.tabHit)
                .background(
                    Capsule()
                        .fill(active ? Color.white.opacity(0.28) : .clear)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 2)
                )
                .contentShape(Circle())
        }
        .buttonStyle(TabPressStyle())
    }

    private var madeleineButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.2)) { app.activeTab = .madeleine }
        } label: {
            MiniOrb(size: 34, glow: true)
                .frame(width: Msg.tabHit, height: Msg.tabHit)
                .contentShape(Circle())
                .opacity(app.activeTab == .madeleine ? 1 : 0.9)
        }
        .buttonStyle(TabPressStyle())
    }

    // MARK: Compose

    private var composeStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            if app.showAttachMenu {
                AttachGlassMenu()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .bottomLeading)
                            .combined(with: .opacity)
                            .combined(with: .offset(y: 8)),
                        removal: .opacity))
            }

            if !app.composeAttachments.isEmpty {
                AttachmentsTray()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            ComposeChrome()
        }
    }
}

// MARK: - Liquid glass compose pill (plus + text + send inside one capsule)

struct ComposeChrome: View {
    @EnvironmentObject var app: AppState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(Msg.spring) { app.showAttachMenu.toggle() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Msg.blue)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .rotationEffect(.degrees(app.showAttachMenu ? 45 : 0))
            }
            .buttonStyle(TabPressStyle())

            ZStack(alignment: .leading) {
                if app.composeText.isEmpty {
                    Text("Share something…")
                        .font(.system(size: 17))
                        .foregroundStyle(Msg.placeholder)
                        .allowsHitTesting(false)
                }
                TextField("", text: $app.composeText, axis: .vertical)
                    .font(.system(size: 17))
                    .foregroundStyle(Msg.label)
                    .lineLimit(1...5)
                    .focused($focused)
                    .tint(Msg.blue)
            }
            .frame(minHeight: 24)

            Button {
                guard app.canSendCompose else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                focused = false
                app.publishCompose()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(app.canSendCompose ? Color.black : Color.white.opacity(0.35))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(app.canSendCompose ? Color.white : Msg.sendFill.opacity(0.55))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(TabPressStyle())
            .disabled(!app.canSendCompose)
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .glassCapsule(tint: Color.black.opacity(0.58), interactive: true, dense: true)
        .contentShape(Capsule())
        .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { focused = true }
        }
    }
}

// MARK: - Liquid glass attach menu (matches reference list)

struct AttachGlassMenu: View {
    @EnvironmentObject var app: AppState
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var shortItems: [PhotosPickerItem] = []
    @State private var videoItems: [PhotosPickerItem] = []
    @State private var showRecorder = false
    @State private var isImporting = false

    private let rows: [(title: String, icon: String, kind: ComposeMediaKind)] = [
        ("Text Only", "text.alignleft", .textOnly),
        ("Record Audio", "mic.fill", .audio),
        ("Short", "bolt.fill", .short),
        ("Video — Long-form\n(Watch)", "play.rectangle.fill", .longForm),
        ("Photo & Video", "photo.on.rectangle", .photo),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                menuRow(row)
                if i < rows.count - 1 {
                    Divider().background(Color.white.opacity(0.08))
                        .padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: 280, alignment: .leading)
        .liquidGlass(cornerRadius: 28, interactive: false)
        .overlay {
            if isImporting {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.45))
                ProgressView()
                    .tint(.white)
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: 12,
            matching: .any(of: [.images, .videos])
        )
        .photosPicker(
            isPresented: $showShortPicker,
            selection: $shortItems,
            maxSelectionCount: 8,
            matching: .videos
        )
        .photosPicker(
            isPresented: $showVideoPicker,
            selection: $videoItems,
            maxSelectionCount: 8,
            matching: .videos
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await ingestMany(items, .photo); photoItems = [] }
        }
        .onChange(of: shortItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await ingestMany(items, .short); shortItems = [] }
        }
        .onChange(of: videoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await ingestMany(items, .longForm); videoItems = [] }
        }
        .sheet(isPresented: $showRecorder) {
            AudioRecorderSheet { url, label, poster in
                app.addAttachment(ComposeAttachment(
                    kind: .audio, imageData: poster, durationLabel: label, audioURL: url))
                withAnimation(Msg.spring) { app.showAttachMenu = false }
            }
        }
    }

    @State private var showPhotoPicker = false
    @State private var showShortPicker = false
    @State private var showVideoPicker = false

    private func menuRow(_ row: (title: String, icon: String, kind: ComposeMediaKind)) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            select(row.kind)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: row.icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Msg.blue)
                    .frame(width: 28, alignment: .center)
                Text(row.title)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Msg.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
        .disabled(isImporting)
    }

    private func select(_ kind: ComposeMediaKind) {
        switch kind {
        case .textOnly:
            withAnimation(Msg.spring) { app.showAttachMenu = false }
        case .audio:
            showRecorder = true
        case .photo:
            showPhotoPicker = true
        case .short:
            showShortPicker = true
        case .longForm:
            showVideoPicker = true
        }
    }

    private func ingestMany(_ items: [PhotosPickerItem], _ kind: ComposeMediaKind) async {
        await MainActor.run { isImporting = true }
        let attachments = await ComposeMediaIngest.attachments(from: items, defaultKind: kind)
        await MainActor.run {
            app.addAttachments(attachments)
            isImporting = false
        }
    }
}

// MARK: - Attachments tray (glass)

struct AttachmentsTray: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(app.composeAttachments) { att in
                    ZStack(alignment: .topTrailing) {
                        // Same portrait tile as before — tap opens editor.
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            app.openMediaEditor(att.id)
                        } label: {
                            ZStack(alignment: .bottom) {
                                Group {
                                    if let ui = UIImage(data: att.imageData) {
                                        Image(uiImage: ui).resizable().scaledToFill()
                                    } else {
                                        Color.black.opacity(0.3)
                                    }
                                }
                                .frame(width: 96, height: 128)
                                .clipped()

                                if att.isVideo || att.kind == .audio {
                                    HStack(spacing: 4) {
                                        Image(systemName: att.kind == .audio ? "waveform"
                                              : att.kind == .short ? "bolt.fill" : "play.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                        if let d = att.durationLabel {
                                            Text(d).font(.system(size: 11, weight: .semibold))
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                }
                            }
                            .frame(width: 96, height: 128)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(Msg.spring) { app.removeAttachment(att.id) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.4))
                                .font(.system(size: 22))
                                .frame(width: 36, height: 36)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(2)
                    }
                }
            }
            .padding(10)
        }
        .liquidGlass(cornerRadius: 22, interactive: false)
    }
}

// MARK: - Press styles + tab icons

/// Soft feedback without shrinking the hit target mid-tap (scale cancels presses on device).
struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Kept for non-tab UI; prefer `TabPressStyle` for bottom chrome.
struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct GGTabActiveKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var ggTabActive: Bool {
        get { self[GGTabActiveKey.self] }
        set { self[GGTabActiveKey.self] = newValue }
    }
}

private struct IconStroke: ViewModifier {
    @Environment(\.ggTabActive) var active
    func body(content: Content) -> some View {
        content.foregroundStyle(active ? Msg.blue : Color.white.opacity(0.55))
    }
}
private extension View { func iconStroke() -> some View { modifier(IconStroke()) } }

struct HomeIcon: View {
    var body: some View {
        Image(systemName: "house").font(.system(size: 18, weight: .regular)).iconStroke()
    }
}
struct WatchIcon: View {
    var body: some View {
        Image(systemName: "play.rectangle").font(.system(size: 18, weight: .regular)).iconStroke()
    }
}
struct BagIcon: View {
    var body: some View {
        Image(systemName: "bag").font(.system(size: 18, weight: .regular)).iconStroke()
    }
}
struct SearchIcon: View {
    var body: some View {
        Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold)).iconStroke()
    }
}
struct TravelIcon: View {
    var body: some View {
        Image(systemName: "car").font(.system(size: 17, weight: .regular)).iconStroke()
    }
}
