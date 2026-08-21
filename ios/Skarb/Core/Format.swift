import Foundation

/// Every number and date the app prints, formatted once so two screens can't disagree.
nonisolated enum Format {
    /// `NumberFormatter` construction is expensive and money is drawn per row and per chart
    /// tooltip — so they are cached per currency and precision, as on the web.
    private nonisolated(unsafe) static var formatters: [String: NumberFormatter] = [:]
    private static let formatterLock = NSLock()

    static func money(
        _ amount: Decimal, _ currency: String, signed: Bool = false, decimals: Int = 2
    ) -> String {
        let key = "\(currency)|\(decimals)"
        let formatter: NumberFormatter = {
            formatterLock.lock()
            defer { formatterLock.unlock() }
            if let cached = formatters[key] { return cached }
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.locale = Locale(identifier: "en_US")
            f.currencyCode = currency
            // The narrow symbol is what keeps "zł 1,240.00" from becoming "PLN 1,240.00" in
            // a column that has to fit on a phone.
            f.currencySymbol = narrowSymbol(for: currency)
            f.minimumFractionDigits = decimals
            f.maximumFractionDigits = decimals
            formatters[key] = f
            return f
        }()

        let magnitude = abs(amount)
        let body = formatter.string(from: magnitude as NSDecimalNumber) ?? "\(magnitude)"
        // A real minus sign, not a hyphen — it lines up with the figures around it.
        let sign = amount < 0 ? "−" : (signed ? "+" : "")
        return sign + body
    }

    /// A rounded figure for axis ticks and "all time" footers: 12.4k rather than 12,431.00.
    static func compact(_ amount: Decimal) -> String {
        let value = abs((amount as NSDecimalNumber).doubleValue)
        let sign = amount < 0 ? "−" : ""
        if value >= 1000 {
            let thousands = value / 1000
            return sign + (thousands.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(thousands))k"
                : String(format: "%.1fk", thousands))
        }
        return sign + "\(Int(value.rounded()))"
    }

    /// The compact symbol, so a column of money fits a phone: "zl 1,240.00" rather than
    /// "PLN 1,240.00". Anything not in the table keeps its ISO code, which is never wrong.
    private static func narrowSymbol(for currency: String) -> String {
        symbolTable[currency] ?? currency + "\u{00A0}"
    }

    /// The handful of currencies a European ledger actually holds, plus a sane fallback.
    private static let symbolTable: [String: String] = [
        "PLN": "zł", "EUR": "€", "USD": "$", "GBP": "£", "UAH": "₴",
        "CHF": "CHF ", "CZK": "Kč", "SEK": "kr", "NOK": "kr", "DKK": "kr",
    ]

    // MARK: - Dates

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    /// Date-only strings from the API (a report window's ends) are UTC calendar dates and
    /// carry no instant, so they are read and written in UTC.
    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// A transaction's instant, bucketed into the reader's own day — the same day
    /// `dayLabel` names, so a section heading can never disagree with its rows.
    private static let localDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "Today", "Yesterday", or the full weekday — the heading over a day's transactions.
    static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return dayFormatter.string(from: date)
    }

    /// The day a transaction is filed under, used to group a list into sections.
    static func dayKey(_ date: Date) -> String { localDay.string(from: date) }

    static func parseDay(_ iso: String) -> Date? { isoDay.date(from: iso) }

    /// A window with both ends inclusive, written as short as it goes without turning
    /// ambiguous: the day alone repeats inside one month, the month repeats across two, and
    /// the year is always spelled out.
    static func range(_ startISO: String, _ endISO: String) -> String {
        guard let from = parseDay(startISO), let to = parseDay(endISO) else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let f = { (format: String) -> DateFormatter in
            let df = DateFormatter()
            df.dateFormat = format
            df.locale = Locale(identifier: "en_US")
            df.timeZone = TimeZone(identifier: "UTC")
            return df
        }
        if startISO == endISO { return f("d MMM yyyy").string(from: to) }
        if calendar.component(.year, from: from) != calendar.component(.year, from: to) {
            return "\(f("d MMM yyyy").string(from: from)) – \(f("d MMM yyyy").string(from: to))"
        }
        if calendar.component(.month, from: from) != calendar.component(.month, from: to) {
            return "\(f("d MMM").string(from: from)) – \(f("d MMM yyyy").string(from: to))"
        }
        return "\(f("d").string(from: from)) – \(f("d MMM yyyy").string(from: to))"
    }

    /// "Aug" for a `2026-08` cashflow bucket.
    static func monthLabel(_ month: String) -> String {
        guard let date = parseDay(month + "-01") else { return month }
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// "synced 4 min ago" — how a connection reports when it last ran.
    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
