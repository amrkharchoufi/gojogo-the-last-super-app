import SwiftUI

struct OnboardingInterestsView: View {
    @EnvironmentObject var app: AppState
    @State private var appear = false

    private var selectedCount: Int { app.selectedInterestCount }
    private var canFinish: Bool { selectedCount >= 3 }

    var body: some View {
        VStack(spacing: 0) {
            MadeleineBubble {
                (Text("What should fill your feed? ")
                 + Text("Pick at least three.")
                    .foregroundColor(GGColor.textSecondary))
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 14)

            ScrollView(showsIndicators: false) {
                FlowLayout(spacing: 10) {
                    ForEach(app.interests) { interest in
                        InterestChip(interest: interest) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                                app.toggleInterest(interest.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
            .opacity(appear ? 1 : 0)

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Text("\(selectedCount)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedCount)
                    Text(canFinish ? "selected — looking sharp" : "of 3 needed")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(GGColor.textSecondary)
                    Spacer()
                }

                AccentButton(title: "Enter gojogo", trailingArrow: true) {
                    app.finishOnboarding()
                }
                .opacity(canFinish ? 1 : 0.35)
                .disabled(!canFinish)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 16)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) { appear = true }
        }
    }
}

private struct InterestChip: View {
    let interest: Interest
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                if interest.selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(interest.title)
                    .font(.system(size: 15, weight: interest.selected ? .semibold : .medium))
            }
            .foregroundStyle(interest.selected ? Color.black : Color.white.opacity(0.88))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(interest.selected ? Color.white : Color.white.opacity(0.07))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        interest.selected ? Color.clear : Color.white.opacity(0.16),
                        lineWidth: 1)
            )
            .scaleEffect(interest.selected ? 1.03 : 1)
        }
        .buttonStyle(SoftPressStyle())
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: interest.selected)
    }
}

/// Simple wrapping row layout for interest chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                totalHeight = y
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = max(totalHeight, y + rowHeight)
        }
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
