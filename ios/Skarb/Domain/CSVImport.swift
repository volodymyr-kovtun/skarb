import Foundation

/// A statement layout the importer knows. Mirrors `CSV_PRESETS` in the web's Settings page.
nonisolated struct CSVPreset: Identifiable, Equatable, Sendable {
    let id: String
    var label: String
    var hint: String
    /// A bank's own layout, read server-side by its header; the columns below are then ignored.
    var format: String?
    var columns: CSVColumns

    static let zen = CSVPreset(
        id: "zen", label: "ZEN.com statement",
        hint: "ZEN app → Wallet → currency → ⋯ → Statements → Generate (CSV). One file per currency, "
            + "each into its own ZEN account — exchanges between them are matched up as internal.",
        format: "zen",
        columns: CSVColumns(date: 0, amount: 3, description: 2, currency: 4))

    static let pko = CSVPreset(
        id: "pko", label: "PKO iPKO export",
        hint: "iPKO → account history → Eksport danych → CSV.",
        columns: CSVColumns(date: 0, amount: 3, description: 6, currency: 4, dateFormat: "yyyy-MM-dd"))

    static let generic = CSVPreset(
        id: "generic", label: "Generic CSV",
        hint: "Any file with date, amount and description columns — set the column numbers below "
            + "(first column = 0).",
        columns: CSVColumns(date: 0, amount: 1, description: 2, currency: nil))

    static let all = [zen, pko, generic]
}

/// Where a plain table keeps each field, and how it writes them.
nonisolated struct CSVColumns: Equatable, Sendable {
    var date: Int
    var amount: Int
    var description: Int
    var currency: Int?
    /// Empty means "let the server work it out".
    var dateFormat = ""
    var decimalSeparator = "."
    var delimiter = ","
    var invertAmount = false

    static let decimalSeparators = [".", ","]
    static let delimiters = [
        CSVDelimiter(value: ",", label: ","),
        CSVDelimiter(value: ";", label: ";"),
        CSVDelimiter(value: "\t", label: "tab"),
    ]
}

nonisolated struct CSVDelimiter: Identifiable, Equatable, Sendable {
    var value: String
    var label: String
    var id: String { value }
}

nonisolated enum CSVImport {
    /// The file's text, read exactly the way a browser's `File.text()` reads it.
    ///
    /// That matters more than it looks: rows without a provider id are deduplicated on an id
    /// built from their text, so a statement imported from the web and again from the phone must
    /// decode to the same characters or every row would come in twice. A browser decodes UTF-8,
    /// replaces anything invalid with U+FFFD rather than guessing another encoding, and drops a
    /// leading byte-order mark — and so does this.
    static func text(from data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    static func request(
        account: UUID, content: String, preset: CSVPreset, columns: CSVColumns, hasHeader: Bool
    ) -> CSVImportRequest {
        CSVImportRequest(
            accountId: account, content: content,
            dateColumn: columns.date, amountColumn: columns.amount,
            descriptionColumn: columns.description, currencyColumn: columns.currency,
            dateFormat: columns.dateFormat, decimalSeparator: columns.decimalSeparator,
            delimiter: columns.delimiter, hasHeader: hasHeader, invertAmount: columns.invertAmount,
            format: preset.format)
    }

    /// The one-line account of what happened, as the web's banner words it.
    static func summary(_ result: CSVImportResult) -> String {
        let errors = result.errors.isEmpty ? "" : " (\(result.errors.count) row(s) skipped with errors)"
        let warnings = (result.warnings ?? []).isEmpty ? "" : " " + (result.warnings ?? []).joined(separator: " ")
        return "Imported \(result.imported) transaction(s), \(result.skipped) duplicate(s) skipped\(errors).\(warnings)"
    }
}
