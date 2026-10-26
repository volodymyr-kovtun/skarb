import SwiftUI

/// Offered after a category is changed by hand: turn that one correction into a keyword rule
/// that files the matching transactions you already have, and every one that arrives from now on.
@Observable
final class RuleOfferModel {
    let tx: Tx
    let category: Category
    var pattern: String
    var applyPast = true
    var includeUntouched = false
    private(set) var current: RuleSuggestion
    private(set) var counting = false
    private(set) var busy = false
    private(set) var error: String?

    private let initialPattern: String?
    private let transactions: any TransactionService
    private let rules: any RuleService
    private let ledger: LedgerStore
    private let toasts: ToastCenter

    init(
        offer: TransactionsModel.RuleOffer, transactions: any TransactionService, rules: any RuleService,
        ledger: LedgerStore, toasts: ToastCenter
    ) {
        tx = offer.tx
        category = offer.category
        current = offer.suggestion
        pattern = offer.suggestion.pattern ?? ""
        initialPattern = offer.suggestion.pattern
        self.transactions = transactions
        self.rules = rules
        self.ledger = ledger
        self.toasts = toasts
    }

    var math: RuleOfferMath {
        RuleOfferMath(counts: current.matches, applyPast: applyPast, includeUntouched: includeUntouched)
    }

    /// Set when a rule already claims this keyword: repointing it keeps one rule instead of two
    /// that disagree.
    var existing: RuleSuggestion.ExistingRule? { current.existingRule }

    var title: String {
        existing.map { "Point “\($0.pattern)” elsewhere?" } ?? "Always file this as \(category.label)?"
    }

    var canSave: Bool { !busy && !pattern.trimmed.isEmpty }

    /// Re-counts for the keyword as typed. The previous counts stay on screen while the next ones
    /// load, so editing the keyword never blanks the sheet out from under the cursor.
    func recount() async {
        let keyword = pattern.trimmed
        guard !keyword.isEmpty, keyword != initialPattern else { return }
        counting = true
        defer { counting = false }
        if let fresh = try? await transactions.ruleSuggestion(for: tx.id, pattern: keyword),
           keyword == pattern.trimmed {
            current = fresh
        }
    }

    /// Saves the rule, and hands the toast everything it needs to take it back.
    func save() async -> Bool {
        guard canSave else { return false }
        busy = true
        error = nil
        defer { busy = false }
        let keyword = pattern.trimmed
        // Captured before the refresh: invalidating drops the suggestion, and the refetched one no
        // longer mentions the rule that was just created or repointed.
        let previous = existing
        do {
            let result: RuleApplied
            if let previous {
                result = try await rules.update(previous.id, categoryId: category.id, pattern: keyword, applyTo: math.scope)
            } else {
                result = try await rules.create(pattern: keyword, categoryId: category.id, applyTo: math.scope)
            }
            await ledger.invalidate()
            // Rewriting a pile of transactions on one tap needs a way back. The apply already
            // returned every row it touched and what it was filed as before, so undo is that list
            // handed straight back.
            toasts.show(RuleOfferMath.savedMessage(applied: result.applied)) { [rules, ledger, toasts] in
                do {
                    // Put the rule back where it was — repointed if it already existed, deleted if
                    // this created it — then restore every category this run rewrote.
                    if let previous {
                        _ = try await rules.update(
                            previous.id, categoryId: previous.category.id, pattern: nil, applyTo: .none)
                    } else {
                        try await rules.delete(result.id)
                    }
                    if !result.reverts.isEmpty { try await rules.revert(result.reverts) }
                    await ledger.invalidate()
                } catch {
                    toasts.show(error)
                }
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

extension AppContainer {
    func makeRuleOffer(_ offer: TransactionsModel.RuleOffer) -> RuleOfferModel {
        RuleOfferModel(offer: offer, transactions: transactions, rules: rules, ledger: ledger, toasts: toasts)
    }
}

/// It opens *after* the save has landed, so closing it costs nothing — the transaction stays
/// corrected either way. The keyword is editable and the counts under it are recomputed by the
/// server as it changes, so the guess never has to be right, only correctable.
struct RuleOfferSheet: View {
    @State private var model: RuleOfferModel
    @Environment(\.dismiss) private var dismiss

    init(model: RuleOfferModel) { _model = State(initialValue: model) }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        preamble
                        keywordField
                        alternatives
                        sample
                        if model.math.matched > 0 { pastToggle }
                        if let error = model.error { FormError(error) }
                    }
                    .padding(20)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(model.existing == nil ? "Not now" : "Keep both") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.busy ? "Saving…" : (model.existing == nil ? "Create rule" : "Update rule")) {
                        Task { if await model.save() { dismiss() } }
                    }
                    .fontWeight(.semibold)
                    .disabled(!model.canSave)
                }
            }
        }
        .presentationDetents([.large])
        // Typing a keyword shouldn't fire a count request per keystroke.
        .task(id: model.pattern) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await model.recount()
        }
    }

    @ViewBuilder
    private var preamble: some View {
        if let existing = model.existing {
            let keyword = Text(existing.pattern).fontWeight(.semibold).foregroundStyle(Palette.ink)
            Text("A rule already sends \(keyword) to \(existing.category.label). Changing it keeps one rule instead of two that disagree.")
                .foregroundStyle(Palette.muted)
        } else {
            Text("Skarb will use this keyword on new transactions as they arrive.")
                .foregroundStyle(Palette.muted)
        }
    }

    private var keywordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyword")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
            HStack(spacing: 10) {
                TextField("Which word identifies this merchant?", text: $model.pattern)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                let matched = model.math.matched
                Text(model.counting ? "counting…" : "\(matched) match\(matched == 1 ? "" : "es")")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Palette.faint)
            }
            .skarbField()
        }
        .font(.system(size: 13))
    }

    @ViewBuilder
    private var alternatives: some View {
        if !model.current.alternatives.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(model.current.alternatives, id: \.self) { alternative in
                    Button { model.pattern = alternative } label: {
                        Text(alternative)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Palette.surface2, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var sample: some View {
        let sample = model.current.sample
        if !sample.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sample) { TransactionRow(tx: $0) }
                    if model.math.matched > sample.count {
                        Text("and \(model.math.matched - sample.count) more")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.faint)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var pastToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $model.applyPast) {
                Text("Also file the \(model.math.changing) I already have")
                    .font(.system(size: 14, weight: .semibold))
            }
            .tint(Palette.accent)

            Text(model.math.breakdown)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.faint)
                .lineSpacing(2)

            if model.math.counts.untouched > 0 {
                Button(model.includeUntouched ? "Leave those alone" : "Include those too") {
                    model.includeUntouched.toggle()
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.accent)
            }
        }
        .padding(14)
        .background(Palette.surface, in: .rect(cornerRadius: Palette.Radius.row))
    }
}
