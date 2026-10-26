import SwiftUI

@Observable
final class CategoriesModel {
    private(set) var categories: [CategoryWithCount] = []
    private let service: any CategoryService

    init(service: any CategoryService) {
        self.service = service
    }

    func load() async {
        if let fresh = try? await service.categories() { categories = fresh }
    }

    func categories(of kind: CategoryKind) -> [CategoryWithCount] {
        categories.filter { $0.kind == kind }
    }
}

extension AppContainer {
    func makeCategories() -> CategoriesModel { CategoriesModel(service: categories) }
}

/// How your money gets labeled: the three kinds of category, the free-form tags beside them,
/// and the keyword rules that do the filing.
struct CategoriesScreen: View {
    @State private var model: CategoriesModel
    @Environment(AppContainer.self) private var app
    @Environment(LedgerStore.self) private var ledger
    @State private var editing: CategoryWithCount?
    @State private var addingKind: CategoryKind?
    @State private var editingTag: Tag?
    @State private var addingTag = false

    init(model: CategoriesModel) { _model = State(initialValue: model) }

    var body: some View {
        SkarbScreen(title: "Categories") {
            Text("How your money gets labeled. New bank transactions are categorized automatically by your rules and card codes.")
                .font(.system(size: 14.5))
                .foregroundStyle(Palette.muted)
                .lineSpacing(3)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach([CategoryKind.expense, .investment, .income]) { kind in
                kindCard(kind)
            }

            tagsCard

            Card {
                NavigationLink {
                    RulesScreen(model: app.makeRules())
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
        .task(id: ledger.revision) { await model.load() }
        .sheet(item: $editing) { item in
            CategoryEditor(model: app.makeCategoryEditor(for: item, kind: item.kind))
        }
        .sheet(item: $addingKind) { kind in
            CategoryEditor(model: app.makeCategoryEditor(for: nil, kind: kind))
        }
        .sheet(item: $editingTag) { TagEditor(model: app.makeTagEditor(for: $0)) }
        .sheet(isPresented: $addingTag) { TagEditor(model: app.makeTagEditor(for: nil)) }
    }

    private func kindCard(_ kind: CategoryKind) -> some View {
        let items = model.categories(of: kind)
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
                            Button { editing = item } label: { categoryTile(item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 18)
        }
    }

    private func categoryTile(_ item: CategoryWithCount) -> some View {
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

    /// Tags live next to categories because they answer the same question one step finer.
    /// Attaching one happens in the transaction editor or on the bulk bar; this is where they
    /// get tidied up.
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

                if ledger.tags.isEmpty {
                    EmptyNote(text: "No tags yet.")
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(ledger.tags) { tag in
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
}
