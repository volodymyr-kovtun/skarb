import SwiftUI

/// What a selection can have done to it: file it, tag it, mark it internal, exclude it.
///
/// Every choice applies the moment it is picked and keeps the selection, as on the web. Each
/// action's opposite sits in the same menu, because the opposite is the undo — except for a
/// category, whose undo comes back in the toast.
struct BulkActionBar: View {
    @Bindable var model: TransactionsModel
    @Environment(LedgerStore.self) private var ledger
    @State private var namingTag = false
    @State private var newTagName = ""

    private var idle: Bool { model.selection.isEmpty || model.bulkBusy }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("\(model.selection.count) selected")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                if model.list.total > model.selection.count {
                    Button("Select all \(model.list.total)") { Task { await model.selectAllMatching() } }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .disabled(model.bulkBusy)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if model.bulkBusy { ProgressView().controlSize(.small) }
            }

            HStack(spacing: 8) {
                categoryMenu
                tagMenu
                internalMenu
                excludeMenu
            }
            .disabled(idle)
            .opacity(idle ? 0.45 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .animation(.smooth(duration: 0.2), value: model.selection.count)
        .sensoryFeedback(.selection, trigger: model.selection.count)
        .alert("New tag", isPresented: $namingTag) {
            TextField("vacation", text: $newTagName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add") {
                let name = newTagName
                newTagName = ""
                Task { await model.addNewTag(named: name) }
            }
            Button("Cancel", role: .cancel) { newTagName = "" }
        } message: {
            Text("It goes onto every selected transaction.")
        }
    }

    // MARK: - Menus

    private var categoryMenu: some View {
        Menu {
            // Every kind is offered whatever was selected: the selection can run across pages the
            // list no longer holds, so there is no telling from here whether it is money in, out,
            // or both.
            ForEach(CategoryKind.allCases) { kind in
                let inKind = ledger.categories.filter { $0.kind == kind }
                if !inKind.isEmpty {
                    Section(kind.title) {
                        ForEach(inKind) { category in
                            Button(category.label) { run(.file(category)) }
                        }
                    }
                }
            }
            Section {
                Button("· Uncategorized") { run(.file(nil)) }
            }
        } label: {
            ActionTile(title: "Category", icon: "square.grid.2x2")
        }
    }

    private var tagMenu: some View {
        Menu {
            Section {
                Button { namingTag = true } label: { Label("New tag…", systemImage: "plus") }
            }
            if !ledger.tags.isEmpty {
                Menu("Add a tag") {
                    ForEach(ledger.tags) { tag in
                        Button("#\(tag.name)") { run(.addTag(tag)) }
                    }
                }
                // Removing is the undo for a tag that went on by mistake, so it is one level away.
                Menu("Remove a tag") {
                    ForEach(ledger.tags) { tag in
                        Button("#\(tag.name)", role: .destructive) { run(.removeTag(tag)) }
                    }
                }
            }
        } label: {
            ActionTile(title: "Tag", icon: "tag")
        }
    }

    private var internalMenu: some View {
        Menu {
            Section("Never counted. Un-marking one side of a pair releases the other too.") {
                Button { run(.markInternal(true)) } label: {
                    Label("Internal transfer", systemImage: "arrow.left.arrow.right")
                }
                Button { run(.markInternal(false)) } label: {
                    Label("Not a transfer", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            ActionTile(title: "Internal", icon: "arrow.left.arrow.right")
        }
    }

    private var excludeMenu: some View {
        Menu {
            Section("For a reimbursement or a correction: it stays listed and leaves every total.") {
                Button { run(.exclude(true)) } label: { Label("Exclude from stats", systemImage: "eye.slash") }
                Button { run(.exclude(false)) } label: { Label("Count again", systemImage: "eye") }
            }
        } label: {
            ActionTile(title: "Exclude", icon: "eye.slash")
        }
    }

    private func run(_ action: BulkAction) {
        Task { await model.apply(action) }
    }
}

/// An icon over its word, at a quarter of the bar each — side by side, a quarter of a phone's
/// width leaves room for "Cat…" and "Excl…", which is no label at all.
private struct ActionTile: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium))
            Text(title).font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Palette.surface2.opacity(0.7), in: .rect(cornerRadius: Palette.Radius.row))
        .contentShape(.rect)
    }
}
