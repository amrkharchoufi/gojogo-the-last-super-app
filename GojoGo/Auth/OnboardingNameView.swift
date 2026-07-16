import SwiftUI

struct OnboardingNameView: View {
    @EnvironmentObject var app: AppState
    @FocusState private var focused: Bool
    @State private var appear = false

    private var name: String { app.user.handle }
    private var isValid: Bool { name.count >= 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MadeleineBubble {
                (Text("Now pick your ")
                 + Text("@name")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                 + Text(" — this is how the room finds you."))
            }
            .padding(.top, 20)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 16)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("@")
                        .foregroundStyle(.white.opacity(0.35))
                    TextField("yourname", text: $app.user.handle)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .foregroundStyle(.white)
                        .tint(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 48, weight: .heavy))
                .tracking(-2.2)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

                Rectangle()
                    .fill(Color.white.opacity(focused ? 0.45 : 0.14))
                    .frame(height: 1.5)
                    .animation(.easeOut(duration: 0.2), value: focused)

                HStack(spacing: 10) {
                    statusPill
                    Spacer()
                    Text("\(name.count)/20")
                        .font(.ggMono(11, .regular))
                        .foregroundStyle(GGColor.textTertiary)
                }

                if !name.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Suggestions")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GGColor.textTertiary)

                        HStack(spacing: 8) {
                            suggestionChip("@\(name).go") {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    app.user.handle = "\(name).go"
                                }
                            }
                            suggestionChip("@its\(name)") {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    app.user.handle = "its\(name)"
                                }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 16)

            Spacer()

            AccentButton(title: "Continue", trailingArrow: true) {
                focused = false
                app.advanceOnboarding()
            }
            .opacity(isValid ? 1 : 0.35)
            .disabled(!isValid)
            .opacity(appear ? 1 : 0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 36)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) { appear = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        }
        .onChange(of: app.user.handle) { _, newValue in
            let filtered = String(newValue
                .lowercased()
                .filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
                .prefix(20))
            if filtered != newValue {
                app.user.handle = filtered
            }
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if name.isEmpty {
            Text("at least 3 characters")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textTertiary)
        } else if isValid {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                Text("@\(name) is free")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
        } else {
            Text("Keep going…")
                .font(.system(size: 13))
                .foregroundStyle(GGColor.textTertiary)
        }
    }

    private func suggestionChip(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                )
        }
        .buttonStyle(SoftPressStyle())
    }
}
