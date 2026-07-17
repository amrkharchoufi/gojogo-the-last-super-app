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

    /// Trait-adaptive color: resolves per the active color scheme.
    init(dark: String, light: String, darkAlpha: Double = 1, lightAlpha: Double = 1) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .light ? light : dark
            let alpha = trait.userInterfaceStyle == .light ? lightAlpha : darkAlpha
            let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            var rgb: UInt64 = 0
            Scanner(string: s).scanHexInt64(&rgb)
            return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                           green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255,
                           alpha: alpha)
        })
    }
}

enum GGColor {
    // Core palette — monochrome, flips with the theme.
    static let black = Color.black
    /// The app's "ink": white in dark mode, near-black in light mode.
    /// Every white capsule CTA / accent fill flips with the theme.
    static let white = Color(dark: "FFFFFF", light: "111114")
    /// Kept name for source compat — resolves to the ink color.
    static let blue = white
    static let red = white
    static let green = Color(dark: "E8E8ED", light: "3A3A3C")

    // Greys
    static let darkGrey = Color(dark: "2C2C2E", light: "E5E5EA")
    static let surface = Color(dark: "1C1C1E", light: "F2F2F7")
    static let surface2 = Color(dark: "2C2C2E", light: "E9E9EC")
    static let hairline = Color(dark: "FFFFFF", light: "000000", darkAlpha: 0.14, lightAlpha: 0.12)

    // Backgrounds
    static let bg = Color(dark: "000000", light: "FAFAFC")
    /// Full-bleed media surfaces (stories, shorts, players) stay dark in both themes.
    static let bgImmersive = Color.black
    static let bgAuth = Color.black
    /// GojoTV browse surface — follows the app theme (players stay immersive).
    static let bgTV = Color(dark: "000000", light: "FAFAFC")
    /// Sheet backdrop.
    static let sheetBG = Color(dark: "121214", light: "F5F5F8")

    // Floating pill chrome (tab bar / dock).
    static let pill = Color(dark: "1F1F21", light: "FFFFFF", darkAlpha: 0.96, lightAlpha: 0.97)
    static let pillBorder = Color(dark: "FFFFFF", light: "000000", darkAlpha: 0.07, lightAlpha: 0.09)

    // Text
    static let textPrimary = Color(dark: "F5F5F7", light: "1C1C1E")
    static let textSecondary = Color(dark: "98989F", light: "6E6E73")
    static let textTertiary = Color(dark: "6A6A70", light: "9B9BA0")

    // Accent + semantics → monochrome
    static let accent = white
    static let accentDeep = Color(dark: "E5E5EA", light: "3A3A3C")
    static let onAccent = Color(dark: "000000", light: "FFFFFF")   // text/icons on an ink fill
    static let success = white

    // Aurora aliases → ink / grey
    static let auroraBlue = white
    static let auroraViolet = white
    static let auroraDeep = Color(dark: "E5E5EA", light: "3A3A3C")
    static let auroraLight = white
    static let auroraTeal = white

    static let glassFill = surface
    static let glassBorder = hairline

    /// Ink at an opacity — replaces `Color.white.opacity(x)` fills so
    /// soft chips/fills stay visible on the light background.
    static func ink(_ opacity: Double) -> Color {
        Color(dark: "FFFFFF", light: "000000",
              darkAlpha: opacity, lightAlpha: min(1, opacity * 0.8))
    }

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
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Call-site tints are dark scrims tuned for dark mode; in light mode
    /// substitute a frosted white so glass reads correctly on a light page.
    private var effectiveTint: Color? {
        guard let tint else { return nil }
        return scheme == .light ? Color.white.opacity(0.72) : tint
    }

    private var borderColor: Color {
        scheme == .light ? Color.black.opacity(0.09) : Color.white.opacity(0.10)
    }

    @available(iOS 26.0, *)
    private func makeGlass() -> Glass {
        let fallback = scheme == .light ? Color.black.opacity(0.03) : Color.white.opacity(0.04)
        var g: Glass = .clear.tint(effectiveTint ?? fallback)
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
                    .overlay(shape.strokeBorder(borderColor, lineWidth: 0.5))
            } else {
                content
                    .clipShape(shape)
                    .background {
                        shape.fill(.ultraThinMaterial.opacity(0.55))
                        shape.fill(GGColor.ink(0.03))
                        if let effectiveTint {
                            shape.fill(effectiveTint)
                        } else {
                            shape.fill(GGColor.surface.opacity(0.35))
                        }
                    }
                    .overlay(shape.strokeBorder(borderColor, lineWidth: 0.5))
            }
        }
        .shadow(color: Color.black.opacity(floating ? (scheme == .light ? 0.16 : 0.4)
                                                    : (scheme == .light ? 0.07 : 0.12)),
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
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var borderColor: Color {
        scheme == .light ? Color.black.opacity(0.10) : Color.white.opacity(0.12)
    }

    @available(iOS 26.0, *)
    private func makeGlass() -> Glass {
        var g: Glass = .clear.tint(scheme == .light ? Color.white.opacity(0.6)
                                                    : Color.white.opacity(0.05))
        if interactive { g = g.interactive() }
        return g
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .clipShape(shape)
                .glassEffect(makeGlass(), in: shape)
                .overlay(shape.strokeBorder(borderColor, lineWidth: 0.5))
                .shadow(color: .black.opacity(scheme == .light ? 0.12 : 0.18), radius: 16, y: 8)
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial.opacity(0.5))
                    if scheme == .light {
                        shape.fill(Color.white.opacity(0.75))
                    } else {
                        shape.fill(Color.white.opacity(0.04))
                        shape.fill(Color.black.opacity(0.12))
                    }
                }
                .overlay(shape.strokeBorder(borderColor, lineWidth: 0.5))
                .clipShape(shape)
                .shadow(color: .black.opacity(scheme == .light ? 0.12 : 0.2), radius: 16, y: 8)
        }
    }
}

struct GlassCapsule: ViewModifier {
    var tint: Color? = nil
    var interactive: Bool = false
    /// Stronger frosted fill — used by the floating tab bar.
    var dense: Bool = false
    @Environment(\.colorScheme) private var scheme

    /// Dark-tuned tints swap to frosted white in light mode.
    private var effectiveTint: Color? {
        if scheme == .light {
            return dense || tint != nil ? Color.white.opacity(0.82) : nil
        }
        return tint
    }

    private var borderColor: Color {
        scheme == .light
            ? Color.black.opacity(dense ? 0.12 : 0.09)
            : Color.white.opacity(dense ? 0.22 : 0.12)
    }

    @available(iOS 26.0, *)
    private func makeGlass() -> Glass {
        let fallbackDark = dense ? Color.black.opacity(0.55) : Color.white.opacity(0.06)
        let fallbackLight = dense ? Color.white.opacity(0.8) : Color.black.opacity(0.04)
        let baseTint = effectiveTint ?? (scheme == .light ? fallbackLight : fallbackDark)
        // `.regular` keeps real Liquid Glass refraction; tint shades it.
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
                    Capsule().strokeBorder(borderColor, lineWidth: dense ? 0.8 : 0.5)
                )
        } else {
            content
                .background {
                    if dense {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(effectiveTint ?? Color.black.opacity(0.55))
                        Capsule().fill(GGColor.ink(0.06))
                    } else {
                        Capsule().fill(.ultraThinMaterial.opacity(0.5))
                        Capsule().fill(GGColor.ink(0.04))
                        if let effectiveTint { Capsule().fill(effectiveTint) }
                    }
                }
                .overlay(
                    Capsule().strokeBorder(borderColor, lineWidth: dense ? 0.8 : 0.5)
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
