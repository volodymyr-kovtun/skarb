import SwiftUI

/// Every transaction, searchable and narrowable. This is the one screen that owns its own
/// navigation stack rather than borrowing `SkarbScreen`, because `.searchable` has to be
/// attached inside the stack it belongs to.
struct TransactionsScreen: View {
    @Environment(AppModel.self) private var model

    @State private var filter = TransactionFilter()
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var editing: Tx?
    @State private var adding = false
    @State private var pickingTags = false
    /// A category was just changed by hand, and this is what Skarb would make of it. Held here
    /// rather than in the editor so the offer outlives the sheet that produced it.
    @State private var ruleOffer: RuleOffer?

    struct RuleOffer: Identifiable {
        let id = UUID()
        var tx: Tx
        var category: Category
        var suggestion: RuleSuggestion
    }

    private var activeFilter: TransactionFilter {
        var f = filter
        f.search = debouncedSearch
        return f
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    filterBar
                    TransactionList(filter: activeFilter, revision: model.revision) { editing = $0 }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 96)
            }
            .background(Palette.paper)
            .navigationTitle("Activity")
            .searchable(
                text: $search,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Description, merchant or note")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SyncButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add transaction")
                }
            }
            .refreshable { await model.invalidate() }
        }
        // Debounced so a search doesn't fire a request per keystroke.
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            debouncedSearch = search.trimmed
        }
        .sheet(item: $editing) { tx in
            TransactionEditor(tx: tx) { recategorized in
                Task { await offerRule(for: recategorized) }
            }
        }
        .sheet(isPresented: $adding) { TransactionEditor(tx: nil) }
        .sheet(isPresented: $pickingTags) {
            TagPickerSheet(selected: $filter.tagIds, tags: model.tags, title: "Filter by tag")
        }
        .sheet(item: $ruleOffer) { offer in
            RuleOfferSheet(tx: offer.tx, category: offer.category, initial: offer.suggestion)
        }
    }

    // MARK: - Filters

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                accountMenu
                categoryMenu
                if !model.tags.isEmpty { tagsPill }
                internalPill
                if !filter.isEmpty || !search.isEmpty { clearPill }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var accountMenu: some View {
        Menu {
            Picker("Account", selection: $filter.accountId) {
                Text("All accounts").tag(UUID?.none)
                ForEach(model.accounts) { account in
                    Text(account.label).tag(UUID?.some(account.id))
                }
            }
        } label: {
            pillLabel(
                icon: "building.columns",
                text: filter.accountId.flatMap { id in model.accounts.first { $0.id == id }?.name } ?? "Account",
                on: filter.accountId != nil)
        }
    }

    private var categoryMenu: some View {
        Menu {
            Picker("Category", selection: categorySelection) {
                Text("All categories").tag(CategoryChoice.all)
                Text("· Uncategorized").tag(CategoryChoice.special(.uncategorized))
                Text("🔁 Internal transfers").tag(CategoryChoice.special(.internalOnly))
                Text("📈 Investments").tag(CategoryChoice.special(.investmentsOnly))
                Divider()
                ForEach(model.categories) { category in
                    Text("\(category.emoji) \(category.name)").tag(CategoryChoice.category(category.id))
                }
            }
        } label: {
            pillLabel(icon: "square.grid.2x2", text: categoryLabel, on: filter.categoryId != nil || filter.special != nil)
        }
    }

    private var tagsPill: some View {
        FilterPill(isOn: !filter.tagIds.isEmpty) {
            pickingTags = true
        } label: {
            let picked = model.tags.filter { filter.tagIds.contains($0.id) }
            Label(
                picked.isEmpty ? "Tags" : (picked.count == 1 ? "#\(picked[0].name)" : "\(picked.count) tags"),
                systemImage: "tag")
        }
    }

    /// Drops transfers between your own accounts, leaving only real money in and out.
    private var internalPill: some View {
        FilterPill(isOn: filter.hideInternal) {
            filter.hideInternal.toggle()
        } label: {
            Label("Hide internal", systemImage: "arrow.left.arrow.right")
        }
        .disabled(filter.special == .internalOnly)
        .opacity(filter.special == .internalOnly ? 0.4 : 1)
    }

    private var clearPill: some View {
        FilterPill {
            filter = TransactionFilter()
            search = ""
        } label: {
            Label("Clear", systemImage: "xmark")
        }
    }

    private func pillLabel(icon: String, text: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(on ? Palette.paper : Palette.muted)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(on ? Palette.accent : Palette.surface2, in: .capsule)
    }

    /// The category pill drives two independent API filters, so its menu speaks one enum and
    /// unpacks it on the way back into the filter.
    private enum CategoryChoice: Hashable {
        case all
        case special(TransactionFilter.Special)
        case category(UUID)
    }

    private var categorySelection: Binding<CategoryChoice> {
        Binding {
            if let special = filter.special { return .special(special) }
            if let id = filter.categoryId { return .category(id) }
            return .all
        } set: { choice in
            switch choice {
            case .all:
                filter.categoryId = nil
                filter.special = nil
            case .special(let special):
                filter.categoryId = nil
                filter.special = special
            case .category(let id):
                filter.special = nil
                filter.categoryId = id
            }
        }
    }

    private var categoryLabel: String {
        if let special = filter.special {
            switch special {
            case .uncategorized: return "Uncategorized"
            case .internalOnly: return "Internal"
            case .investmentsOnly: return "Investments"
            }
        }
        if let id = filter.categoryId, let category = model.categories.first(where: { $0.id == id }) {
            return category.name
        }
        return "Category"
    }

    // MARK: - Rules

    /// After a category is set by hand, ask whether it should become a rule. The save has
    /// already landed, so this is pure upside: if there is nothing worth suggesting, or the
    /// suggestion can't be fetched, the transaction is simply left as corrected.
    private func offerRule(for tx: Tx) async {
        guard let category = tx.category else { return }
        guard let suggestion = try? await APIClient.shared.ruleSuggestion(for: tx.id),
              suggestion.pattern != nil
        else { return }
        ruleOffer = RuleOffer(tx: tx, category: category, suggestion: suggestion)
    }
}

/// Multi-select over the tags in use; picking several shows transactions carrying any of them.
struct TagPickerSheet: View {
    @Binding var selected: [UUID]
    let tags: [Tag]
    var title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()
                ScrollView {
                    FlowLayout(spacing: 8) {
                        ForEach(tags) { tag in
                            let on = selected.contains(tag.id)
                            Button {
                                if on { selected.removeAll { $0 == tag.id } } else { selected.append(tag.id) }
                            } label: {
                                Text("#\(tag.name)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(on ? Palette.paper : Palette.muted)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background(on ? HSL.swatch(tag.color) : Palette.surface2, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { selected = [] }.disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Wraps chips onto as many lines as they need — tags, color swatches, emoji.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
