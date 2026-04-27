import SwiftUI

enum WidgetTheme {
    static let darkAccent = Color(red: 232.0 / 255, green: 160.0 / 255, blue: 32.0 / 255)
    static let darkBorder = Color(red: 31.0 / 255, green: 56.0 / 255, blue: 40.0 / 255)
    static let darkMuted = Color(red: 90.0 / 255, green: 136.0 / 255, blue: 112.0 / 255)
    static let darkTag = Color(red: 64.0 / 255, green: 176.0 / 255, blue: 136.0 / 255)

    static let lightAccent = Color(red: 30.0 / 255, green: 74.0 / 255, blue: 56.0 / 255)
    static let lightBorder = Color(red: 204.0 / 255, green: 196.0 / 255, blue: 168.0 / 255)
    static let lightMuted = Color(red: 106.0 / 255, green: 120.0 / 255, blue: 96.0 / 255)
    static let lightTag = Color(red: 232.0 / 255, green: 160.0 / 255, blue: 32.0 / 255)

    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkAccent : lightAccent
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBorder : lightBorder
    }

    static func muted(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkMuted : lightMuted
    }

    static func tag(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkTag : lightTag
    }
}
