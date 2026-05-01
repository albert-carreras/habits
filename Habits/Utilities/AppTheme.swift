import SwiftUI

enum AppPalette: String, CaseIterable, Identifiable, Codable {
    case modern = "Modern"
    case kandinsky = "Kandinsky"
    case mondrian = "Mondrian"
    case albers = "Albers"

    var id: String { rawValue }

    struct Colors {
        let lightBackground: RGB
        let lightSurface: RGB
        let lightBorder: RGB
        let lightText: RGB
        let lightMuted: RGB
        let lightPrimary: RGB
        let lightAccent: RGB
        let lightDanger: RGB

        let darkBackground: RGB
        let darkSurface: RGB
        let darkBorder: RGB
        let darkText: RGB
        let darkMuted: RGB
        let darkPrimary: RGB
        let darkAccent: RGB
        let darkDanger: RGB
    }

    var colors: Colors {
        switch self {
        case .modern:
            return Colors(
                lightBackground: RGB(hex: 0xf8f0df),
                lightSurface: RGB(hex: 0xefe2ca),
                lightBorder: RGB(hex: 0xd2bd96),
                lightText: RGB(hex: 0x1c1721),
                lightMuted: RGB(hex: 0x756f7f),
                lightPrimary: RGB(hex: 0x5a376b),
                lightAccent: RGB(hex: 0xff7a57),
                lightDanger: RGB(hex: 0xd84c34),
                darkBackground: RGB(hex: 0x100b14),
                darkSurface: RGB(hex: 0x1b1223),
                darkBorder: RGB(hex: 0x3a2a45),
                darkText: RGB(hex: 0xf6ead8),
                darkMuted: RGB(hex: 0xb1a2bd),
                darkPrimary: RGB(hex: 0x8e63ad),
                darkAccent: RGB(hex: 0xc8f052),
                darkDanger: RGB(hex: 0xff6b52)
            )
        case .kandinsky:
            return Colors(
                lightBackground: RGB(hex: 0xf5f0e8),
                lightSurface: RGB(hex: 0xe8e0d2),
                lightBorder: RGB(hex: 0xcfc4b0),
                lightText: RGB(hex: 0x1a1a2e),
                lightMuted: RGB(hex: 0x6b6b7b),
                lightPrimary: RGB(hex: 0xe8c820),
                lightAccent: RGB(hex: 0x1b3a8c),
                lightDanger: RGB(hex: 0xc83232),
                darkBackground: RGB(hex: 0x0e0e1c),
                darkSurface: RGB(hex: 0x1a1a30),
                darkBorder: RGB(hex: 0x2e2e4a),
                darkText: RGB(hex: 0xf0ece4),
                darkMuted: RGB(hex: 0x9898b0),
                darkPrimary: RGB(hex: 0x4a7ae8),
                darkAccent: RGB(hex: 0xf0d830),
                darkDanger: RGB(hex: 0xe85050)
            )
        case .mondrian:
            return Colors(
                lightBackground: RGB(hex: 0xf4f1ec),
                lightSurface: RGB(hex: 0xe6e2da),
                lightBorder: RGB(hex: 0xc8c2b6),
                lightText: RGB(hex: 0x1a1a1a),
                lightMuted: RGB(hex: 0x6e6e6e),
                lightPrimary: RGB(hex: 0xcc2222),
                lightAccent: RGB(hex: 0x2244a8),
                lightDanger: RGB(hex: 0xaa1a1a),
                darkBackground: RGB(hex: 0x121210),
                darkSurface: RGB(hex: 0x1e1e1c),
                darkBorder: RGB(hex: 0x3a3a36),
                darkText: RGB(hex: 0xf0ede6),
                darkMuted: RGB(hex: 0xa0a098),
                darkPrimary: RGB(hex: 0xe84040),
                darkAccent: RGB(hex: 0x4466d0),
                darkDanger: RGB(hex: 0xe85050)
            )
        case .albers:
            return Colors(
                lightBackground: RGB(hex: 0xf6f0e4),
                lightSurface: RGB(hex: 0xeae0cc),
                lightBorder: RGB(hex: 0xd0c2a4),
                lightText: RGB(hex: 0x2a2018),
                lightMuted: RGB(hex: 0x7a7060),
                lightPrimary: RGB(hex: 0xb87820),
                lightAccent: RGB(hex: 0xc85420),
                lightDanger: RGB(hex: 0xb83020),
                darkBackground: RGB(hex: 0x12100c),
                darkSurface: RGB(hex: 0x201c14),
                darkBorder: RGB(hex: 0x3e3628),
                darkText: RGB(hex: 0xf2eade),
                darkMuted: RGB(hex: 0xb0a490),
                darkPrimary: RGB(hex: 0xd89830),
                darkAccent: RGB(hex: 0xe07030),
                darkDanger: RGB(hex: 0xe05030)
            )
        }
    }
}

enum AppTheme {
    static let paletteStorageKey = "selectedPalette"
    static let defaultPalette: AppPalette = .modern

    static var currentPalette: AppPalette {
        get {
            palette(from: UserDefaults.standard.string(forKey: paletteStorageKey))
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: paletteStorageKey)
        }
    }

    static func palette(from rawValue: String?) -> AppPalette {
        guard let rawValue, let palette = AppPalette(rawValue: rawValue) else {
            return defaultPalette
        }
        return palette
    }

    private static var c: AppPalette.Colors { currentPalette.colors }

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let full: CGFloat = 9_999
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    enum FontWeight {
        static let semibold: Font.Weight = .semibold
        static let bold: Font.Weight = .bold
        static let heavy: Font.Weight = .heavy
    }

    static let rowCornerRadius = Radius.xl

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? c.darkBackground.color : c.lightBackground.color
    }

    static func card(for scheme: ColorScheme) -> Color {
        surface(for: scheme)
    }

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? c.darkSurface.color : c.lightSurface.color
    }

    static func formField(for scheme: ColorScheme) -> Color {
        surface(for: scheme)
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark ? c.darkBorder.color : c.lightBorder.color
    }

    static func text(for scheme: ColorScheme) -> Color {
        scheme == .dark ? c.darkText.color : c.lightText.color
    }

    static func muted(for scheme: ColorScheme) -> Color {
        scheme == .dark ? c.darkMuted.color : c.lightMuted.color
    }

    static func primary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? c.darkPrimary.color : c.lightPrimary.color
    }

    static func primaryForeground(for scheme: ColorScheme) -> Color {
        let rgb = scheme == .dark ? c.darkPrimary : c.lightPrimary
        return rgb.luminance > 0.78 ? Color.black : Color.white
    }

    static func primarySoft(for scheme: ColorScheme) -> Color {
        primary(for: scheme).opacity(scheme == .dark ? 0.22 : 0.12)
    }

    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? c.darkAccent.color : c.lightAccent.color
    }

    static func accentForeground(for scheme: ColorScheme) -> Color {
        let rgb = scheme == .dark ? c.darkAccent : c.lightAccent
        return rgb.luminance > 0.4 ? Color.black : Color.white
    }

    static func accentSoft(for scheme: ColorScheme) -> Color {
        accent(for: scheme).opacity(scheme == .dark ? 0.14 : 0.10)
    }

    static func danger(for scheme: ColorScheme) -> Color {
        scheme == .dark ? c.darkDanger.color : c.lightDanger.color
    }

    static func dangerSoft(for scheme: ColorScheme) -> Color {
        danger(for: scheme).opacity(scheme == .dark ? 0.14 : 0.08)
    }

    // Convenience aliases for backward compatibility with widget/external code
    static func tag(for scheme: ColorScheme) -> Color { primary(for: scheme) }
    static func tagForeground(for scheme: ColorScheme) -> Color { primaryForeground(for: scheme) }
    static func tagSoft(for scheme: ColorScheme) -> Color { primarySoft(for: scheme) }
    static func success(for scheme: ColorScheme) -> Color { accent(for: scheme) }
    static func successForeground(for scheme: ColorScheme) -> Color { accentForeground(for: scheme) }

    static func backgroundRGB(for scheme: ColorScheme) -> RGB {
        scheme == .dark ? c.darkBackground : c.lightBackground
    }

    static func cardRGB(for scheme: ColorScheme) -> RGB {
        scheme == .dark ? c.darkSurface : c.lightSurface
    }

    static func activeControlRGB(for scheme: ColorScheme) -> RGB {
        scheme == .dark ? c.darkPrimary : c.lightPrimary
    }

    static func accentControlRGB(for scheme: ColorScheme) -> RGB {
        scheme == .dark ? c.darkAccent : c.lightAccent
    }

    static func activeControlForegroundRGB(for scheme: ColorScheme) -> RGB {
        let rgb = scheme == .dark ? c.darkPrimary : c.lightPrimary
        return contrastingForegroundRGB(for: rgb)
    }

    static func contrastingForeground(for background: RGB) -> Color {
        contrastingForegroundRGB(for: background).color
    }

    static func contrastingForegroundRGB(for background: RGB) -> RGB {
        background.luminance > 0.65 ? RGB(hex: 0x000000) : RGB(hex: 0xffffff)
    }
}

struct RGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: Int) {
        red = Double((hex >> 16) & 0xff) / 255
        green = Double((hex >> 8) & 0xff) / 255
        blue = Double(hex & 0xff) / 255
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var luminance: Double {
        (red * 0.2126) + (green * 0.7152) + (blue * 0.0722)
    }

    func blended(over background: RGB, opacity: Double) -> RGB {
        let clampedOpacity = min(max(opacity, 0), 1)
        return RGB(
            red: red * clampedOpacity + background.red * (1 - clampedOpacity),
            green: green * clampedOpacity + background.green * (1 - clampedOpacity),
            blue: blue * clampedOpacity + background.blue * (1 - clampedOpacity)
        )
    }
}

struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color
    let fillOpacity: Double
    let strokeColor: Color
    let strokeWidth: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .background {
                    shape.fill(tint.opacity(fillOpacity))
                }
                .glassEffect(
                    .regular.interactive(interactive),
                    in: shape
                )
        } else {
            content
                .background {
                    shape.fill(tint.opacity(fillOpacity))
                }
                .overlay {
                    shape.stroke(strokeColor, lineWidth: strokeWidth)
                }
        }
    }
}

struct SoftCardModifier<S: Shape>: ViewModifier {
    let shape: S
    let fill: Color
    let strokeColor: Color

    func body(content: Content) -> some View {
        content
            .background(shape.fill(fill))
            .overlay(shape.stroke(strokeColor, lineWidth: 0.5))
    }
}

struct BouncyPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(
                .spring(response: 0.38, dampingFraction: 0.55),
                value: configuration.isPressed
            )
    }
}

extension View {
    func softCard<S: Shape>(
        colorScheme: ColorScheme,
        in shape: S,
        tint: Color? = nil
    ) -> some View {
        let fill = tint ?? AppTheme.card(for: colorScheme)
        let strokeColor = AppTheme.border(for: colorScheme)
        return modifier(SoftCardModifier(shape: shape, fill: fill, strokeColor: strokeColor))
    }

    func liquidGlass<S: Shape>(
        colorScheme: ColorScheme,
        in shape: S,
        tint: Color,
        fillOpacity: Double? = nil,
        interactive: Bool = false
    ) -> some View {
        let resolvedFillOpacity = fillOpacity ?? (colorScheme == .dark ? 0.92 : 0.96)
        let strokeColor = AppTheme.border(for: colorScheme)

        return modifier(
            LiquidGlassModifier(
                shape: shape,
                tint: tint,
                fillOpacity: resolvedFillOpacity,
                strokeColor: strokeColor,
                strokeWidth: 0.5,
                interactive: interactive
            )
        )
    }
}
