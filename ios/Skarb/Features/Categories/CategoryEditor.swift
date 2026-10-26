import SwiftUI

@Observable
final class CategoryEditorModel {
    let original: CategoryWithCount?
    var name = ""
    var emoji = "🏷️"
    var color = Palette.categoryColors[0]
    var kind: CategoryKind
    private(set) var busy = false
    private(set) var error: String?

    private let service: any CategoryService
    private let ledger: LedgerStore
    private let actions: ActionRunner

    init(category: CategoryWithCount?, kind: CategoryKind, service: any CategoryService,
         ledger: LedgerStore, actions: ActionRunner) {
        original = category
        self.kind = kind
        self.service = service
        self.ledger = ledger
        self.actions = actions
        guard let category else { return }
        name = category.name
        emoji = category.emoji
        color = category.color
    }

    var isEdit: Bool { original != nil }

    /// One emoji, however many code points it takes — a flag or a skin tone is two or more. The
    /// field already holds one, so the newest character typed is the one meant.
    func setEmoji(_ text: String) {
        emoji = text.last.map(String.init) ?? ""
    }

    var deleteWarning: String {
        guard let original else { return "" }
        let uses = original.transactionCount
        return uses > 0
            ? "Delete “\(original.name)”? \(uses) transaction\(uses == 1 ? "" : "s") will become uncategorized."
            : "Delete “\(original.name)”?"
    }

    func save() async -> Bool {
        guard !name.trimmed.isEmpty else {
            error = "Name is required."
            return false
        }
        busy = true
        error = nil
        defer { busy = false }
        let body = CategoryBody(name: name.trimmed, emoji: emoji.isEmpty ? "🏷️" : emoji, color: color, kind: kind)
        do {
            if let original {
                _ = try await service.update(original.id, body)
            } else {
                _ = try await service.create(body)
            }
            await ledger.invalidate()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func delete() async -> Bool {
        guard let original else { return false }
        return await actions.perform("Category deleted") { try await service.delete(original.id) }
    }
}

@Observable
final class TagEditorModel {
    let original: Tag?
    var name = ""
    var color = Palette.categoryColors[0]
    private(set) var busy = false
    private(set) var error: String?

    private let service: any TagService
    private let ledger: LedgerStore
    private let actions: ActionRunner

    init(tag: Tag?, service: any TagService, ledger: LedgerStore, actions: ActionRunner) {
        original = tag
        self.service = service
        self.ledger = ledger
        self.actions = actions
        guard let tag else { return }
        name = tag.name
        color = tag.color
    }

    var title: String { original.map { "Edit #\($0.name)" } ?? "New tag" }

    var deleteWarning: String {
        original.map { "Delete #\($0.name)? Its transactions keep their history, they just lose the label." } ?? ""
    }

    func save() async -> Bool {
        guard !name.trimmed.isEmpty else {
            error = "Give the tag a name."
            return false
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            if let original {
                _ = try await service.update(original.id, name: name.trimmed, color: color)
            } else {
                _ = try await service.create(name: name.trimmed, color: color)
            }
            await ledger.invalidate()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func delete() async -> Bool {
        guard let original else { return false }
        return await actions.perform("Tag deleted") { try await service.delete(original.id) }
    }
}

extension AppContainer {
    func makeCategoryEditor(for category: CategoryWithCount?, kind: CategoryKind) -> CategoryEditorModel {
        CategoryEditorModel(category: category, kind: kind, service: categories, ledger: ledger, actions: actions)
    }

    func makeTagEditor(for tag: Tag?) -> TagEditorModel {
        TagEditorModel(tag: tag, service: tags, ledger: ledger, actions: actions)
    }
}

struct CategoryEditor: View {
    @State private var model: CategoryEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    init(model: CategoryEditorModel) { _model = State(initialValue: model) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        TextField("🏷️", text: Binding(get: { model.emoji }, set: { model.setEmoji($0) }))
                            .font(.system(size: 26))
                            .multilineTextAlignment(.center)
                            .frame(width: 56)
                        TextField("Coffee", text: $model.name)
                    }
                }

                Section("Type") {
                    Picker("Type", selection: $model.kind) {
                        Text("Spending").tag(CategoryKind.expense)
                        Text("Income").tag(CategoryKind.income)
                        Text("Investment").tag(CategoryKind.investment)
                    }
                    .pickerStyle(.segmented)
                    if model.kind == .investment {
                        Text("Counts as \"Invested\", never as spending.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.faint)
                    }
                }

                Section("Color") {
                    ColorSwatchPicker(colors: Palette.categoryColors, selection: $model.color)
                }

                if model.isEdit {
                    Section {
                        Button("Delete category", role: .destructive) { confirmingDelete = true }
                    }
                }

                if let error = model.error {
                    Section { FormError(error).listRowInsets(EdgeInsets()) }
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(model.isEdit ? "Edit category" : "New category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.busy ? "Saving…" : "Save") { Task { if await model.save() { dismiss() } } }
                        .fontWeight(.semibold)
                        .disabled(model.busy)
                }
            }
            .confirmationDialog(model.deleteWarning, isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { if await model.delete() { dismiss() } } }
            }
        }
    }
}

struct TagEditor: View {
    @State private var model: TagEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    init(model: TagEditorModel) { _model = State(initialValue: model) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("vacation", text: $model.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Color") {
                    ColorSwatchPicker(colors: Palette.categoryColors, selection: $model.color)
                }

                if model.original != nil {
                    Section {
                        Button("Delete tag", role: .destructive) { confirmingDelete = true }
                    }
                }

                if let error = model.error {
                    Section { FormError(error).listRowInsets(EdgeInsets()) }
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.busy ? "Saving…" : "Save") { Task { if await model.save() { dismiss() } } }
                        .fontWeight(.semibold)
                        .disabled(model.busy)
                }
            }
            .confirmationDialog(model.deleteWarning, isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { if await model.delete() { dismiss() } } }
            }
        }
    }
}
