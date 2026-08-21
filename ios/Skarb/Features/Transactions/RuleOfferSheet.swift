import SwiftUI

/// Offered after a category is changed by hand: turn that one correction into a keyword rule
/// that files the matching transactions you already have, and every one that arrives from now on.
///
/// It opens *after* the save has landed, so closing it costs nothing — the transaction stays
/// corrected either way. The keyword is editable and the counts under it are recomputed by the
/// server as it changes, so the guess never has to be right, only correctable.
struct RuleOfferSheet: View {
    let tx: Tx
    let category: Category
    let initial: RuleSuggestion

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var pattern = ""
    @State private var view: RuleSuggestion?
    @State private var counting = false
    @State private var applyPast = true
    @State private var includeUntouched = false
    @State private var busy = false
    @State private var error: String?

    private var current: RuleSuggestion { view ?? initial }
    private var counts: RuleMatchCounts { current.matches }
    private var automatic: Int { counts.uncategorized + counts.automatic }
    private var matched: Int { automatic + counts.untouched }
    /// What the toggle would actually rewrite — hand-sorted rows are held back until asked for.
    private var changing: Int { includeUntouched ? matched : automatic }
    private var scope: RuleScope { !applyPast ? .none : (includeUntouched ? .all : .automatic) }
    private var existing: RuleSuggestion.ExistingRule? { current.existingRule }

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
                        if matched > 0 { pastToggle }
                        if let error { FormError(error) }
                    }
                    .padding(20)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(existing == nil
                ? "Always file this as \(category.emoji) \(category.name)?"
                : "Point “\(existing!.pattern)” elsewhere?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(existing == nil ? "Not now" : "Keep both") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(busy ? "Saving…" : (existing == nil ? "Create rule" : "Update rule")) {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(busy || pattern.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { if pattern.isEmpty { pattern = initial.pattern ?? "" } }
        // Typing a keyword shouldn't fire a count request per keystroke.
        .task(id: pattern) {
            let keyword = pattern.trimmed
            guard !keyword.isEmpty, keyword != initial.pattern else { return }
            counting = true
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            defer { counting = false }
            // Keep the previous counts on screen while the next ones load, so editing the
            // keyword never blanks the sheet out from under the cursor.
            if let fresh = try? await APIClient.shared.ruleSuggestion(for: tx.id, pattern: keyword) {
                view = fresh
            }
        }
    }

    @ViewBuilder
    private var preamble: some View {
        if let existing {
            let keyword = Text(existing.pattern).fontWeight(.semibold).foregroundStyle(Palette.ink)
            Text("A rule already sends \(keyword) to \(existing.category.emoji) \(existing.category.name). Changing it keeps one rule instead of two that disagree.")
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
                TextField("Which word identifies this merchant?", text: $pattern)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(counting ? "counting…" : "\(matched) match\(matched == 1 ? "" : "es")")
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
        if !current.alternatives.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(current.alternatives, id: \.self) { alternative in
                    Button { pattern = alternative } label: {
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
        if !current.sample.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(current.sample) { TransactionRow(tx: $0) }
                    if matched > current.sample.count {
                        Text("and \(matched - current.sample.count) more")
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
            Toggle(isOn: $applyPast) {
                Text("Also file the \(changing) I already have")
                    .font(.system(size: 14, weight: .semibold))
            }
            .tint(Palette.accent)

            /// Says which of the matches are guesses and which are decisions, so neither is a surprise.
            Text(breakdown)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.faint)
                .lineSpacing(2)

            if counts.untouched > 0 {
                Button(includeUntouched ? "Leave those alone" : "Include those too") {
                    includeUntouched.toggle()
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.accent)
            }
        }
        .padding(14)
        .background(Palette.surface, in: .rect(cornerRadius: Palette.Radius.row))
    }

    private var breakdown: String {
        var parts: [String] = []
        if counts.uncategorized > 0 { parts.append("\(counts.uncategorized) uncategorized") }
        if counts.automatic > 0 { parts.append("\(counts.automatic) filed automatically") }
        let lead = parts.isEmpty ? "" : parts.joined(separator: ", ") + "."
        guard counts.untouched > 0 else { return lead }
        let them = counts.untouched == 1 ? "it is" : "they are"
        let tail = "\(counts.untouched) you sorted by hand "
            + (includeUntouched ? "will be re-filed too." : "stay as \(them).")
        return lead.isEmpty ? tail : lead + " " + tail
    }

    private func save() async {
        busy = true
        defer { busy = false }
        error = nil
        let keyword = pattern.trimmed
        do {
            let result: RuleApplied
            if let existing {
                result = try await APIClient.shared.updateRule(
                    existing.id, categoryId: category.id, pattern: keyword, applyTo: scope)
            } else {
                result = try await APIClient.shared.createRule(
                    pattern: keyword, categoryId: category.id, applyTo: scope)
            }
            // Captured before the refresh: invalidating drops the suggestion, and the refetched
            // one no longer mentions the rule that was just created or repointed.
            let previous = existing
            await model.invalidate()
            dismiss()
            // Rewriting a pile of transactions on one tap needs a way back. The apply already
            // returned every row it touched and what it was filed as before, so undo is that
            // list handed straight back.
            let message = result.applied > 0
                ? "Rule saved · \(result.applied) transaction\(result.applied == 1 ? "" : "s") re-filed"
                : "Rule saved"
            model.show(message, undoLabel: "Undo") { [model] in
                await model.perform {
                    // Put the rule back where it was — repointed if it already existed, deleted
                    // if this created it — then restore every category this run rewrote.
                    if let previous {
                        try await APIClient.shared.updateRule(
                            previous.id, categoryId: previous.category.id, pattern: nil, applyTo: .none)
                    } else {
                        try await APIClient.shared.deleteRule(result.id)
                    }
                    if !result.reverts.isEmpty {
                        try await APIClient.shared.revertRules(result.reverts)
                    }
                }
            }
        } catch {
            model.handle(error)
            self.error = error.localizedDescription
        }
    }
}
