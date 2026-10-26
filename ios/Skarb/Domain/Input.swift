import Foundation

/// What a person typed into an amount field, read the way they meant it.
nonisolated enum MoneyInput: Equatable, Sendable {
    case empty
    case value(Decimal)
    case invalid

    /// Accepts "1240.50", "1 240,50" and "1,240.50": the decimal-pad keyboard offers whichever
    /// separator the phone's region uses, and statements copied in bring their own grouping.
    init(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
        guard !s.isEmpty else {
            self = .empty
            return
        }
        // A comma is the decimal mark unless a dot comes after it ("1,240.50").
        if let comma = s.lastIndex(of: ","), let dot = s.lastIndex(of: ".") {
            s = comma < dot ? s.replacingOccurrences(of: ",", with: "")
                : s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        let allowed = CharacterSet(charactersIn: "0123456789.-")
        guard s.unicodeScalars.allSatisfy(allowed.contains), s.filter({ $0 == "." }).count <= 1,
              !s.dropFirst().contains("-"),
              let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
        else {
            self = .invalid
            return
        }
        self = .value(value)
    }

    var decimal: Decimal? {
        if case .value(let v) = self { return v }
        return nil
    }
}

/// Server addresses as someone would actually type them.
nonisolated enum ServerAddressInput {
    /// Accepts `skarb.subero.app`, with or without a scheme or a trailing slash, and returns the
    /// origin the API client should call.
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host(), !host.isEmpty else { return nil }
        return url
    }
}

/// The server's floor for an owner's credentials, checked here first so a rejected form is a
/// surprise rather than the norm.
nonisolated enum CredentialPolicy {
    static let minimumPasswordLength = 12

    static func isPlausibleEmail(_ email: String) -> Bool {
        email.trimmingCharacters(in: .whitespaces).contains("@")
    }

    static func isLongEnough(_ password: String) -> Bool {
        password.count >= minimumPasswordLength
    }

    /// Authenticator codes are six digits; anything else typed or pasted is dropped.
    static func totpDigits(_ text: String) -> String {
        String(text.filter(\.isNumber).prefix(6))
    }
}

/// The calendar day someone picked, as the instant the API stores for it.
nonisolated enum DayStamp {
    /// Noon UTC on the picked day, which is what the web sends: whatever timezone either client
    /// is in, a midday instant lands on the same calendar date in both, so a transaction added on
    /// the phone and one added in a browser on the same day sit under the same heading.
    static func noonUTC(of date: Date, in calendar: Calendar = .current) -> Date {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day, hour: 12)) ?? date
    }

    static func isSameDay(_ a: Date, _ b: Date, in calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}
