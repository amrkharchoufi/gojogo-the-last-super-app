import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var app: AppState
    @State private var appear = false

    private let circleSize: CGFloat = 58

    var body: some View {
        ZStack {
            GGColor.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Text recreation of the brand mark: white “gojo” + teal “go”
                Wordmark(size: 44)
                    .tracking(-1.8)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 8)
                    .animation(.easeOut(duration: 0.65), value: appear)

                Spacer(minLength: 0)

                VStack(spacing: 28) {
                    HStack(spacing: 26) {
                        authCircle {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white)
                        } action: {
                            // Native Sign in with Apple → backend token exchange.
                            app.signInWithApple()
                        }

                        authCircle {
                            GoogleMark()
                                .frame(width: 22, height: 22)
                        } action: {
                            // Google via Cognito Hosted UI (ASWebAuthenticationSession).
                            app.signInWithGoogle()
                        }

                        authCircle {
                            Image(systemName: "envelope")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(.white)
                        } action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                app.phase = .email
                            }
                        }
                    }
                    .opacity(app.authBusy ? 0.35 : 1)
                    .disabled(app.authBusy)

                    if let error = app.authError {
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "FF7A7A"))
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }

                    legalFooter
                }
                .padding(.bottom, 28)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 10)
                .animation(.easeOut(duration: 0.6).delay(0.12), value: appear)
            }

            if app.authBusy {
                ZStack {
                    GGColor.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.3)
                        Text("Signing you in…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(GGColor.textSecondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.authBusy)
        .animation(.easeInOut(duration: 0.25), value: app.authError)
        .onAppear { appear = true }
    }

    private var legalFooter: some View {
        VStack(spacing: 2) {
            Text("By continuing, you agree to our")
                .foregroundStyle(GGColor.textTertiary)

            HStack(spacing: 4) {
                Button("Terms of Service") {}
                    .buttonStyle(.plain)
                    .underline()
                    .foregroundStyle(GGColor.textSecondary)

                Text("and")
                    .foregroundStyle(GGColor.textTertiary)

                Button("Privacy Policy") {}
                    .buttonStyle(.plain)
                    .underline()
                    .foregroundStyle(GGColor.textSecondary)
            }
        }
        .font(.system(size: 12))
        .multilineTextAlignment(.center)
    }

    private func authCircle<Label: View>(
        @ViewBuilder label: () -> Label,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label()
                .frame(width: circleSize, height: circleSize)
                .liquidGlass(cornerRadius: circleSize / 2, interactive: true)
        }
        .buttonStyle(SoftPressStyle())
    }
}

/// Compact Google “G” mark for auth circles.
private struct GoogleMark: View {
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "4285F4"),
                            Color(hex: "34A853"),
                            Color(hex: "FBBC05"),
                            Color(hex: "EA4335"),
                            Color(hex: "4285F4")
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .butt)
                )
                .rotationEffect(.degrees(-20))

            // Right-side bar of the G
            Capsule()
                .fill(Color(hex: "4285F4"))
                .frame(width: 10, height: 3.2)
                .offset(x: 5.5)
        }
        .frame(width: 20, height: 20)
    }
}
