import SwiftUI
import Testing
@testable import Habits

@Suite("App Theme")
struct AppThemeTests {

    @Test("Card surfaces contrast with app backgrounds")
    func cardSurfaceContrast() {
        for scheme in [ColorScheme.light, .dark] {
            let background = AppTheme.backgroundRGB(for: scheme)
            let card = AppTheme.cardRGB(for: scheme)

            #expect(abs(background.luminance - card.luminance) >= 0.03)
        }
    }

    @Test("Theme colors match the design system tokens")
    func designSystemColorTokens() {
        assertRGB(AppTheme.lightBackgroundRGB, equals: RGB(hex: 0xf4efe0))
        assertRGB(AppTheme.lightSurfaceRGB, equals: RGB(hex: 0xece6d4))
        assertRGB(AppTheme.lightSurfaceHiRGB, equals: RGB(hex: 0xe4ddc8))
        assertRGB(AppTheme.lightBorderRGB, equals: RGB(hex: 0xccc4a8))
        assertRGB(AppTheme.lightTextRGB, equals: RGB(hex: 0x132018))
        assertRGB(AppTheme.lightMutedRGB, equals: RGB(hex: 0x6a7860))
        assertRGB(AppTheme.lightAccentRGB, equals: RGB(hex: 0x1e4a38))
        assertRGB(AppTheme.lightTagRGB, equals: RGB(hex: 0xe8a020))
        assertRGB(AppTheme.lightDangerRGB, equals: RGB(hex: 0xc94428))

        assertRGB(AppTheme.darkBackgroundRGB, equals: RGB(hex: 0x0b1812))
        assertRGB(AppTheme.darkSurfaceRGB, equals: RGB(hex: 0x122119))
        assertRGB(AppTheme.darkSurfaceHiRGB, equals: RGB(hex: 0x172a20))
        assertRGB(AppTheme.darkBorderRGB, equals: RGB(hex: 0x1f3828))
        assertRGB(AppTheme.darkTextRGB, equals: RGB(hex: 0xf0ead8))
        assertRGB(AppTheme.darkMutedRGB, equals: RGB(hex: 0x5a8870))
        assertRGB(AppTheme.darkAccentRGB, equals: RGB(hex: 0xe8a020))
        assertRGB(AppTheme.darkTagRGB, equals: RGB(hex: 0x40b088))
        assertRGB(AppTheme.darkDangerRGB, equals: RGB(hex: 0xc94428))
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

    private func assertRGB(_ actual: RGB, equals expected: RGB) {
        #expect(abs(actual.red - expected.red) < 0.0001)
        #expect(abs(actual.green - expected.green) < 0.0001)
        #expect(abs(actual.blue - expected.blue) < 0.0001)
    }
}
