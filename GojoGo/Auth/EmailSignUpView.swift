import SwiftUI

struct EmailSignUpView: View {
    @EnvironmentObject var app: AppState
    @FocusState private var focusedField: Field?
    @State private var appear = false

    enum Field { case email, password, code }

    private var canContinue: Bool {
        switch app.emailAuthStep {
        case .credentials:
            let trimmed = app.email.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.contains("@") && trimmed.contains(".") && trimmed.count > 5
                && app.authPassword.count >= 8
        case .code:
            return app.authCode.trimmingCharacters(in: .whitespaces).count >= 4
        }
    }

    var body: some View {
        ZStack {
            GGColor.black.ignoresSafeArea()

            // Quiet atmosphere
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 380, height: 380)
                .blur(radius: 70)
                .offset(x: 100, y: -260)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                            if app.emailAuthStep == .code {
                                app.emailAuthStep = .credentials
                                app.authError = nil
                            } else {
                                app.phase = .welcome
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 36, height: 36)
                            .glassCapsule(interactive: true)
                    }
                    Spacer()
                    Text("1 of 4")
                        .font(.ggMono(12, .medium))
                        .foregroundStyle(GGColor.textTertiary)
                }
                .opacity(appear ? 1 : 0)

                MadeleineBubble {
                    Text(app.emailAuthStep == .credentials
                         ? "Email and a password — if you're new I'll email you a code, if not you're straight in."
                         : "Check \(app.email) — I sent you a 6-digit code.")
                }
                .padding(.top, 36)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 18)

                if app.emailAuthStep == .credentials {
                    credentialFields
                } else {
                    codeField
                }

                if let error = app.authError {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "FF7A7A"))
                        .padding(.top, 14)
                        .transition(.opacity)
                }

                Spacer()

                AccentButton(title: app.authBusy ? "One sec…" : "Continue", trailingArrow: !app.authBusy) {
                    submit()
                }
                .disabled(!canContinue || app.authBusy)
                .opacity(appear ? (canContinue && !app.authBusy ? 1 : 0.35) : 0)
                .animation(.easeOut(duration: 0.2), value: canContinue)
                .animation(.easeOut(duration: 0.2), value: app.authBusy)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .animation(.easeInOut(duration: 0.25), value: app.authError)
        .animation(.easeInOut(duration: 0.3), value: app.emailAuthStep)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.86)) { appear = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focusedField = .email }
        }
        .onChange(of: app.emailAuthStep) { _, step in
            focusedField = step == .code ? .code : .email
        }
    }

    private var credentialFields: some View {
        Group {
            Text("Email")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textTertiary)
                .padding(.top, 36)

            TextField("name@example.com", text: $app.email)
                .textFieldStyle(.plain)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.top, 8)

            underline(active: focusedField == .email)

            Text("Password")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textTertiary)
                .padding(.top, 26)

            SecureField("8+ characters, incl. a number", text: $app.authPassword)
                .textFieldStyle(.plain)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { if canContinue { submit() } }
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.top, 8)

            underline(active: focusedField == .password)

            Text("We'll never post without you.")
                .explanatory(14)
                .foregroundStyle(GGColor.textTertiary)
                .padding(.top, 14)
        }
        .opacity(appear ? 1 : 0)
    }

    private var codeField: some View {
        Group {
            Text("Verification code")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GGColor.textTertiary)
                .padding(.top, 40)

            TextField("123456", text: $app.authCode)
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .code)
                .font(.system(size: 34, weight: .semibold))
                .tracking(6)
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.top, 10)

            underline(active: focusedField == .code)

            Button {
                app.resendAuthCode()
            } label: {
                Text("Resend code")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GGColor.textSecondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .opacity(appear ? 1 : 0)
    }

    private func underline(active: Bool) -> some View {
        Rectangle()
            .fill(Color.white.opacity(active ? 0.55 : 0.18))
            .frame(height: 1.5)
            .padding(.top, 12)
            .animation(.easeOut(duration: 0.2), value: active)
    }

    private func submit() {
        focusedField = nil
        switch app.emailAuthStep {
        case .credentials: app.submitEmailCredentials()
        case .code: app.submitConfirmationCode()
        }
    }
}
