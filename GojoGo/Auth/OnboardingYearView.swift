import SwiftUI

struct OnboardingYearView: View {
    @EnvironmentObject var app: AppState
    @State private var appear = false
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    private let minYear = 1940
    private let maxYear = 2012
    private let itemSpacing: CGFloat = 230

    private var year: Int { app.user.birthYear }

    private var age: Int {
        Calendar.current.component(.year, from: Date()) - year
    }

    private var continuousYear: CGFloat {
        CGFloat(year) - dragOffset / itemSpacing
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width

            ZStack {
                VStack(spacing: 18) {
                    yearTrack(width: w)

                    VStack(spacing: 8) {
                        Text("\(age) years old")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.15), value: age)

                        Text("slide · never shown publicly")
                            .font(.ggMono(11, .regular))
                            .foregroundStyle(GGColor.textTertiary)
                    }
                }
                .frame(width: w)
                .opacity(appear ? 1 : 0)

                VStack(alignment: .leading, spacing: 0) {
                    MadeleineBubble {
                        (Text("Nice to meet you. ")
                         + Text("First — when were you born?")
                            .foregroundColor(GGColor.textSecondary))
                    }
                    .padding(.top, 20)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 16)

                    Spacer()

                    AccentButton(title: "That's me", trailingArrow: true) {
                        app.advanceOnboarding()
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 16)
                }
                .frame(width: max(w - 56, 0))
                .padding(.bottom, 36)
            }
            .frame(width: w, height: geo.size.height)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) { appear = true }
        }
    }

    private func yearTrack(width w: CGFloat) -> some View {
        let center = Int(continuousYear.rounded())
        let years = [center - 2, center - 1, center, center + 1, center + 2]
            .filter { $0 >= minYear && $0 <= maxYear }

        return ZStack {
            // Selection rail
            Capsule()
                .fill(Color.white.opacity(0.06))
                .frame(width: 4, height: 88)
                .blur(radius: 0.5)

            ForEach(years, id: \.self) { y in
                let dist = abs(CGFloat(y) - continuousYear)
                yearLabel(y, dist: dist)
                    .offset(x: (CGFloat(y) - continuousYear) * itemSpacing)
                    .zIndex(dist < 0.5 ? 1 : 0)
            }
        }
        .frame(width: w, height: 120)
        .clipped()
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .animation(isDragging ? nil : .spring(response: 0.38, dampingFraction: 0.78),
                   value: year)
    }

    private func yearLabel(_ y: Int, dist: CGFloat) -> some View {
        let t = min(max(dist, 0), 2) / 2
        let scale = 1.0 - (0.38 * t)
        let opacity = dist < 0.35 ? 1.0 : (0.34 - 0.12 * (dist - 1))
        let selected = dist < 0.45

        return Text(String(y))
            .font(.system(size: 100, weight: .heavy))
            .tracking(-5)
            .foregroundStyle(selected ? Color.white : GGColor.textPrimary)
            .opacity(max(0.12, min(1, opacity)))
            .scaleEffect(scale)
            .fixedSize()
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                let raw = value.translation.width
                let next = CGFloat(year) - raw / itemSpacing
                if next < CGFloat(minYear) || next > CGFloat(maxYear) {
                    let overshoot = next < CGFloat(minYear)
                        ? CGFloat(minYear) - next
                        : next - CGFloat(maxYear)
                    dragOffset = raw / (1 + overshoot * 1.4)
                } else {
                    dragOffset = raw
                }
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.width
                let delta = Int((-projected / itemSpacing).rounded())
                let next = min(max(year + delta, minYear), maxYear)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    app.user.birthYear = next
                    dragOffset = 0
                }
            }
    }
}
