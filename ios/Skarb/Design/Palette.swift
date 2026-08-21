import SwiftUI

/// Skarb's palette, ported one-for-one from `frontend/src/index.css`. Only this file knows a
/// hex code — everything else reads a named token, so the two apps can only drift on purpose.
enum Palette {
    static let paper = dynamic(light: 0xF2EFE9, dark: 0x171410)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x221E18)
    static let surface2 = dynamic(light: 0xF8F5F0, dark: 0x1D1914)
    static let line = dynamic(light: 0xE8E2D6, dark: 0x322C23)
    static let hover = dynamic(light: 0xF6F3ED, dark: 0x2A251E)

    static let ink = dynamic(light: 0x211D18, dark: 0xF4EEE4)
    static let muted = dynamic(light: 0x5B544A, dark: 0xA69B8B)
    static let faint = dynamic(light: 0x746C5E, dark: 0x948B7C)

    static let accent = dynamic(light: 0xAF5229, dark: 0xE08A5B)
    static let income = dynamic(light: 0x437051, dark: 0x7CB794)
    static let spend = dynamic(light: 0x8A6A9E, dark: 0xBA9BD2)
    static let danger = dynamic(light: 0xB0322A, dark: 0xEF9A93)

    /// The wedge that stands for "no category" — and for the chart's "Other" catch-all.
    static let uncategorized = dynamic(light: 0x91897C, dark: 0x716C64)

    /// Radii, straight from the web's `--radius-*` tokens.
    enum Radius {
        static let card: CGFloat = 22
        static let row: CGFloat = 14
        static let tile: CGFloat = 13
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}

extension Color {
    /// Parses the `#rrggbb` strings the API stores for categories, tags and accounts.
    /// Anything unparseable falls back to the uncategorized grey rather than crashing a row.
    init(hexString: String) {
        guard let rgb = HSL.rgb(fromHex: hexString) else {
            self = Palette.uncategorized
            return
        }
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

extension Palette {
    /// The eight chart hues, tuned per appearance — the same family the web charts draw from.
    enum Chart {
        static let c1 = Palette.hue(light: 0x775B88, dark: 0xBA9BD2)
        static let c2 = Palette.hue(light: 0x426F50, dark: 0x7CB794)
        static let c3 = Palette.hue(light: 0x9F4B25, dark: 0xE08A5B)
        static let c4 = Palette.hue(light: 0x546783, dark: 0x92AAD1)
        static let c5 = Palette.hue(light: 0x974D6E, dark: 0xD18BA8)
        static let c6 = Palette.hue(light: 0x456D67, dark: 0x7FB4AC)
        static let c7 = Palette.hue(light: 0x91897C, dark: 0x716C64)
        static let c8 = Palette.hue(light: 0x7B6230, dark: 0xC9A560)
    }

    /// The eight hues the design is built from, so a color picked on the phone always belongs.
    static let accountColors = [
        "#775B88", "#426F50", "#9F4B25", "#546783", "#974D6E", "#456D67", "#7B6230", "#91897C",
    ]
    static let categoryColors = [
        "#426F50", "#9F4B25", "#546783", "#974D6E", "#775B88", "#456D67",
        "#B0322A", "#7B6230", "#2F7168", "#5A5F9E", "#91897C", "#6B6559",
        "#3F7A5C", "#6B7A38", "#A06A24", "#8A4A20", "#7A5A2A", "#211D18",
    ]

    fileprivate static func hue(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}
