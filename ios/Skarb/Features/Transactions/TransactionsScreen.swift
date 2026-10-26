import SwiftUI

/// Every transaction, searchable and narrowable, and editable a selection at a time. This is the
/// one screen that owns its own navigation stack rather than borrowing `SkarbScreen`, because
/// `.searchable` has to be attached inside the stack it belongs to.
struct TransactionsScreen: View {
    @State private var model: TransactionsModel
    @State private var editing: Tx?
    @State private var adding = false
    @State private var pickingTags = false

    @Environment(AppContainer.self) private var app
    @Environment(LedgerStore.self) private var ledger
    @Environment(AppRouter.self) private var router

    init(model: TransactionsModel) { _model = State(initialValue: model) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TransactionFilterBar(model: model) { pickingTags = true }
                    TransactionList(
                        loader: model.list,
                        selection: model.selecting ? model.selection : nil,
                        onTap: { tx in
                            if model.selecting { model.toggle(tx) } else { editing = tx }
                        },
                        onToggleDay: { model.toggleDay($0) },
                        onSelectFromMenu: { model.startSelecting(with: $0.id) })
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, model.selecting ? 24 : 96)
            }
            .background(Palette.paper)
            .navigationTitle(model.selecting ? selectionTitle : "Activity")
            .searchable(
                text: $model.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Description, merchant or note")
            .toolbar { toolbar }
            // Selection replaces the tab bar with the actions, the way Photos and Files do: the
            // thumb is already at the bottom after ticking rows, and the rows stay in view above.
            .toolbar(model.selecting ? .hidden : .visible, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                if model.selecting {
                    BulkActionBar(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: model.selecting)
            .refreshable { await ledger.invalidate() }
        }
        // Debounced so a search doesn't fire a request per keystroke.
        .task(id: model.searchText) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            model.applySearch()
        }
        .task(id: "\(ledger.revision)|\(model.activeFilter.key)") { await model.reload() }
        .onChange(of: router.pendingActivityFilter, initial: true) { _, _ in
            if let filter = router.takeActivityFilter() { model.open(filter) }
        }
        .sheet(item: $editing) { tx in
            TransactionEditor(model: app.makeTransactionEditor(for: tx)) { recategorized in
                Task { await model.offerRule(for: recategorized) }
            }
        }
        .sheet(isPresented: $adding) { TransactionEditor(model: app.makeTransactionEditor(for: nil)) }
        .sheet(isPresented: $pickingTags) {
            TagPickerSheet(selected: $model.filter.tagIds, tags: ledger.tags, title: "Filter by tag")
        }
        .sheet(item: $model.ruleOffer) { offer in
            RuleOfferSheet(model: app.makeRuleOffer(offer))
        }
    }

    private var selectionTitle: String {
        model.selection.isEmpty ? "Select" : "\(model.selection.count) selected"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.selecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { model.stopSelecting() }
                    .fontWeight(.semibold)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) { SyncButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.startSelecting() } label: { Image(systemName: "checkmark.circle") }
                    .accessibilityLabel("Select several transactions")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add transaction")
            }
        }
    }
}

// MARK: - Filters

private struct TransactionFilterBar: View {
    @Bindable var model: TransactionsModel
    var pickTags: () -> Void
    @Environment(LedgerStore.self) private var ledger

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                accountMenu
                categoryMenu
                if !ledger.tags.isEmpty { tagsPill }
                internalPill
                if model.hasNarrowing { clearPill }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var accountMenu: some View {
        Menu {
            Picker("Account", selection: $model.filter.accountId) {
                Text("All accounts").tag(UUID?.none)
                ForEach(ledger.accounts) { account in
                    Text(account.label).tag(UUID?.some(account.id))
                }
            }
        } label: {
            pillLabel(
                icon: "building.columns",
                text: ledger.account(model.filter.accountId)?.name ?? "Account",
                on: model.filter.accountId != nil)
        }
    }

    private var categoryMenu: some View {
        Menu {
            Picker("Category", selection: categorySelection) {
                Text("All categories").tag(CategoryChoice.all)
                ForEach(TransactionFilter.Special.allCases, id: \.self) { special in
                    Text(special.menuLabel).tag(CategoryChoice.special(special))
                }
                Divider()
                ForEach(ledger.categories) { category in
                    Text(category.label).tag(CategoryChoice.category(category.id))
                }
            }
        } label: {
            pillLabel(
                icon: "square.grid.2x2", text: categoryLabel,
                on: model.filter.categoryId != nil || model.filter.special != nil)
        }
    }

    private var tagsPill: some View {
        FilterPill(isOn: !model.filter.tagIds.isEmpty, action: pickTags) {
            let picked = ledger.tags.filter { model.filter.tagIds.contains($0.id) }
            Label(
                picked.isEmpty ? "Tags" : (picked.count == 1 ? "#\(picked[0].name)" : "\(picked.count) tags"),
                systemImage: "tag")
        }
    }

    /// Drops transfers between your own accounts, leaving only real money in and out.
    private var internalPill: some View {
        FilterPill(isOn: model.filter.hideInternal && model.filter.canHideInternal) {
            model.filter.hideInternal.toggle()
        } label: {
            Label("Hide internal", systemImage: "arrow.left.arrow.right")
        }
        .disabled(!model.filter.canHideInternal)
        .opacity(model.filter.canHideInternal ? 1 : 0.4)
    }

    private var clearPill: some View {
        FilterPill { model.clearFilters() } label: {
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
            if let special = model.filter.special { return .special(special) }
            if let id = model.filter.categoryId { return .category(id) }
            return .all
        } set: { choice in
            switch choice {
            case .all:
                model.filter.categoryId = nil
                model.filter.special = nil
            case .special(let special):
                model.filter.categoryId = nil
                model.filter.special = special
            case .category(let id):
                model.filter.special = nil
                model.filter.categoryId = id
            }
        }
    }

    private var categoryLabel: String {
        if let special = model.filter.special { return special.label }
        return ledger.category(model.filter.categoryId)?.name ?? "Category"
    }
}

// MARK: - Tag picker

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
                            .accessibilityAddTraits(on ? [.isSelected] : [])
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
