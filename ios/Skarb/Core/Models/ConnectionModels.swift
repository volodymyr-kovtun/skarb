import Foundation

nonisolated struct Connection: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var provider: String
    var displayName: String
    var status: String
    var lastSyncedAt: Date?
    var lastError: String?
    var accountCount: Int
    var consentValidUntil: Date?
    /// Accounts deleted from this connection, which sync no longer recreates.
    var ignoredAccountCount: Int

    var isMonobank: Bool { provider == ProviderName.monobank }
    var isEnableBanking: Bool { provider == ProviderName.enableBanking }
    var isLinked: Bool { status == "linked" }
}

nonisolated struct SyncStatus: Codable, Sendable {
    struct LogEntry: Codable, Sendable, Identifiable {
        var at: Date
        var provider: String
        var message: String
        var success: Bool
        var newTransactions: Int
        var id: String { "\(at.timeIntervalSince1970)-\(provider)-\(message)" }
    }

    var running: [String]
    var logs: [LogEntry]
}

/// A bank Enable Banking can reach — an "ASPSP" in open-banking terms.
nonisolated struct Aspsp: Codable, Identifiable, Hashable, Sendable {
    var name: String
    var country: String
    var logo: String?

    var id: String { "\(country):\(name)" }
}

nonisolated struct TelegramSettings: Codable, Sendable {
    var hasToken: Bool
    var botUsername: String?
}

nonisolated struct TelegramChat: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
}

// MARK: - CSV import

/// A statement handed to `POST /api/import/csv`. With `format` set, the server reads the file
/// by its own header and the column fields are ignored.
nonisolated struct CSVImportRequest: Encodable, Sendable, Equatable {
    var accountId: UUID
    var content: String
    var dateColumn: Int
    var amountColumn: Int
    var descriptionColumn: Int
    var currencyColumn: Int?
    var dateFormat: String
    var decimalSeparator: String
    var delimiter: String
    var hasHeader: Bool
    var invertAmount: Bool
    var format: String?
}

nonisolated struct CSVImportResult: Codable, Sendable, Equatable {
    var imported: Int
    var skipped: Int
    var errors: [String]
    /// Things worth a look that didn't stop the import — a closing balance that disagrees, say.
    var warnings: [String]?
}
