import SwiftUI

struct ProgressDots: View {
    let step: Int   // 1...3
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.white : Color.white.opacity(0.18))
                    .frame(width: i == step ? 28 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
    }
}

struct MadeleineBubble<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MiniOrb(size: 38, float: true)
                .frame(width: 38, height: 38)
            content
                .font(.ny(17))
                .foregroundStyle(GGColor.textPrimary)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: 6, bottomLeading: 20,
                                           bottomTrailing: 20, topTrailing: 20),
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: 6, bottomLeading: 20,
                                           bottomTrailing: 20, topTrailing: 20),
                        style: .continuous
                    )
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .frame(maxWidth: 340, alignment: .leading)
    }
}

struct OnboardingFlow: View {
    @EnvironmentObject var app: AppState

    private var stepTitle: String {
        switch app.onboardingStep {
        case 1: return "Birth year"
        case 2: return "Your name"
        default: return "Your taste"
        }
    }

    var body: some View {
        ZStack {
            GGColor.black.ignoresSafeArea()

            // Soft stage light
            EllipticalGradient(
                colors: [Color.white.opacity(0.07), Color.clear],
                center: .topLeading,
                startRadiusFraction: 0.05,
                endRadiusFraction: 0.7
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 4)

                Group {
                    switch app.onboardingStep {
                    case 1: OnboardingYearView()
                    case 2: OnboardingNameView()
                    default: OnboardingInterestsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(app.onboardingStep)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: app.onboardingStep)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .glassCapsule(interactive: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(stepTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("0\(app.onboardingStep) / 03")
                        .font(.ggMono(11, .medium))
                        .foregroundStyle(GGColor.textTertiary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * CGFloat(app.onboardingStep) / 3)
                            .animation(.spring(response: 0.45, dampingFraction: 0.85),
                                       value: app.onboardingStep)
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func goBack() {
        if app.onboardingStep > 1 {
            app.onboardingStep -= 1
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                app.phase = .welcome
            }
        }
    }
}
