import Foundation

/// A list of transactions cut into days, newest first, the way the lists show them.
nonisolated struct TransactionDay: Identifiable, Sendable {
    let key: String
    var items: [Tx]
    var id: String { key }
    var date: Date { items[0].occurredAt }
    var ids: [UUID] { items.map(\.id) }

    /// Consecutive runs of the same day. The list arrives newest first, so a day never reappears
    /// further down — and if a page boundary splits one, the two halves still join up.
    static func group(_ items: [Tx], dayKey: (Date) -> String = Format.dayKey) -> [TransactionDay] {
        var days: [TransactionDay] = []
        for tx in items {
            let key = dayKey(tx.occurredAt)
            if days.last?.key == key {
                days[days.count - 1].items.append(tx)
            } else {
                days.append(TransactionDay(key: key, items: [tx]))
            }
        }
        return days
    }
}
