import CoreImage.CIFilterBuiltins
import SwiftUI

/// Inline error, sized to sit under a field without shifting the card around.
struct FormError: View {
    let message: String

    init(_ message: String) { self.message = message }

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Palette.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.danger.opacity(0.1), in: .rect(cornerRadius: Palette.Radius.row))
            .accessibilityAddTraits(.isStaticText)
    }
}

/// What a control reports back in a line under itself.
nonisolated struct StatusMessage: Equatable, Sendable {
    var ok: Bool
    var text: String
}

/// A success or failure line under a control — "Test sent", "No chats found".
struct StatusNote: View {
    let ok: Bool
    let text: String

    init(ok: Bool, text: String) {
        self.ok = ok
        self.text = text
    }

    init(_ message: StatusMessage) {
        self.init(ok: message.ok, text: message.text)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(ok ? Palette.income : Palette.danger)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A list row that lights up while it is held, the way the web's rows do on hover.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Palette.hover : Color.clear,
                in: .rect(cornerRadius: Palette.Radius.row))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Dots the balances out, or brings them back. It sits next to a balance rather than in Settings,
/// so it is where you are when you decide you would rather not look — and the same button puts
/// the number back.
struct BalanceToggle: View {
    @AppStorage(Prefs.showBalancesKey) private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: shown ? "eye" : "eye.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 30, height: 30)
                .background(Palette.surface2, in: .circle)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: shown)
        .accessibilityLabel(shown ? "Hide balances" : "Show balances")
    }
}

/// The checkbox a row wears in selection mode.
struct SelectionMark: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.faint, lineWidth: selected ? 0 : 1.5)
                .background(Circle().fill(selected ? Palette.accent : Color.clear))
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.paper)
            }
        }
        .frame(width: 22, height: 22)
        .animation(.snappy(duration: 0.15), value: selected)
        .accessibilityHidden(true)
    }
}

/// The eight hues the design is built from, so a picked color always belongs.
struct ColorSwatchPicker: View {
    let colors: [String]
    @Binding var selection: String

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(colors, id: \.self) { hex in
                Button { selection = hex } label: {
                    Circle()
                        .fill(Color(hexString: hex))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle()
                                .strokeBorder(Palette.ink, lineWidth: selection == hex ? 2 : 0)
                                .padding(-4)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(hex)")
                .accessibilityAddTraits(selection == hex ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 6)
    }
}

/// Wraps chips onto as many lines as they need — tags, color swatches, emoji.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A QR code for an `otpauth://` URI, drawn crisp at any size. Black on white whatever the
/// theme: a dark-on-dark code is one some scanners will not read.
struct QRCodeImage: View {
    let text: String
    var size: CGFloat = 176

    var body: some View {
        Group {
            if let image = Self.render(text) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .padding(12)
        .background(Color.white, in: .rect(cornerRadius: 16))
    }

    private static func render(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
