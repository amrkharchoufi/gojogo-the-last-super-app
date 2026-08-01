import SwiftUI

// MARK: - Delete account (Phase 2e · Milestone 5)
//
// Two things have to be true of this screen at once: it must be genuinely easy
// to reach (App Store guideline 5.1.1(v) — an account you can create in the app
// must be deletable in the app, without emailing anybody), and it must be
// impossible to arrive at by accident.
//
// So: it is one tap from Settings, and it takes a typed word to fire. And it
// tells the truth about what happens, including the part people most need to
// know — that there are thirty days, and that undoing it inside them means
// asking us, because sign-in closes the instant you confirm.

struct DeleteAccountView: View {
    @EnvironmentObject var app: AppState

    @State private var typed: String = ""
    @FocusState private var focused: Bool

    private let confirmWord = "DELETE"

    var body: some View {
        VStack(spacing: 0) {
            header
            if app.deletionStatus?.pending == true {
                done
            } else {
                form
            }
        }
        .background(GGColor.sheetBG.ignoresSafeArea())
        .interactiveDismissDisabled(app.deleteAccountBusy)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACCOUNT")
                    .font(.ggMono(11, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(GGColor.textSecondary)
                Text("Delete account")
                    .font(.gg(22, .bold))
                    .foregroundStyle(GGColor.textPrimary)
            }
            Spacer()
            if !app.deleteAccountBusy && app.deletionStatus?.pending != true {
                Button { app.showDeleteAccount = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GGColor.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(GGColor.surface))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    point("You'll be signed out immediately",
                          "clock",
                          "Your account closes the moment you confirm. Nobody will be able to sign in to it, including you.")
                    point("You have 30 days to change your mind",
                          "arrow.uturn.backward",
                          "Nothing is destroyed until then. Because sign-in is already closed, getting back in means contacting us — we can't offer a button for it.")
                    point("After that, your name comes off everything",
                          "person.slash",
                          "Your handle, name, photo, email and profile are erased. Posts and messages you were part of stay where they are, credited to a deleted account, so other people's conversations don't develop holes.")
                    point("Purchases and payouts are kept",
                          "doc.text",
                          "Wallet and order records are a financial record we're required to hold on to. They no longer point at you.")

                    if let notice = app.safetyNotice {
                        Text(notice)
                            .font(.gg(13))
                            .foregroundStyle(GGColor.textPrimary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(GGColor.ink(0.06)))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("TYPE \(confirmWord) TO CONFIRM")
                            .font(.ggMono(10, .semibold))
                            .tracking(0.8)
                            .foregroundStyle(GGColor.textTertiary)
                            .padding(.leading, 4)
                        TextField("", text: $typed)
                            .font(.ggMono(16, .semibold))
                            .foregroundStyle(GGColor.textPrimary)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(GGColor.surface))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(GGColor.hairline, lineWidth: 1))
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            confirmButton
        }
    }

    private var confirmButton: some View {
        let armed = typed.trimmingCharacters(in: .whitespaces).uppercased() == confirmWord
        return Button {
            focused = false
            Task { await app.deleteMyAccount() }
        } label: {
            HStack(spacing: 8) {
                if app.deleteAccountBusy { ProgressView().tint(.white) }
                Text(app.deleteAccountBusy ? "Closing your account…" : "Delete my account")
                    .font(.gg(15, .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.red.opacity(armed && !app.deleteAccountBusy ? 0.9 : 0.3)))
        }
        .buttonStyle(PressableStyle())
        .disabled(!armed || app.deleteAccountBusy)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    /// Shown for the couple of seconds between the server accepting and the app
    /// returning to the welcome screen — the date is the one thing worth
    /// reading, and after this there is no signed-in screen to read it on.
    private var done: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(GGColor.textPrimary)
            Text("Your account is closed")
                .font(.gg(18, .semibold))
                .foregroundStyle(GGColor.textPrimary)
            if let ends = app.deletionStatus?.graceEndsAt {
                Text("Everything is erased on \(Self.readable(ends)).")
                    .font(.gg(14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(GGColor.textSecondary)
                    .padding(.horizontal, 40)
            }
            Text("Signing you out…")
                .font(.ggMono(12))
                .foregroundStyle(GGColor.textTertiary)
            Spacer()
        }
    }

    private func point(_ title: String, _ symbol: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(GGColor.ink(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.gg(15, .semibold))
                    .foregroundStyle(GGColor.textPrimary)
                Text(body)
                    .font(.gg(13))
                    .foregroundStyle(GGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func readable(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let out = DateFormatter()
        out.dateStyle = .long
        out.timeStyle = .none
        return out.string(from: date)
    }
}
