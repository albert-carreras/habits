import SwiftUI
import Testing
@testable import Habits

@Suite("App Theme")
struct AppThemeTests {

    @Test("Card surfaces contrast with app backgrounds for all palettes")
    func cardSurfaceContrast() {
        for palette in AppPalette.allCases {
            let colors = palette.colors
            for (bg, card) in [
                (colors.lightBackground, colors.lightSurface),
                (colors.darkBackground, colors.darkSurface)
            ] {
                #expect(abs(bg.luminance - card.luminance) >= 0.03)
            }
        }
    }

    @Test("Modern palette colors match the design tokens")
    func modernPaletteTokens() {
        let c = AppPalette.modern.colors
        assertRGB(c.lightBackground, equals: RGB(hex: 0xf8f0df))
        assertRGB(c.lightSurface, equals: RGB(hex: 0xefe2ca))
        assertRGB(c.lightBorder, equals: RGB(hex: 0xd2bd96))
        assertRGB(c.lightText, equals: RGB(hex: 0x1c1721))
        assertRGB(c.lightMuted, equals: RGB(hex: 0x756f7f))
        assertRGB(c.lightPrimary, equals: RGB(hex: 0x5a376b))
        assertRGB(c.lightAccent, equals: RGB(hex: 0xff7a57))
        assertRGB(c.lightDanger, equals: RGB(hex: 0xd84c34))

        assertRGB(c.darkBackground, equals: RGB(hex: 0x100b14))
        assertRGB(c.darkSurface, equals: RGB(hex: 0x1b1223))
        assertRGB(c.darkBorder, equals: RGB(hex: 0x3a2a45))
        assertRGB(c.darkText, equals: RGB(hex: 0xf6ead8))
        assertRGB(c.darkMuted, equals: RGB(hex: 0xb1a2bd))
        assertRGB(c.darkPrimary, equals: RGB(hex: 0x8e63ad))
        assertRGB(c.darkAccent, equals: RGB(hex: 0xc8f052))
        assertRGB(c.darkDanger, equals: RGB(hex: 0xff6b52))
    }

    @Test("All palettes have 8 color roles per scheme")
    func allPalettesHaveCorrectRoles() {
        for palette in AppPalette.allCases {
            let c = palette.colors
            #expect(c.lightBackground.luminance >= 0)
            #expect(c.lightSurface.luminance >= 0)
            #expect(c.lightBorder.luminance >= 0)
            #expect(c.lightText.luminance >= 0)
            #expect(c.lightMuted.luminance >= 0)
            #expect(c.lightPrimary.luminance >= 0)
            #expect(c.lightAccent.luminance >= 0)
            #expect(c.lightDanger.luminance >= 0)
            #expect(c.darkBackground.luminance >= 0)
            #expect(c.darkSurface.luminance >= 0)
            #expect(c.darkBorder.luminance >= 0)
            #expect(c.darkText.luminance >= 0)
            #expect(c.darkMuted.luminance >= 0)
            #expect(c.darkPrimary.luminance >= 0)
            #expect(c.darkAccent.luminance >= 0)
            #expect(c.darkDanger.luminance >= 0)
        }
    }

    @Test("Theme spacing and radius tokens match the design system")
    func designSystemLayoutTokens() {
        #expect(AppTheme.Radius.xs == 4)
        #expect(AppTheme.Radius.sm == 10)
        #expect(AppTheme.Radius.md == 14)
        #expect(AppTheme.Radius.lg == 16)
        #expect(AppTheme.Radius.xl == 20)
        #expect(AppTheme.Radius.xxl == 24)
        #expect(AppTheme.Radius.full == 9_999)

        #expect(AppTheme.Spacing.xs == 4)
        #expect(AppTheme.Spacing.sm == 8)
        #expect(AppTheme.Spacing.md == 12)
        #expect(AppTheme.Spacing.lg == 16)
        #expect(AppTheme.Spacing.xl == 20)
        #expect(AppTheme.Spacing.xxl == 24)
        #expect(AppTheme.Spacing.xxxl == 32)
    }

    @Test("Palette persistence round-trips through UserDefaults")
    func palettePersistence() {
        let original = AppTheme.currentPalette
        defer { AppTheme.currentPalette = original }

        for palette in AppPalette.allCases {
            AppTheme.currentPalette = palette
            #expect(AppTheme.currentPalette == palette)
        }
    }

    @Test("Palette resolver falls back to the default palette")
    func paletteResolverFallback() {
        #expect(AppTheme.palette(from: nil) == AppTheme.defaultPalette)
        #expect(AppTheme.palette(from: "Not a palette") == AppTheme.defaultPalette)
        #expect(AppTheme.palette(from: AppPalette.mondrian.rawValue) == .mondrian)
    }

    @Test("Tag and success aliases resolve to primary and accent")
    func semanticAliases() {
        for scheme in [ColorScheme.light, .dark] {
            #expect(AppTheme.tag(for: scheme) == AppTheme.primary(for: scheme))
            #expect(AppTheme.tagForeground(for: scheme) == AppTheme.primaryForeground(for: scheme))
            #expect(AppTheme.success(for: scheme) == AppTheme.accent(for: scheme))
        }
    }

    @Test("Contrasting foreground follows background brightness")
    func contrastingForeground() {
        #expect(AppTheme.contrastingForegroundRGB(for: RGB(hex: 0x111111)) == RGB(hex: 0xffffff))
        #expect(AppTheme.contrastingForegroundRGB(for: RGB(hex: 0xf7f7f7)) == RGB(hex: 0x000000))

        let blendedDarkControl = RGB(hex: 0x8e63ad).blended(over: RGB(hex: 0x100b14), opacity: 0.68)
        #expect(AppTheme.contrastingForegroundRGB(for: blendedDarkControl) == RGB(hex: 0xffffff))
    }

    private func assertRGB(_ actual: RGB, equals expected: RGB) {
        #expect(abs(actual.red - expected.red) < 0.0001)
        #expect(abs(actual.green - expected.green) < 0.0001)
        #expect(abs(actual.blue - expected.blue) < 0.0001)
    }
}
