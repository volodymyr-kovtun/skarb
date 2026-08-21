import SwiftUI

/// The Skarb mark: the spending donut the overview draws, in four wedges.
///
/// Traced from `frontend/public/icon.svg` — same sweeps, same gaps — but painted from the
/// palette rather than fixed hexes, so it re-tints with the charts instead of going muddy
/// in the dark.
struct Mark: View {
    var size: CGFloat = 48

    /// Each wedge as (start angle, sweep) in degrees, clockwise from the 3 o'clock position.
    private static let wedges: [(start: Double, sweep: Double)] = [
        (-85, 137), (62.1, 94.5), (166.6, 59.7), (236.3, 28.7),
    ]
    private static let colors: [Color] = [Palette.accent, Palette.Chart.c1, Palette.Chart.c2, Palette.Chart.c8]

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let outer = canvasSize.width * 240 / 512
            let inner = canvasSize.width * 144 / 512
            for (index, wedge) in Self.wedges.enumerated() {
                var path = Path()
                path.addArc(
                    center: center, radius: outer,
                    startAngle: .degrees(wedge.start), endAngle: .degrees(wedge.start + wedge.sweep),
                    clockwise: false)
                path.addArc(
                    center: center, radius: inner,
                    startAngle: .degrees(wedge.start + wedge.sweep), endAngle: .degrees(wedge.start),
                    clockwise: true)
                path.closeSubpath()
                context.fill(path, with: .color(Self.colors[index]))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
