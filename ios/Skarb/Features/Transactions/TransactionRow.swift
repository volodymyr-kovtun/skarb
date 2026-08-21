import SwiftUI

/// One transaction, as it appears everywhere a list of them does. Without an `onTap` the row
/// is being shown as evidence, not offered as a control.
struct TransactionRow: View {
    let tx: Tx
    var onTap: (() -> Void)?

    private var dimmed: Bool { tx.isInternal || tx.isExcluded }

    var body: some View {
        let row = HStack(spacing: 12) {
            if tx.isInternal {
                RoundedRectangle(cornerRadius: Palette.Radius.tile)
                    .fill(Palette.surface2)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.faint)
                    }
            } else {
                CategoryDot(category: tx.category)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tx.description)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(dimmed ? Palette.muted : Palette.ink)
                        .lineLimit(1)
                    if tx.isInternal { Chip(text: "internal") }
                    if tx.isExcluded { Chip(text: "excluded") }
                    ForEach(tx.tags.prefix(2)) { tag in
                        Chip(text: "#\(tag.name)", hex: tag.color)
                    }
                }
                HStack(spacing: 5) {
                    ColorDot(hex: tx.accountColor, size: 6)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Money(amount: tx.amount, currency: tx.currency, signed: !dimmed, muted: dimmed)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)

        if let onTap {
            Button(action: onTap) { row.contentShape(.rect) }
                .buttonStyle(RowButtonStyle())
        } else {
            row
        }
    }

    private var subtitle: String {
        let account = tx.bank.isEmpty ? tx.accountName : tx.bank
        if !tx.isInternal, let category = tx.category { return "\(account) · \(category.name)" }
        return account
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
