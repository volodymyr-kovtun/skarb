import SwiftUI

/// A stored `#rrggbb` from the API, made legible in the current appearance.
///
/// This is `frontend/src/shared/color.ts` in Swift: categories, tags and accounts carry a hue
/// the owner picked on the web, and a hue that reads well on paper disappears on a dark
/// surface. Nothing renders a stored color directly — it comes through here first and lands
/// inside the lightness band that stays readable against whichever background is up.
enum HSL {
    /// The band a stored color is allowed to occupy, per appearance.
    private static let lightBand: ClosedRange<Double> = 0.26...0.44
    private static let darkBand: ClosedRange<Double> = 0.62...0.78

    static func rgb(fromHex hex: String) -> (r: Int, g: Int, b: Int)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF))
    }

    private static func toHSL(_ rgb: (r: Int, g: Int, b: Int)) -> (h: Double, s: Double, l: Double) {
        let r = Double(rgb.r) / 255, g = Double(rgb.g) / 255, b = Double(rgb.b) / 255
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        let d = maxV - minV
        guard d != 0 else { return (0, 0, l) }

        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        let h: Double
        switch maxV {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        return (h * 60, s, l)
    }

    private static func toRGB(h: Double, s: Double, l: Double) -> (r: Double, g: Double, b: Double) {
        guard s != 0 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        let hk = h / 360
        return (channel(hk + 1 / 3), channel(hk), channel(hk - 1 / 3))
    }

    private static func normalized(_ hex: String, dark: Bool) -> Color? {
        guard let rgb = rgb(fromHex: hex) else { return nil }
        let hsl = toHSL(rgb)
        let band = dark ? darkBand : lightBand
        // A grey stays grey — pushing saturation onto it would invent a hue.
        let s = hsl.s == 0 ? 0 : min(max(hsl.s, 0.22), 0.62)
        let out = toRGB(h: hsl.h, s: s, l: min(max(hsl.l, band.lowerBound), band.upperBound))
        return Color(red: out.r, green: out.g, blue: out.b)
    }

    /// A stored color, made legible: dots, chart fills, bars and colored text.
    static func swatch(_ hex: String) -> Color {
        Color(UIColor { trait in
            let dark = trait.userInterfaceStyle == .dark
            let color = normalized(hex, dark: dark) ?? Palette.uncategorized
            return UIColor(color)
        })
    }

    /// The same color as a background wash, for chips and icon tiles.
    static func tint(_ hex: String) -> Color {
        Color(UIColor { trait in
            let dark = trait.userInterfaceStyle == .dark
            let color = normalized(hex, dark: dark) ?? Palette.uncategorized
            return UIColor(color).withAlphaComponent(dark ? 0.24 : 0.14)
        })
    }
}
