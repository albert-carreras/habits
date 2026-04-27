import SwiftUI

enum AppTheme {
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

    static let lightBackgroundRGB = RGB(hex: 0xf4efe0)
    static let lightSurfaceRGB = RGB(hex: 0xece6d4)
    static let lightSurfaceHiRGB = RGB(hex: 0xe4ddc8)
    static let lightBorderRGB = RGB(hex: 0xccc4a8)
    static let lightTextRGB = RGB(hex: 0x132018)
    static let lightMutedRGB = RGB(hex: 0x6a7860)
    static let lightAccentRGB = RGB(hex: 0x1e4a38)
    static let lightAccentFgRGB = RGB(hex: 0xf4efe0)
    static let lightTagRGB = RGB(hex: 0xe8a020)
    static let lightTagFgRGB = RGB(hex: 0x132018)
    static let lightDangerRGB = RGB(hex: 0xc94428)

    static let darkBackgroundRGB = RGB(hex: 0x0b1812)
    static let darkSurfaceRGB = RGB(hex: 0x122119)
    static let darkSurfaceHiRGB = RGB(hex: 0x172a20)
    static let darkBorderRGB = RGB(hex: 0x1f3828)
    static let darkTextRGB = RGB(hex: 0xf0ead8)
    static let darkMutedRGB = RGB(hex: 0x5a8870)
    static let darkAccentRGB = RGB(hex: 0xe8a020)
    static let darkAccentFgRGB = RGB(hex: 0x0b1812)
    static let darkTagRGB = RGB(hex: 0x40b088)
    static let darkTagFgRGB = RGB(hex: 0x0b1812)
    static let darkDangerRGB = RGB(hex: 0xc94428)

    static let lightBackground = lightBackgroundRGB.color
    static let lightCard = lightSurfaceRGB.color
    static let lightAccent = lightAccentRGB.color

    static let darkBackground = darkBackgroundRGB.color
    static let darkCard = darkSurfaceRGB.color
    static let darkAccent = darkAccentRGB.color

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBackground : lightBackground
    }

    static func card(for scheme: ColorScheme) -> Color {
        surface(for: scheme)
    }

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSurfaceRGB.color : lightSurfaceRGB.color
    }

    static func surfaceHi(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSurfaceHiRGB.color : lightSurfaceHiRGB.color
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBorderRGB.color : lightBorderRGB.color
    }

    static func text(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkTextRGB.color : lightTextRGB.color
    }

    static func muted(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkMutedRGB.color : lightMutedRGB.color
    }

    static func formField(for scheme: ColorScheme) -> Color {
        surfaceHi(for: scheme)
    }

    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkAccent : lightAccent
    }

    static func accentForeground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkAccentFgRGB.color : lightAccentFgRGB.color
    }

    static func accentSoft(for scheme: ColorScheme) -> Color {
        accent(for: scheme).opacity(scheme == .dark ? 0.14 : 0.10)
    }

    static func tag(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkTagRGB.color : lightTagRGB.color
    }

    static func tagForeground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkTagFgRGB.color : lightTagFgRGB.color
    }

    static func danger(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkDangerRGB.color : lightDangerRGB.color
    }

    static func dangerSoft(for scheme: ColorScheme) -> Color {
        danger(for: scheme).opacity(scheme == .dark ? 0.14 : 0.08)
    }

    static func backgroundRGB(for scheme: ColorScheme) -> RGB {
        scheme == .dark ? darkBackgroundRGB : lightBackgroundRGB
    }

    static func cardRGB(for scheme: ColorScheme) -> RGB {
        scheme == .dark ? darkSurfaceRGB : lightSurfaceRGB
    }
}

struct RGB {
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
}

struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color
    let fillOpacity: Double
    let strokeColor: Color
    let strokeWidth: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular.tint(tint.opacity(fillOpacity)).interactive(interactive),
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
