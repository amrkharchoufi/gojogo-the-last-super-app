import SwiftUI

// MARK: - Settings
//
// Everything that belongs to the *account* rather than to a screen. It exists
// because the profile's overflow menu had been growing an entry per milestone —
// edit profile, business profiles, the wallet, the theme, sign out — and a menu
// that grows like that stops being a menu.
//
// One rule for what lands here: if it changes who you are, what you can act as,
// how you pay, or how the app looks, it is a setting. If it acts on the content
// in front of you, it belongs on that screen.
//
// **Rows open things by closing this sheet first.** The screens below are
// AppState-driven sheets already owned by ProfileView (or, for the wallet, by
// the root), and a second live owner of the same flag silently kills the cover
// instead of presenting it — a bug this codebase has paid for once already.
// Closing then setting on the next runloop keeps exactly one owner.

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    private var handle: String { app.user.handle }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    account
                    money
                    audience
                    appearance
                    about
                    signOut
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .task { await app.refreshWallet() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SETTINGS")
                    .font(.ggMono(11, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Text(handle.isEmpty ? "Your account" : "@\(handle)")
                    .font(.gg(22, .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer()
            Button {
                app.showSettings = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(GGColor.surface))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: Groups

    private var account: some View {
        group("Account") {
            row("Edit profile", "person.crop.circle",
                detail: app.user.name) {
                open { app.showEditProfile = true }
            }
            divider
            row(app.hasBusinessProfile ? "Business profiles" : "Create a business profile",
                "briefcase",
                detail: app.hasBusinessProfile ? "\(app.ownedBusinesses.count)" : "") {
                open { app.showBusinessProfiles = true }
            }
        }
    }

    private var money: some View {
        group("Money") {
            // The wallet is account-level on purpose: it is what every vertical
            // spends from, so it belongs to the person and not to delivery.
            row("GoJo Wallet", "wallet.bifold",
                detail: app.wallet == nil ? "" : app.walletBalanceLabel) {
                open { app.showWallet = true }
            }
        }
    }

    private var audience: some View {
        group("Audience") {
            row("Close friends", "star.circle",
                detail: app.closeFriends.isEmpty ? "" : "\(app.closeFriends.count)") {
                open { app.showCloseFriends = true }
            }
            divider
            row("Story archive", "clock.arrow.circlepath") {
                open { app.showStoryArchive = true }
            }
        }
    }

    private var appearance: some View {
        group("Appearance") {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                app.toggleTheme()
            } label: {
                HStack(spacing: 12) {
                    icon(app.appTheme == .dark ? "moon" : "sun.max")
                    Text("Theme")
                        .font(.gg(15))
                        .foregroundStyle(GGColor.textPrimary)
                    Spacer()
                    Text(app.appTheme == .dark ? "Dark" : "Light")
                        .font(.ggMono(13, .medium))
                        .foregroundStyle(GGColor.textSecondary)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var about: some View {
        group("About") {
            HStack(spacing: 12) {
                icon("info.circle")
                Text("Version")
                    .font(.gg(15))
                    .foregroundStyle(GGColor.textPrimary)
                Spacer()
                Text(Self.version)
                    .font(.ggMono(13, .medium))
                    .foregroundStyle(GGColor.textSecondary)
            }
            .padding(.vertical, 13)
        }
    }

    private var signOut: some View {
        Button {
            app.showSettings = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { app.signOut() }
        } label: {
            Text("Sign out")
                .font(.gg(15, .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(GGColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(GGColor.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Pieces

    private func group<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.ggMono(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(GGColor.textTertiary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(GGColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(GGColor.hairline, lineWidth: 1))
        }
    }

    /// A row's `detail` is the current value, not a description — "$56.51",
    /// "Dark", how many businesses. A settings screen that only lists names
    /// makes you open every row to find out where you stand.
    private func row(_ title: String, _ symbol: String, detail: String = "",
                     action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                icon(symbol)
                Text(title)
                    .font(.gg(15))
                    .foregroundStyle(GGColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.ggMono(13, .medium))
                        .foregroundStyle(GGColor.textSecondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GGColor.textTertiary)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(GGColor.textPrimary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(GGColor.ink(0.08)))
    }

    private var divider: some View {
        Divider().overlay(GGColor.hairline)
    }

    /// Closes this sheet, then opens the next one. See the note at the top:
    /// two live owners of the same presentation flag is a silent no-op.
    private func open(_ action: @escaping () -> Void) {
        app.showSettings = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: action)
    }

    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
