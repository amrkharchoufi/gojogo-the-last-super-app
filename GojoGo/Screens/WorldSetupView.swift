import SwiftUI
import PhotosUI

/// WhatsApp-style first-run setup for My World — but in GojoGo's own design.
/// Onboarding pages → phone number → verification code → World name + photo.
/// Shown (via RootView) whenever a connected user enters My World before their
/// phone-verified World identity is set up.
struct WorldSetupView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            IMColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Group {
                    switch app.worldSetupStep {
                    case .intro:   introStep
                    case .phone:   phoneStep
                    case .code:    codeStep
                    case .profile: profileStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))
                .id(app.worldSetupStep)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: app.worldSetupStep)
    }

    // MARK: Top bar (back / skip)

    private var topBar: some View {
        HStack {
            if app.worldSetupStep == .intro {
                Spacer()
                Button("Later") { app.enterCollections() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
            } else {
                Button {
                    app.backWorldSetup()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                        .frame(width: 40, height: 40)
                }
                Spacer()
                stepDots
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach([WorldSetupStep.phone, .code, .profile], id: \.rawValue) { step in
                Capsule()
                    .fill(app.worldSetupStep == step ? GGColor.textPrimary : GGColor.textPrimary.opacity(0.2))
                    .frame(width: app.worldSetupStep == step ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: app.worldSetupStep)
    }

    // MARK: Step 1 — intro pages

    private var introStep: some View {
        VStack(spacing: 0) {
            TabView {
                introPage(icon: "person.2.fill", title: "My World",
                          subtitle: "Your private circle — separate from your public GojoGo. The people you actually talk to.")
                introPage(icon: "bubble.left.and.bubble.right.fill", title: "Real conversations",
                          subtitle: "Group chats, circles, polls, reactions and send-later — everything a private space should have.")
                introPage(icon: "lock.fill", title: "Just your number",
                          subtitle: "Set up My World with your phone number, like a private line. That's how friends find you here.")
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            AccentButton(title: "Get started", trailingArrow: true) {
                app.advanceWorldFromIntro()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 34)
        }
    }

    private func introPage(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle()
                    .fill(GGColor.surface)
                    .frame(width: 128, height: 128)
                Image(systemName: icon)
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(GGColor.textPrimary)
            }
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(GGColor.textPrimary)
                Text(subtitle)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(GGColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 40)
            }
            Spacer()
            Spacer()
        }
    }

    // MARK: Step 2 — phone number

    private var phoneStep: some View {
        stepScaffold(
            title: "Your number",
            subtitle: "We'll text you a 6-digit code to confirm it's you. This is your private My World line."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                TextField("", text: $app.worldSetupPhone, prompt:
                    Text("+1 555 123 4567").foregroundColor(GGColor.textTertiary))
                    .textFieldStyle(.plain)
                    .keyboardType(.phonePad)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(GGColor.textPrimary)
                    .tint(GGColor.textPrimary)
                underline
                errorText
            }
        } cta: {
            AccentButton(title: app.worldSetupBusy ? "Sending…" : "Send code", trailingArrow: !app.worldSetupBusy) {
                app.worldSubmitPhone()
            }
            .disabled(app.worldSetupBusy)
        }
    }

    // MARK: Step 3 — verification code

    private var codeStep: some View {
        stepScaffold(
            title: "Enter the code",
            subtitle: "Sent to \(app.worldSetupPhone). It may take a moment to arrive."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                TextField("", text: $app.worldSetupCode, prompt:
                    Text("• • • • • •").foregroundColor(GGColor.textTertiary))
                    .textFieldStyle(.plain)
                    .keyboardType(.numberPad)
                    .font(.system(size: 40, weight: .bold))
                    .tracking(8)
                    .foregroundStyle(GGColor.textPrimary)
                    .tint(GGColor.textPrimary)
                    .onChange(of: app.worldSetupCode) { _, new in
                        app.worldSetupCode = String(new.filter(\.isNumber).prefix(6))
                    }
                underline
                Button("Resend code") { app.worldResendCode() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                errorText
            }
        } cta: {
            AccentButton(title: app.worldSetupBusy ? "Verifying…" : "Verify", trailingArrow: !app.worldSetupBusy) {
                app.worldSubmitCode()
            }
            .disabled(app.worldSetupBusy)
        }
    }

    // MARK: Step 4 — World profile (name + photo)

    private var profileStep: some View {
        stepScaffold(
            title: "Your My World profile",
            subtitle: "This name and photo are how friends see you in My World — separate from your public GojoGo profile."
        ) {
            VStack(spacing: 26) {
                avatarPicker
                VStack(alignment: .leading, spacing: 12) {
                    TextField("", text: $app.worldSetupName, prompt:
                        Text("Your name").foregroundColor(GGColor.textTertiary))
                        .textFieldStyle(.plain)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(GGColor.textPrimary)
                        .tint(GGColor.textPrimary)
                        .multilineTextAlignment(.center)
                    underline
                }
                errorText
            }
        } cta: {
            AccentButton(title: app.worldSetupBusy ? "Saving…" : "Enter My World", trailingArrow: !app.worldSetupBusy) {
                app.worldSaveProfile()
            }
            .disabled(app.worldSetupBusy)
        }
    }

    @State private var pickerItem: PhotosPickerItem?

    private var avatarPicker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let data = app.worldSetupAvatarData, let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else if let url = app.worldSetupAvatarURL {
                        MediaImage(url: url, cornerRadius: 54)
                    } else {
                        ZStack {
                            Circle().fill(GGColor.surface)
                            Text(String((app.worldSetupName.first ?? "?").uppercased()))
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(GGColor.textSecondary)
                        }
                    }
                }
                .frame(width: 108, height: 108)
                .clipShape(Circle())

                Image(systemName: "camera.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.onAccent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(GGColor.white))
                    .overlay(Circle().strokeBorder(IMColor.bg, lineWidth: 3))
            }
        }
        .buttonStyle(PressableStyle())
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    app.worldSetupAvatarData = data
                }
            }
        }
    }

    // MARK: Shared scaffold

    @ViewBuilder
    private func stepScaffold<Content: View, CTA: View>(
        title: String, subtitle: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder cta: () -> CTA
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(GGColor.textPrimary)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(GGColor.textSecondary)
                    .lineSpacing(3)
            }
            .padding(.top, 14)

            Spacer(minLength: 28)
            content()
            Spacer()
            cta()
                .padding(.bottom, 34)
        }
        .padding(.horizontal, 28)
    }

    private var underline: some View {
        Rectangle().fill(GGColor.textPrimary.opacity(0.16)).frame(height: 1.5)
    }

    @ViewBuilder
    private var errorText: some View {
        if let error = app.worldSetupError {
            Text(error)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "FF5A5A"))
                .transition(.opacity)
        }
    }
}
