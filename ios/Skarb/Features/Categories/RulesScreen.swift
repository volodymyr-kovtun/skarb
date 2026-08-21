import SwiftUI

/// The keywords that file transactions on arrival. Most rules are easier to make by correcting
/// a category and accepting the offer that follows — this is where they are reviewed and tidied.
struct RulesScreen: View {
    @Environment(AppModel.self) private var model

    /// Rules shown before "Show more" — the seeded set alone runs to a few hundred.
    private static let page = 12

    @State private var rules: [Rule] = []
    @State private var search = ""
    @State private var visible = RulesScreen.page
    @State private var pattern = ""
    @State private var categoryId: UUID?
    @State private var applyNote: String?
    @State private var busy = false

    private var matches: [Rule] {
        let query = search.trimmed.lowercased()
        guard !query.isEmpty else { return rules }
        return rules.filter {
            $0.pattern.lowercased().contains(query) || $0.category.name.lowercased().contains(query)
        }
    }
    private var shown: [Rule] { Array(matches.prefix(visible)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("When a new transaction's description contains a keyword, it gets that category automatically — `ibkr` → 📈 Brokerage counts as investing. Rules apply as transactions arrive; “Apply to uncategorized” runs them over what you already have, and only fills blanks.")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.muted)
                            .lineSpacing(3)

                        if let applyNote {
                            Text(applyNote)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(Palette.income)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.income.opacity(0.1), in: .rect(cornerRadius: Palette.Radius.row))
                        }

                        Button("Apply to uncategorized") { Task { await applyAll() } }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .disabled(busy)
                    }
                    .padding(20)
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("New rule")
                            .font(.display(15))
                            .foregroundStyle(Palette.ink)
                        TextField("Keyword, e.g. \"zabka\"", text: $pattern)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .skarbField()
                        Menu {
                            Picker("Category", selection: $categoryId) {
                                Text("Pick category…").tag(UUID?.none)
                                ForEach(model.categories) { category in
                                    Text("\(category.emoji) \(category.name)").tag(UUID?.some(category.id))
                                }
                            }
                        } label: {
                            HStack {
                                Text(pickedCategoryLabel)
                                    .foregroundStyle(categoryId == nil ? Palette.faint : Palette.ink)
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
                        Button("Add rule") { Task { await add() } }
                            .buttonStyle(.skarbPrimary)
                            .disabled(pattern.trimmed.isEmpty || categoryId == nil || busy)
                            .opacity(pattern.trimmed.isEmpty || categoryId == nil ? 0.5 : 1)
                    }
                    .padding(20)
                }

                if !rules.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 0) {
                            CardHeader(title: "\(rules.count) rules")

                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                                TextField("Search by keyword or category", text: $search)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    // A fresh search starts back at the top of the list.
                                    .onChange(of: search) { _, _ in visible = Self.page }
                                if !search.isEmpty {
                                    Button { search = "" } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.faint)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .font(.system(size: 15))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Palette.surface2, in: .capsule)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)

                            if matches.isEmpty {
                                EmptyNote(text: "No rule matches “\(search.trimmed)”.")
                            } else {
                                ForEach(shown) { rule in
                                    ruleRow(rule)
                                }

                                HStack(spacing: 12) {
                                    if shown.count < matches.count {
                                        Button("Show more") { visible += Self.page }
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundStyle(Palette.accent)
                                    }
                                    Text("Showing \(shown.count) of \(matches.count)")
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96)
        }
        .background(Palette.paper)
        .navigationTitle("Rules")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task(id: model.revision) { await load() }
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
            Text("\(rule.category.emoji) \(rule.category.name)")
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button {
                Task {
                    await model.perform { try await APIClient.shared.deleteRule(rule.id) }
                    await load()
                }
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

    private var pickedCategoryLabel: String {
        guard let categoryId, let category = model.categories.first(where: { $0.id == categoryId })
        else { return "Pick category…" }
        return "\(category.emoji) \(category.name)"
    }

    private func load() async {
        do {
            rules = try await APIClient.shared.rules()
        } catch {
            model.handle(error)
        }
    }

    private func applyAll() async {
        busy = true
        defer { busy = false }
        do {
            let result = try await APIClient.shared.applyRules()
            applyNote = "Categorized \(result.categorized) of \(result.scanned) uncategorized transaction\(result.scanned == 1 ? "" : "s")."
            await model.invalidate()
        } catch {
            model.handle(error)
            model.show(error.localizedDescription, isError: true)
        }
    }

    private func add() async {
        guard let categoryId, !pattern.trimmed.isEmpty else { return }
        busy = true
        defer { busy = false }
        let keyword = pattern.trimmed
        do {
            // No priority: the server sorts a hand-written rule ahead of the seeded ones, which
            // is the only way it can beat a broad default like "supermarket" or "fee".
            try await APIClient.shared.createRule(
                pattern: keyword, categoryId: categoryId, applyTo: .automatic)
            pattern = ""
            // A new rule sorts to the bottom of a long list — search for it so it is visible.
            search = keyword
            visible = Self.page
            await model.invalidate()
            await load()
        } catch {
            model.handle(error)
            model.show(error.localizedDescription, isError: true)
        }
    }
}
