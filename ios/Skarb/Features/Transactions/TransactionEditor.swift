import SwiftUI

struct TransactionEditor: View {
    @State private var model: TransactionEditorModel
    /// Called with the saved transaction when the edit moved it to a new category.
    var onRecategorized: ((Tx) -> Void)?

    @Environment(LedgerStore.self) private var ledger
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var pickingTags = false

    init(model: TransactionEditorModel, onRecategorized: ((Tx) -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onRecategorized = onRecategorized
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Direction", selection: Binding(get: { model.direction }, set: { model.setDirection($0) })) {
                        ForEach(TransactionEditorModel.Direction.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listRowBackground(Color.clear)

                amountSection
                placementSection
                tagsSection

                Section("Note") {
                    TextField("Optional", text: $model.note, axis: .vertical)
                }

                if model.showsCashBlock { CashReceivedSection(model: model) }

                if model.isWalletSide {
                    Section {
                        Text("The wallet side of a cash withdrawal — Skarb wrote it when the money left the bank. To change what you received, open the withdrawal itself. Deleting this row counts the withdrawal as spending again.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                    }
                }

                if model.showsCountingToggles { countingSection }

                if model.isEdit {
                    Section {
                        Button("Delete transaction", role: .destructive) { confirmingDelete = true }
                    }
                }

                if let error = model.error {
                    Section { FormError(error).listRowInsets(EdgeInsets()) }
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(model.isEdit ? "Edit transaction" : "Add transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.busy ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(model.busy)
                }
            }
            .sheet(isPresented: $pickingTags) {
                TagPickerSheet(selected: $model.tagIds, tags: ledger.tags, title: "Tags")
            }
            .confirmationDialog(model.deleteQuestion, isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { if await model.delete() != nil { dismiss() } }
                }
            }
        }
        .onChange(of: ledger.accounts, initial: true) { _, _ in model.adoptDefaultAccount() }
    }

    // MARK: - Sections

    private var amountSection: some View {
        Section {
            HStack {
                Text("Amount")
                Spacer()
                TextField("0.00", text: $model.amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .disabled(!model.amountEditable)
                    .foregroundStyle(model.amountEditable ? Palette.ink : Palette.faint)
                if let account = model.account { Text(account.currency).foregroundStyle(Palette.faint) }
            }
            if !model.amountEditable {
                Text("The bank owns this amount — it re-syncs from your statement.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.faint)
            }
            if let original = model.original, let other = TransactionDetails.originalAmount(original) {
                LabeledContent("In the other currency", value: other)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
            }
            DatePicker("Date", selection: $model.date, displayedComponents: .date)
            TextField("Where did the money go?", text: $model.descriptionText, axis: .vertical)
        }
    }

    private var placementSection: some View {
        Section {
            Picker("Account", selection: $model.accountId) {
                Text("Choose…").tag(UUID?.none)
                ForEach(model.accountChoices) { account in
                    Text(account.label).tag(UUID?.some(account.id))
                }
            }
            .disabled(model.isEdit)

            Picker("Category", selection: $model.categoryId) {
                Text("Uncategorized").tag(UUID?.none)
                ForEach(model.categoryChoices) { category in
                    Text(category.label + (category.kind == .investment ? " (investment)" : ""))
                        .tag(UUID?.some(category.id))
                }
            }
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            Button {
                pickingTags = true
            } label: {
                HStack {
                    Text(model.tagIds.isEmpty ? "None" : model.pickedTagNames)
                        .foregroundStyle(model.tagIds.isEmpty ? Palette.faint : Palette.ink)
                        .lineLimit(1)
                    Spacer()
                    DisclosureChevron()
                }
            }
            HStack {
                TextField("Add a new tag", text: $model.newTagName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await model.addTag() } }
                if !model.newTagName.trimmed.isEmpty {
                    Button("Add") { Task { await model.addTag() } }
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
    }

    private var countingSection: some View {
        Section {
            Toggle("Internal transfer", isOn: $model.isInternal)
            if model.showsReleaseWarning, let warning = model.releaseWarning {
                Text(warning)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.faint)
            }
            Toggle("Exclude from stats", isOn: $model.isExcluded)
        } footer: {
            Text("Internal transfers move money between your own accounts and are never counted. Exclude covers everything else that shouldn't count — a reimbursement, a correction.")
        }
    }

    private func save() async {
        guard let outcome = await model.save() else { return }
        dismiss()
        if case .updated(let tx?) = outcome { onRecategorized?(tx) }
    }
}

/// What a cash withdrawal actually put in the wallet. The rate only ever fills the placeholder —
/// the amount is the owner's to give, because fees and the bank's spread are why it differs.
private struct CashReceivedSection: View {
    @Bindable var model: TransactionEditorModel

    var body: some View {
        Section {
            HStack(spacing: 12) {
                TextField(model.cashPlaceholder, text: $model.cashAmountText)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                    .accessibilityLabel("Amount received")
                Picker("Currency received", selection: Binding(
                    get: { model.cashCurrency }, set: { model.setCashCurrency($0) }
                )) {
                    ForEach(model.cashCurrencyOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        } header: {
            Text("Cash you received")
        } footer: {
            Text(model.cashHint)
        }
        .task(id: model.cashCurrency) { await model.loadEstimate() }
    }
}
