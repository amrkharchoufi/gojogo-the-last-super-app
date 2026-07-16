import SwiftUI

/// Madeleine mark — a solid blue disc with a white SF Symbol.
/// Keeps a subtle pulse (opacity/scale only), no gradients.
struct MadeleineOrb: View {
    var size: CGFloat = 120
    var halo: Bool = true

    @State private var pulse = false

    var body: some View {
        ZStack {
            if halo {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: size * 1.5, height: size * 1.5)
                    .opacity(pulse ? 0.9 : 0.4)
                    .scaleEffect(pulse ? 1.05 : 0.95)
            }
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Color.black)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Small Madeleine mark for avatars / tab bar / chat headers.
struct MiniOrb: View {
    var size: CGFloat = 40
    var glow: Bool = true
    var float: Bool = false
    @State private var offset = false

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.black)
        }
        .frame(width: size, height: size)
        .offset(y: float && offset ? -7 : 0)
        .onAppear {
            guard float else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                offset = true
            }
        }
    }
}

/// Welcome background — flat black, no drifting aurora (kept as a no-op for compat).
struct AuroraBlobs: View {
    var body: some View { Color.clear }
}
