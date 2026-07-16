import SwiftUI

struct EmailSignUpView: View {
    @EnvironmentObject var app: AppState
    @FocusState private var focused: Bool
    @State private var appear = false

    private var canContinue: Bool {
        let trimmed = app.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count > 5
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
                            app.phase = .welcome
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
                    Text("Drop your email — I’ll send a one-time code. No password to forget.")
                }
                .padding(.top, 36)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 18)

                Text("Email")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GGColor.textTertiary)
                    .padding(.top, 40)
                    .opacity(appear ? 1 : 0)

                TextField("name@example.com", text: $app.email)
                    .textFieldStyle(.plain)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .padding(.top, 10)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)

                Rectangle()
                    .fill(Color.white.opacity(focused ? 0.55 : 0.18))
                    .frame(height: 1.5)
                    .padding(.top, 14)
                    .animation(.easeOut(duration: 0.2), value: focused)

                Text("We’ll never post without you.")
                    .explanatory(14)
                    .foregroundStyle(GGColor.textTertiary)
                    .padding(.top, 14)
                    .opacity(appear ? 1 : 0)

                Spacer()

                AccentButton(title: "Continue", trailingArrow: true) {
                    submit()
                }
                .disabled(!canContinue)
                .opacity(appear ? (canContinue ? 1 : 0.35) : 0)
                .animation(.easeOut(duration: 0.2), value: canContinue)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.86)) { appear = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
        }
    }

    private func submit() {
        focused = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            app.phase = .onboarding
        }
    }
}
