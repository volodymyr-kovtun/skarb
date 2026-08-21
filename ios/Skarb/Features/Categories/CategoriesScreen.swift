import SwiftUI

/// How your money gets labeled: the three kinds of category, the free-form tags beside them,
/// and the keyword rules that do the filing.
struct CategoriesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var categories: [CategoryWithCount] = []
    @State private var editing: CategoryWithCount?
    @State private var addingKind: CategoryKind?
    @State private var editingTag: Tag?
    @State private var addingTag = false

    var body: some View {
        SkarbScreen(title: "Categories") {
            Text("How your money gets labeled. New bank transactions are categorized automatically by your rules and card codes.")
                .font(.system(size: 14.5))
                .foregroundStyle(Palette.muted)
                .lineSpacing(3)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach([CategoryKind.expense, .investment, .income], id: \.self) { kind in
                kindCard(kind)
            }

            tagsCard

            Card {
                NavigationLink {
                    RulesScreen()
                } label: {
                    SettingsRow(
                        title: "Auto-categorization rules",
                        subtitle: "Keywords that file new transactions on arrival",
                        icon: "wand.and.sparkles") { DisclosureChevron() }
                }
                .buttonStyle(RowButtonStyle())
                .padding(.vertical, 4)
            }
        }
        .task(id: model.revision) { await load() }
        .sheet(item: $editing) { category in
            CategoryEditor(category: category, kind: category.kind)
        }
        .sheet(item: $addingKind) { kind in
            CategoryEditor(category: nil, kind: kind)
        }
        .sheet(item: $editingTag) { TagEditor(tag: $0) }
        .sheet(isPresented: $addingTag) { TagEditor(tag: nil) }
    }

    private func kindCard(_ kind: CategoryKind) -> some View {
        let items = categories.filter { $0.kind == kind }
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: kind.title) {
                    Button { addingKind = kind } label: {
                        Label("Add", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                    }
                }

                Text(kind.blurb)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.faint)
                    .lineSpacing(2)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                if items.isEmpty {
                    EmptyNote(text: "No categories yet.")
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(items) { item in
                            Button { editing = item } label: {
                                HStack(spacing: 10) {
                                    CategoryDot(category: item.category, size: 34)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name)
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundStyle(Palette.ink)
                                            .lineLimit(1)
                                        Text(item.transactionCount == 0
                                            ? "unused"
                                            : "\(item.transactionCount) transaction\(item.transactionCount == 1 ? "" : "s")")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Palette.faint)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.surface2, in: .rect(cornerRadius: Palette.Radius.row))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 18)
        }
    }

    /// Tags live next to categories because they answer the same question one step finer.
    /// Attaching one happens in the transaction editor; this is where they get tidied up.
    private var tagsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Tags") {
                    Button { addingTag = true } label: {
                        Label("Add", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                Text("Free-form labels, finer than a category and stackable — #vacation, #renovation. Attach them in the transaction editor; the overview reports what each one costs.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.faint)
                    .lineSpacing(2)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                if model.tags.isEmpty {
                    EmptyNote(text: "No tags yet.")
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(model.tags) { tag in
                            Button { editingTag = tag } label: {
                                Text("#\(tag.name)")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(HSL.swatch(tag.color))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(HSL.tint(tag.color), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 18)
        }
    }

    private func load() async {
        do {
            categories = try await APIClient.shared.categories()
        } catch {
            model.handle(error)
        }
    }
}

// `sheet(item:)` needs an identity to key off; a kind is its own.
extension CategoryKind: Identifiable {
    var id: String { rawValue }
}
