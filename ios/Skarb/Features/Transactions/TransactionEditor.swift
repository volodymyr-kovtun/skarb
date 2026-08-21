import SwiftUI

/// Add or edit one transaction. A synced transaction's amount belongs to the bank, so only a
/// manual one can have it changed — everything else (category, tags, note, whether it counts)
/// is yours either way.
struct TransactionEditor: View {
    /// Nil means this sheet is adding rather than editing.
    let tx: Tx?
    /// Called with the saved transaction when this edit moved it to a category it wasn't in
    /// before — which is what the list needs in order to offer a rule for it.
    var onRecategorized: ((Tx) -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var kind: Kind = .expense
    @State private var accountId: UUID?
    @State private var amount = ""
    @State private var descriptionText = ""
    @State private var categoryId: UUID?
    @State private var tagIds: [UUID] = []
    @State private var date = Date()
    @State private var note = ""
    @State private var isExcluded = false
    @State private var isInternal = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingDelete = false
    @State private var pickingTags = false
    @State private var newTag = ""
    @State private var loaded = false

    private enum Kind: String, CaseIterable {
        case expense, income
        var label: String { self == .expense ? "Money out" : "Money in" }
    }

    private var isEdit: Bool { tx != nil }
    private var account: Account? { model.accounts.first { $0.id == accountId } }
    private var amountEditable: Bool { !isEdit || tx?.source == "manual" }
    /// Money out can be an expense or an investment contribution; money in = income categories.
    private var categories: [Category] {
        model.categories.filter {
            kind == .expense ? ($0.kind == .expense || $0.kind == .investment) : $0.kind == .income
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Direction", selection: $kind) {
                        ForEach(Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, _ in categoryId = nil }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listRowBackground(Color.clear)

                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .disabled(!amountEditable)
                            .foregroundStyle(amountEditable ? Palette.ink : Palette.faint)
                        if let account { Text(account.currency).foregroundStyle(Palette.faint) }
                    }
                    if !amountEditable {
                        Text("The bank owns this amount — it re-syncs from your statement.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.faint)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Where did the money go?", text: $descriptionText, axis: .vertical)
                }

                Section {
                    Picker("Account", selection: $accountId) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(model.accounts.filter { !$0.isArchived }) { account in
                            Text(account.label).tag(UUID?.some(account.id))
                        }
                    }
                    .disabled(isEdit)

                    Picker("Category", selection: $categoryId) {
                        Text("Uncategorized").tag(UUID?.none)
                        ForEach(categories) { category in
                            Text("\(category.emoji) \(category.name)"
                                + (category.kind == .investment ? " (investment)" : ""))
                                .tag(UUID?.some(category.id))
                        }
                    }
                }

                Section("Tags") {
                    Button {
                        pickingTags = true
                    } label: {
                        HStack {
                            Text(tagIds.isEmpty ? "None" : pickedTagNames)
                                .foregroundStyle(tagIds.isEmpty ? Palette.faint : Palette.ink)
                                .lineLimit(1)
                            Spacer()
                            DisclosureChevron()
                        }
                    }
                    HStack {
                        TextField("Add a new tag", text: $newTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { Task { await addTag() } }
                        if !newTag.trimmed.isEmpty {
                            Button("Add") { Task { await addTag() } }
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }

                if isEdit {
                    Section {
                        Toggle("Internal transfer", isOn: $isInternal)
                        Toggle("Exclude from stats", isOn: $isExcluded)
                    } footer: {
                        Text("Internal transfers move money between your own accounts and are never counted. Exclude covers everything else that shouldn't count — a reimbursement, a correction.")
                    }

                    Section {
                        Button("Delete transaction", role: .destructive) { confirmingDelete = true }
                    }
                }

                if let error {
                    Section { FormError(error).listRowInsets(EdgeInsets()) }
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(isEdit ? "Edit transaction" : "Add transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(busy ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(busy)
                }
            }
            .sheet(isPresented: $pickingTags) {
                TagPickerSheet(selected: $tagIds, tags: model.tags, title: "Tags")
            }
            .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) { Task { await remove() } }
            }
        }
        .task { load() }
        // Meta can still be in flight when this sheet opens; pick the default the moment the
        // accounts arrive rather than latching whatever was there at first appearance.
        .onChange(of: model.accounts) { _, accounts in
            if tx == nil, accountId == nil { accountId = accounts.first { !$0.isArchived }?.id }
        }
    }

    private var pickedTagNames: String {
        model.tags.filter { tagIds.contains($0.id) }.map { "#\($0.name)" }.joined(separator: " ")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let tx else {
            accountId = model.accounts.first { !$0.isArchived }?.id
            return
        }
        kind = tx.amount > 0 ? .income : .expense
        accountId = tx.accountId
        amount = "\(abs(tx.amount))"
        descriptionText = tx.description
        categoryId = tx.category?.id
        tagIds = tx.tags.map(\.id)
        date = tx.occurredAt
        note = tx.note ?? ""
        isExcluded = tx.isExcluded
        isInternal = tx.isInternal
    }

    private func addTag() async {
        let name = newTag.trimmed.lowercased()
        guard !name.isEmpty else { return }
        do {
            let tag = try await APIClient.shared.createTag(name: name, color: nil)
            if !tagIds.contains(tag.id) { tagIds.append(tag.id) }
            newTag = ""
            await model.loadMeta()
        } catch {
            model.handle(error)
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard let accountId else {
            error = "Pick an account."
            return
        }
        let magnitude = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        let signed = (kind == .expense ? -1 : 1) * abs(magnitude)
        guard signed != 0, !descriptionText.trimmed.isEmpty else {
            error = "Amount and description are required."
            return
        }

        busy = true
        defer { busy = false }
        error = nil
        do {
            if let tx {
                let saved = try await APIClient.shared.updateTransaction(tx.id, TransactionPatch(
                    description: descriptionText.trimmed,
                    amount: amountEditable ? signed : nil,
                    occurredAt: date,
                    note: note,
                    isExcluded: isExcluded,
                    isInternal: isInternal,
                    categorySet: true,
                    categoryId: categoryId,
                    tagIds: tagIds))
                // Only a move to a real category is worth generalising — clearing one, or
                // re-saving the category it already had, teaches nothing.
                let changed = categoryId != nil && categoryId != tx.category?.id
                await model.invalidate()
                dismiss()
                if changed, !saved.isInternal { onRecategorized?(saved) }
            } else {
                _ = try await APIClient.shared.createTransaction(NewTransaction(
                    accountId: accountId,
                    amount: signed,
                    description: descriptionText.trimmed,
                    categoryId: categoryId,
                    tagIds: tagIds,
                    occurredAt: date,
                    note: note.trimmed.isEmpty ? nil : note.trimmed))
                await model.invalidate()
                dismiss()
            }
        } catch {
            model.handle(error)
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        guard let tx else { return }
        await model.perform("Transaction deleted") {
            try await APIClient.shared.deleteTransaction(tx.id)
        }
        dismiss()
    }
}
