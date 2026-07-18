import SwiftUI

// MARK: - Wordmark  "gojogo" with tinted trailing "go"

struct Wordmark: View {
    /// Brand teal used for the muted trailing segment (matches welcome).
    static let brandTrailing = Color(hex: "00E5C7")

    var size: CGFloat = 19
    var trailing: String = "go"
    var accentGradient: Bool = false   // kept for source compat
    /// Override trailing tint; defaults to brand teal.
    var trailingColor: Color? = nil

    var body: some View {
        HStack(spacing: 0) {
            Text("gojo").foregroundStyle(GGColor.textPrimary)
            Text(trailing).foregroundStyle(trailingColor ?? Self.brandTrailing)
        }
        .font(.system(size: size, weight: .bold))
        .tracking(-0.4)
    }
}

// MARK: - Striped media placeholder (solid dark grey + hatch)

struct StripePattern: View {
    var spacing: CGFloat = 20
    var color: Color = Color.white.opacity(0.035)

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let w = size.width, h = size.height
                let step = spacing
                var x = -h
                var path = Path()
                while x < w + h {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + h, y: h))
                    x += step
                }
                context.stroke(path, with: .color(color), lineWidth: step / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct MediaPlaceholder: View {
    var gradient: [Color] = []       // ignored — solid grey now (kept for source compat)
    var label: String? = nil
    var cornerRadius: CGFloat = 16
    var icon: String? = nil

    var body: some View {
        ZStack {
            GGColor.surface2
            StripePattern()
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(GGColor.textTertiary)
            } else if let label {
                Text(label)
                    .font(.ggMono(10, .regular))
                    .foregroundStyle(GGColor.textTertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Avatar (solid dark grey circle, optional blue story ring)

struct AvatarBlob: View {
    var size: CGFloat = 32
    var gradient: [Color] = []       // ignored — kept for source compat
    var letter: String? = nil
    var ring: Bool = false

    var body: some View {
        Group {
            if ring {
                Circle()
                    .fill(GGColor.blue)
                    .padding(-2)
                    .overlay(inner)
                    .frame(width: size, height: size)
            } else {
                inner.frame(width: size, height: size)
            }
        }
    }

    private var inner: some View {
        Circle()
            .fill(GGColor.surface2)
            .overlay {
                if let letter {
                    Text(letter)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(GGColor.textPrimary)
                }
            }
            .overlay(ring ? Circle().strokeBorder(GGColor.bg, lineWidth: 3) : nil)
    }
}

// MARK: - Accent button (solid blue)

struct AccentButton: View {
    var title: String
    var trailingArrow: Bool = false
    var gradient: LinearGradient = GGColor.accentGradient   // resolves flat blue
    var glow: Color = .clear
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if trailingArrow {
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(GGColor.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(GGColor.white))
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Theme toggle

struct ThemeToggleButton: View {
    @EnvironmentObject var app: AppState
    var size: CGFloat = 20

    var body: some View {
        Button {
            app.toggleTheme()
        } label: {
            Image(systemName: app.appTheme == .dark ? "sun.max" : "moon.fill")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(GGColor.textPrimary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.appTheme == .dark ? "Switch to light mode" : "Switch to dark mode")
    }
}

// MARK: - Mono chip / pill

struct MonoChip: View {
    var text: String
    var active: Bool = false
    var body: some View {
        Text(text)
            .font(.ggMono(11, .medium))
            .foregroundStyle(active ? GGColor.blue : GGColor.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule().fill(active ? GGColor.blue.opacity(0.15) : GGColor.darkGrey)
            )
            .overlay(
                Capsule().strokeBorder(
                    active ? GGColor.blue.opacity(0.5) : GGColor.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Section header

struct SectionHeader: View {
    var title: String
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(GGColor.textSecondary)
            .tracking(0.3)
    }
}
