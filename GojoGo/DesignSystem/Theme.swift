import SwiftUI

// MARK: - Color tokens
// Monochrome palette: black · white · greys. No color accents.

extension Color {
    init(hex: String, alpha: Double = 1) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum GGColor {
    // Core palette — black & white only
    static let black = Color.black
    static let white = Color(hex: "FFFFFF")
    /// Kept name for source compat — resolves to white.
    static let blue = white
    static let red = white
    static let green = Color(hex: "E8E8ED")

    // Greys
    static let darkGrey = Color(hex: "2C2C2E")
    static let surface = Color(hex: "1C1C1E")
    static let surface2 = Color(hex: "2C2C2E")
    static let hairline = Color.white.opacity(0.14)

    // Backgrounds
    static let bg = Color.black
    static let bgImmersive = Color.black
    static let bgAuth = Color.black
    static let bgTV = Color.black

    // Text
    static let textPrimary = Color(hex: "F5F5F7")
    static let textSecondary = Color(hex: "98989F")
    static let textTertiary = Color(hex: "6A6A70")

    // Accent + semantics → monochrome
    static let accent = white
    static let accentDeep = Color(hex: "E5E5EA")
    static let onAccent = Color.black                 // text/icons on a white fill
    static let success = white

    // Aurora aliases → white / light grey
    static let auroraBlue = white
    static let auroraViolet = white
    static let auroraDeep = Color(hex: "E5E5EA")
    static let auroraLight = white
    static let auroraTeal = white

    static let glassFill = surface
    static let glassBorder = hairline

    static let accentGradient = LinearGradient(colors: [white, white],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let auroraCTA = LinearGradient(colors: [white, white],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ringGradient = LinearGradient(colors: [white, white],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Typography
// SF Pro (system default) for UI. New York (system serif) for explanatory copy.

extension Font {
    static func gg(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func ggMono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// New York — Apple's system serif. Used to "explain stuff".
    static func ny(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension Text {
    /// Explanatory / descriptive copy set in New York serif.
    func explanatory(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Text {
        self.font(.ny(size, weight))
    }
}

// MARK: - Ambient background (now flat black)

struct GGBackground: View {
    var base: Color = GGColor.bg
    var glow: Color = .clear      // ignored — no gradients
    var glowY: CGFloat = 0

    var body: some View {
        base.ignoresSafeArea()
    }
}

// MARK: - Liquid Glass surfaces (iOS 26)
// Uses the system Liquid Glass material where available; falls back to a
// solid dark-grey card + hairline on iOS 17–25.

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 22
    var tint: Color? = nil
    var interactive: Bool = false
    var floating: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @available(iOS 26.0, *)
    private func makeGlass() -> Glass {
        var g: Glass = .clear.tint(tint ?? .white.opacity(0.04))
        if interactive { g = g.interactive() }
        return g
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .clipShape(shape)
                    .glassEffect(makeGlass(), in: shape)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            } else {
                content
                    .clipShape(shape)
                    .background {
                        shape.fill(.ultraThinMaterial.opacity(0.55))
                        shape.fill(Color.white.opacity(0.03))
                        if let tint {
                            shape.fill(tint)
                        } else {
                            shape.fill(GGColor.surface.opacity(0.35))
                        }
                    }
                    .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            }
        }
        .shadow(color: floating ? Color.black.opacity(0.4) : Color.black.opacity(0.12),
                radius: floating ? 18 : 10, x: 0, y: floating ? 12 : 4)
    }
}

extension View {
    func glass(cornerRadius: CGFloat = 22,
               fillOpacity: Double = 0.06,     // kept for source compat
               borderOpacity: Double = 0.11,   // kept for source compat
               tint: Color? = nil,
               interactive: Bool = false,
               floating: Bool = false) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius,
                                 tint: tint,
                                 interactive: interactive,
                                 floating: floating))
    }
}

struct LiquidGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 28
    var interactive: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @available(iOS 26.0, *)
    private func makeGlass() -> Glass {
        var g: Glass = .clear.tint(.white.opacity(0.05))
        if interactive { g = g.interactive() }
        return g
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .clipShape(shape)
                .glassEffect(makeGlass(), in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial.opacity(0.5))
                    shape.fill(Color.white.opacity(0.04))
                    shape.fill(Color.black.opacity(0.12))
                }
                .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .clipShape(shape)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        }
    }
}

struct GlassCapsule: ViewModifier {
    var tint: Color? = nil
    var interactive: Bool = false
    /// Stronger frosted fill — used by the floating tab bar.
    var dense: Bool = false

    @available(iOS 26.0, *)
    private func makeGlass() -> Glass {
        let baseTint = tint ?? (dense
            ? Color.black.opacity(0.55)
            : Color.white.opacity(0.06))
        // `.regular` keeps real Liquid Glass refraction; tint shades it charcoal.
        var g: Glass = (dense ? Glass.regular : Glass.clear).tint(baseTint)
        if interactive { g = g.interactive() }
        return g
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(makeGlass(), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        Color.white.opacity(dense ? 0.22 : 0.12),
                        lineWidth: dense ? 0.8 : 0.5)
                )
        } else {
            content
                .background {
                    if dense {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(tint ?? Color.black.opacity(0.55))
                        Capsule().fill(Color.white.opacity(0.06))
                    } else {
                        Capsule().fill(.ultraThinMaterial.opacity(0.5))
                        Capsule().fill(Color.white.opacity(0.04))
                        if let tint { Capsule().fill(tint) }
                    }
                }
                .overlay(
                    Capsule().strokeBorder(
                        Color.white.opacity(dense ? 0.22 : 0.12),
                        lineWidth: dense ? 0.8 : 0.5)
                )
                .clipShape(Capsule())
        }
    }
}

extension View {
    func glassCapsule(fillOpacity: Double = 0.07,
                      borderOpacity: Double = 0.11,
                      tint: Color? = nil,
                      interactive: Bool = false,
                      dense: Bool = false) -> some View {
        modifier(GlassCapsule(tint: tint, interactive: interactive, dense: dense))
    }

    /// Liquid Glass rounded rect — menu sheets, composers, trays.
    func liquidGlass(cornerRadius: CGFloat = 28, interactive: Bool = false) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius, interactive: interactive))
    }
}
