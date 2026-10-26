import Foundation

/// The words a bank connection is described and questioned in.
nonisolated enum ConnectionCopy {
    static func subtitle(_ connection: Connection, now: Date = Date()) -> String {
        var parts = ["\(connection.accountCount) account\(connection.accountCount == 1 ? "" : "s")"]
        if let synced = connection.lastSyncedAt { parts.append("synced \(Format.relative(synced, to: now))") }
        if let until = connection.consentValidUntil {
            parts.append("\(until < now ? "consent ended" : "consent until") \(Format.shortDate(until))")
        }
        return parts.joined(separator: " · ")
    }

    /// Enable Banking consent lasts about 90 days. Within a fortnight of the end, the connection
    /// says so before syncs start failing.
    static func needsRenewal(_ connection: Connection, now: Date = Date()) -> Bool {
        guard connection.isEnableBanking else { return false }
        guard let until = connection.consentValidUntil else { return !connection.isLinked }
        return until.timeIntervalSince(now) < 14 * 24 * 3600
    }

    static func deleteWarning(_ connection: Connection) -> String {
        guard connection.accountCount > 0 else { return "Remove \(connection.displayName)?" }
        let accounts = connection.accountCount == 1 ? "Its 1 account" : "Its \(connection.accountCount) accounts"
        return "Remove \(connection.displayName)? \(accounts) and every transaction on them will be deleted. "
            + "This cannot be undone."
    }

    static func ignoredNote(_ connection: Connection) -> String {
        connection.ignoredAccountCount == 1
            ? "1 deleted account is kept out of sync."
            : "\(connection.ignoredAccountCount) deleted accounts are kept out of sync."
    }

    static func restoreWarning(_ connection: Connection) -> String {
        let what = connection.ignoredAccountCount == 1 ? "it" : "them"
        return "Bring \(what) back? The next sync recreates \(what) and re-fetches history from scratch."
    }

    /// The countries the bank list can be narrowed to, with "every country" first.
    static let countries = [
        "ALL", "PL", "LT", "DE", "FR", "ES", "IT", "NL", "BE", "AT", "PT", "CZ", "SK", "HU", "RO", "BG",
        "HR", "SI", "GR", "IE", "FI", "SE", "DK", "NO", "EE", "LV", "GB",
    ]

    static func countryLabel(_ code: String) -> String {
        code == "ALL" ? "🌍 All countries" : code
    }
}
