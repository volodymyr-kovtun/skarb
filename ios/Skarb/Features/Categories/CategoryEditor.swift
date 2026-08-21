import SwiftUI

struct CategoryEditor: View {
    let category: CategoryWithCount?
    let kind: CategoryKind

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "🏷️"
    @State private var color = Palette.categoryColors[0]
    @State private var selectedKind: CategoryKind = .expense
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingDelete = false
    @State private var loaded = false

    private var isEdit: Bool { category != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        TextField("🏷️", text: $emoji)
                            .font(.system(size: 26))
                            .multilineTextAlignment(.center)
                            .frame(width: 56)
                            .onChange(of: emoji) { _, new in
                                emoji = String(new.prefix(2))
                            }
                        TextField("Coffee", text: $name)
                    }
                }

                Section("Type") {
                    Picker("Type", selection: $selectedKind) {
                        Text("Spending").tag(CategoryKind.expense)
                        Text("Income").tag(CategoryKind.income)
                        Text("Investment").tag(CategoryKind.investment)
                    }
                    .pickerStyle(.segmented)
                    if selectedKind == .investment {
                        Text("Counts as \"Invested\", never as spending.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.faint)
                    }
                }

                Section("Color") {
                    ColorSwatchPicker(colors: Palette.categoryColors, selection: $color)
                }

                if isEdit {
                    Section {
                        Button("Delete category", role: .destructive) { confirmingDelete = true }
                    }
                }

                if let error {
                    Section { FormError(error).listRowInsets(EdgeInsets()) }
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(isEdit ? "Edit category" : "New category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(busy ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(busy)
                }
            }
            .confirmationDialog(deleteWarning, isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await remove() } }
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            selectedKind = kind
            guard let category else { return }
            name = category.name
            emoji = category.emoji
            color = category.color
        }
    }

    private var deleteWarning: String {
        guard let category else { return "" }
        let uses = category.transactionCount
        return uses > 0
            ? "Delete “\(category.name)”? \(uses) transaction\(uses == 1 ? "" : "s") will become uncategorized."
            : "Delete “\(category.name)”?"
    }

    private func save() async {
        guard !name.trimmed.isEmpty else {
            error = "Name is required."
            return
        }
        busy = true
        defer { busy = false }
        error = nil
        let body = CategoryBody(
            name: name.trimmed,
            emoji: emoji.isEmpty ? "🏷️" : emoji,
            color: color,
            kind: selectedKind)
        do {
            if let category {
                try await APIClient.shared.updateCategory(category.id, body)
            } else {
                try await APIClient.shared.createCategory(body)
            }
            await model.invalidate()
            dismiss()
        } catch {
            model.handle(error)
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        guard let category else { return }
        await model.perform("Category deleted") {
            try await APIClient.shared.deleteCategory(category.id)
        }
        dismiss()
    }
}

struct TagEditor: View {
    let tag: Tag?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var color = Palette.categoryColors[0]
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingDelete = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("vacation", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Color") {
                    ColorSwatchPicker(colors: Palette.categoryColors, selection: $color)
                }

                if tag != nil {
                    Section {
                        Button("Delete tag", role: .destructive) { confirmingDelete = true }
                    }
                }

                if let error {
                    Section { FormError(error).listRowInsets(EdgeInsets()) }
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(tag.map { "Edit #\($0.name)" } ?? "New tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(busy ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(busy)
                }
            }
            .confirmationDialog(
                tag.map { "Delete #\($0.name)? Its transactions keep their history, they just lose the label." } ?? "",
                isPresented: $confirmingDelete, titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { Task { await remove() } }
            }
        }
        .task {
            guard !loaded, let tag else {
                loaded = true
                return
            }
            loaded = true
            name = tag.name
            color = tag.color
        }
    }

    private func save() async {
        guard !name.trimmed.isEmpty else {
            error = "Give the tag a name."
            return
        }
        busy = true
        defer { busy = false }
        error = nil
        do {
            if let tag {
                try await APIClient.shared.updateTag(tag.id, name: name.trimmed, color: color)
            } else {
                try await APIClient.shared.createTag(name: name.trimmed, color: color)
            }
            await model.invalidate()
            dismiss()
        } catch {
            model.handle(error)
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        guard let tag else { return }
        await model.perform("Tag deleted") {
            try await APIClient.shared.deleteTag(tag.id)
        }
        dismiss()
    }
}
