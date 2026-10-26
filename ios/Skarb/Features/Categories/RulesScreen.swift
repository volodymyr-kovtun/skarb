import SwiftUI

@Observable
final class RulesModel {
    /// Rules shown before "Show more" — the seeded set alone runs to a few hundred.
    static let page = 12

    private(set) var rules: [Rule] = []
    var search = "" {
        // A fresh search starts back at the top of the list.
        didSet { if search != oldValue { visible = Self.page } }
    }
    private(set) var visible = RulesModel.page
    var pattern = ""
    var categoryId: UUID?
    private(set) var applyNote: String?
    private(set) var busy = false

    private let service: any RuleService
    private let ledger: LedgerStore
    private let toasts: ToastCenter

    init(service: any RuleService, ledger: LedgerStore, toasts: ToastCenter) {
        self.service = service
        self.ledger = ledger
        self.toasts = toasts
    }

    var matches: [Rule] {
        let query = search.trimmed.lowercased()
        guard !query.isEmpty else { return rules }
        return rules.filter {
            $0.pattern.lowercased().contains(query) || $0.category.name.lowercased().contains(query)
        }
    }

    var shown: [Rule] { Array(matches.prefix(visible)) }
    var canAdd: Bool { !busy && !pattern.trimmed.isEmpty && categoryId != nil }

    func showMore() { visible += Self.page }

    func load() async {
        if let fresh = try? await service.rules() { rules = fresh }
    }

    func applyToUncategorized() async {
        busy = true
        defer { busy = false }
        do {
            let result = try await service.applyToUncategorized()
            applyNote = "Categorized \(result.categorized) of \(result.scanned) uncategorized transaction\(result.scanned == 1 ? "" : "s")."
            await ledger.invalidate()
        } catch {
            toasts.show(error)
        }
    }

    func add() async {
        guard canAdd, let categoryId else { return }
        busy = true
        defer { busy = false }
        let keyword = pattern.trimmed
        do {
            // New transactions only, as on the web and as the card above says: re-filing the past
            // is "Apply to uncategorized", or the rule offer, which both say what they touched.
            _ = try await service.create(pattern: keyword, categoryId: categoryId, applyTo: .none)
            pattern = ""
            // A new rule sorts to the bottom of a long list — search for it so it is visible.
            search = keyword
            await ledger.invalidate()
            await load()
        } catch {
            toasts.show(error)
        }
    }

    func delete(_ rule: Rule) async {
        do {
            try await service.delete(rule.id)
            rules.removeAll { $0.id == rule.id }
            await ledger.invalidate()
        } catch {
            toasts.show(error)
        }
    }
}

extension AppContainer {
    func makeRules() -> RulesModel { RulesModel(service: rules, ledger: ledger, toasts: toasts) }
}

/// The keywords that file transactions on arrival. Most rules are easier to make by correcting
/// a category and accepting the offer that follows — this is where they are reviewed and tidied.
struct RulesScreen: View {
    @State private var model: RulesModel
    @Environment(LedgerStore.self) private var ledger

    init(model: RulesModel) { _model = State(initialValue: model) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                introCard
                newRuleCard
                if !model.rules.isEmpty { listCard }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96)
        }
        .background(Palette.paper)
        .navigationTitle("Rules")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task(id: ledger.revision) { await model.load() }
    }

    private var introCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("When a new transaction's description contains a keyword, it gets that category automatically — `ibkr` → 📈 Brokerage counts as investing. Rules apply as transactions arrive; “Apply to uncategorized” runs them over what you already have, and only fills blanks.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(3)

                if let note = model.applyNote {
                    Text(note)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Palette.income)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.income.opacity(0.1), in: .rect(cornerRadius: Palette.Radius.row))
                }

                Button("Apply to uncategorized") { Task { await model.applyToUncategorized() } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .disabled(model.busy)
            }
            .padding(20)
        }
    }

    private var newRuleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("New rule")
                    .font(.display(15))
                    .foregroundStyle(Palette.ink)
                TextField("Keyword, e.g. \"zabka\"", text: $model.pattern)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .skarbField()
                Menu {
                    Picker("Category", selection: $model.categoryId) {
                        Text("Pick category…").tag(UUID?.none)
                        ForEach(ledger.categories) { category in
                            Text(category.label).tag(UUID?.some(category.id))
                        }
                    }
                } label: {
                    HStack {
                        Text(ledger.category(model.categoryId)?.label ?? "Pick category…")
                            .foregroundStyle(model.categoryId == nil ? Palette.faint : Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.faint)
                    }
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Palette.surface2, in: .rect(cornerRadius: Palette.Radius.row))
                }
                Button("Add rule") { Task { await model.add() } }
                    .buttonStyle(.skarbPrimary)
                    .disabled(!model.canAdd)
                    .opacity(model.canAdd ? 1 : 0.5)
            }
            .padding(20)
        }
    }

    private var listCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "\(model.rules.count) rules")

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                    TextField("Search by keyword or category", text: $model.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.faint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.surface2, in: .capsule)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                if model.matches.isEmpty {
                    EmptyNote(text: "No rule matches “\(model.search.trimmed)”.")
                } else {
                    ForEach(model.shown) { rule in
                        ruleRow(rule)
                    }

                    HStack(spacing: 12) {
                        if model.shown.count < model.matches.count {
                            Button("Show more") { model.showMore() }
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                        }
                        Text("Showing \(model.shown.count) of \(model.matches.count)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.faint)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(spacing: 10) {
            Text(rule.pattern)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Palette.surface2, in: .rect(cornerRadius: 6))
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)
            Text(rule.category.label)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button {
                Task { await model.delete(rule) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.faint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove rule \(rule.pattern)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 20)
        }
    }
}
