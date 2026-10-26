import SwiftUI
import UniformTypeIdentifiers

/// A bank statement file, for the banks with no API — ZEN, or anything that exports a table.
@Observable
final class CSVImportModel {
    var accountId: UUID?
    private(set) var preset = CSVPreset.zen
    var columns = CSVPreset.zen.columns
    var hasHeader = true
    private(set) var content = ""
    private(set) var fileName: String?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var result: CSVImportResult?

    private let service: any ImportService
    private let ledger: LedgerStore

    init(service: any ImportService, ledger: LedgerStore) {
        self.service = service
        self.ledger = ledger
        accountId = ledger.accounts.first?.id
    }

    var accounts: [Account] { ledger.accounts }
    var canImport: Bool { !busy && !content.isEmpty && accountId != nil }
    /// A bank's own layout is read by its header, so there is no mapping to show.
    var showsMapping: Bool { preset.format == nil }
    var summary: String? { result.map(CSVImport.summary) }

    func pick(_ preset: CSVPreset) {
        self.preset = preset
        columns = preset.columns
    }

    func load(_ data: Data, named name: String) {
        content = CSVImport.text(from: data)
        fileName = name
        result = nil
        error = nil
    }

    func fail(_ message: String) { error = message }

    func run() async {
        guard canImport, let accountId else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            result = try await service.importCSV(CSVImport.request(
                account: accountId, content: content, preset: preset, columns: columns, hasHeader: hasHeader))
            await ledger.invalidate()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension AppContainer {
    func makeCSVImport() -> CSVImportModel { CSVImportModel(service: imports, ledger: ledger) }
}

struct CSVImportSheet: View {
    @State private var model: CSVImportModel
    @State private var picking = false
    @Environment(\.dismiss) private var dismiss

    init(model: CSVImportModel) { _model = State(initialValue: model) }

    var body: some View {
        SheetScaffold(title: "Import a statement") {
            if let summary = model.summary, let result = model.result {
                outcome(summary, result)
            } else {
                form
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    model.load(try Data(contentsOf: url), named: url.lastPathComponent)
                } catch {
                    model.fail("Couldn't read that file: \(error.localizedDescription)")
                }
            case .failure(let error):
                model.fail(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        LabeledField("Into account") {
            Picker("Into account", selection: $model.accountId) {
                ForEach(model.accounts) { account in
                    Text("\(account.label) (\(account.currency))").tag(UUID?.some(account.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        LabeledField("Format") {
            Picker("Format", selection: Binding(get: { model.preset.id }, set: { id in
                if let preset = CSVPreset.all.first(where: { $0.id == id }) { model.pick(preset) }
            })) {
                ForEach(CSVPreset.all) { Text($0.label).tag($0.id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        Text(model.preset.hint)
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.muted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface2, in: .rect(cornerRadius: Palette.Radius.row))

        Button { picking = true } label: {
            Label(model.fileName ?? "Choose a .csv file", systemImage: model.fileName == nil ? "doc.badge.plus" : "doc.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.fileName == nil ? Palette.muted : Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .overlay {
                    RoundedRectangle(cornerRadius: Palette.Radius.row)
                        .strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
        }
        .buttonStyle(.plain)

        if model.showsMapping { mapping }

        if let error = model.error { FormError(error) }

        Button(model.busy ? "Importing…" : "Import") { Task { await model.run() } }
            .buttonStyle(.skarbPrimary)
            .disabled(!model.canImport)
            .opacity(model.canImport ? 1 : 0.5)
    }

    /// Where a plain table keeps each field. First column is 0, as on the web.
    private var mapping: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Column mapping (first column = 0)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
            Stepper("Date: column \(model.columns.date)", value: $model.columns.date, in: 0...60)
            Stepper("Amount: column \(model.columns.amount)", value: $model.columns.amount, in: 0...60)
            Stepper("Description: column \(model.columns.description)", value: $model.columns.description, in: 0...60)
            Toggle("Currency column", isOn: Binding(
                get: { model.columns.currency != nil },
                set: { model.columns.currency = $0 ? (model.columns.currency ?? 3) : nil }))
            if let currency = model.columns.currency {
                Stepper("Currency: column \(currency)", value: Binding(
                    get: { model.columns.currency ?? 0 }, set: { model.columns.currency = $0 }), in: 0...60)
            }
            HStack {
                Text("Date format")
                TextField("auto", text: $model.columns.dateFormat)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, design: .monospaced))
            }
            Picker("Decimal separator", selection: $model.columns.decimalSeparator) {
                ForEach(CSVColumns.decimalSeparators, id: \.self) { Text($0).tag($0) }
            }
            Picker("Delimiter", selection: $model.columns.delimiter) {
                ForEach(CSVColumns.delimiters) { Text($0.label).tag($0.value) }
            }
            Toggle("Header row", isOn: $model.hasHeader)
        }
        .font(.system(size: 14))
        .tint(Palette.accent)
        .padding(14)
        .background(Palette.surface, in: .rect(cornerRadius: Palette.Radius.row))
    }

    @ViewBuilder
    private func outcome(_ summary: String, _ result: CSVImportResult) -> some View {
        Label(summary, systemImage: result.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(result.errors.isEmpty ? Palette.income : Palette.ink)
            .fixedSize(horizontal: false, vertical: true)

        if !result.errors.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(result.errors.prefix(8).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.danger)
                }
                if result.errors.count > 8 {
                    Footnote("and \(result.errors.count - 8) more")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.danger.opacity(0.08), in: .rect(cornerRadius: Palette.Radius.row))
        }

        Button("Done") { dismiss() }
            .buttonStyle(.skarbPrimary)
    }
}
