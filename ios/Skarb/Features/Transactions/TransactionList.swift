import SwiftUI

/// Loads one filtered page of transactions at a time and keeps what it already has, so the
/// list grows as it is scrolled instead of paging in and out.
@Observable
final class TransactionPageLoader {
    static let pageSize = 50

    private(set) var items: [Tx] = []
    private(set) var total = 0
    private(set) var loading = false
    private(set) var loadedOnce = false
    private(set) var error: String?

    private let service: any TransactionService
    @ObservationIgnored private var filter = TransactionFilter()
    @ObservationIgnored private var nextPage = 1
    /// Bumped by every reload. A page that comes back for an older generation belongs to a filter
    /// nobody is looking at any more, and is dropped — so a filter changed twice quickly shows the
    /// second answer, not whichever request happens to land last.
    @ObservationIgnored private var generation = 0

    init(service: any TransactionService) {
        self.service = service
    }

    var hasMore: Bool { items.count < total }
    var remaining: Int { max(total - items.count, 0) }
    var days: [TransactionDay] { TransactionDay.group(items) }

    /// Starts over on `filter`. What is on screen stays until the new first page arrives, so a
    /// reload after an edit never flashes the list empty.
    func reload(_ filter: TransactionFilter) async {
        generation += 1
        let generation = generation
        self.filter = filter
        loading = true
        defer { if generation == self.generation { loading = false } }
        do {
            let page = try await service.page(filter, page: 1, pageSize: Self.pageSize)
            guard generation == self.generation else { return }
            items = page.items
            total = page.total
            nextPage = 2
            error = nil
            loadedOnce = true
        } catch {
            guard generation == self.generation, !error.isCancellation else { return }
            self.error = error.localizedDescription
            loadedOnce = true
        }
    }

    func loadMore() async {
        guard !loading, hasMore else { return }
        let generation = generation
        loading = true
        defer { if generation == self.generation { loading = false } }
        do {
            let page = try await service.page(filter, page: nextPage, pageSize: Self.pageSize)
            guard generation == self.generation else { return }
            // A transaction that arrived since the first page shifts every offset by one, which
            // would show its neighbour twice; ids decide what is already here.
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            total = page.total
            nextPage += 1
        } catch {
            guard generation == self.generation, !error.isCancellation else { return }
            self.error = error.localizedDescription
        }
    }
}

extension AppContainer {
    func makePageLoader() -> TransactionPageLoader { TransactionPageLoader(service: transactions) }
}

/// The transactions themselves, grouped into days. Shared by the Activity tab and by every
/// list reached from a slice of the spending ring.
struct TransactionList: View {
    let loader: TransactionPageLoader
    /// Non-nil while the list is in selection mode.
    var selection: BulkSelection?
    var onTap: (Tx) -> Void
    var onToggleDay: (([UUID]) -> Void)?
    /// Long-press "Select" on a row, which starts selection mode with that row ticked.
    var onSelectFromMenu: ((Tx) -> Void)?

    var body: some View {
        Card {
            // Lazy, so a long history only builds the rows in view — and so the footer below only
            // appears, and fetches the next page, once it is actually scrolled to.
            LazyVStack(alignment: .leading, spacing: 0) {
                if let error = loader.error, loader.items.isEmpty {
                    EmptyNote(text: error)
                } else if loader.items.isEmpty {
                    if loader.loadedOnce && !loader.loading {
                        EmptyNote(text: "Nothing here yet. Adjust the filters, or add a transaction.")
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 44)
                    }
                } else {
                    ForEach(loader.days) { day in
                        dayHeader(day)
                        ForEach(day.items) { tx in
                            row(tx)
                        }
                    }
                    footer
                }
            }
            .padding(.bottom, 10)
        }
    }

    private func dayHeader(_ day: TransactionDay) -> some View {
        HStack(alignment: .firstTextBaseline) {
            MicroLabel(Format.dayLabel(day.date))
            Spacer()
            if let selection, let onToggleDay {
                Button(selection.containsAll(day.ids) ? "Clear day" : "Select day") {
                    onToggleDay(day.ids)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func row(_ tx: Tx) -> some View {
        let row = TransactionRow(tx: tx, selected: selection.map { $0.contains(tx.id) }) { onTap(tx) }
        if selection == nil, let onSelectFromMenu {
            row.contextMenu {
                Button { onTap(tx) } label: { Label("Edit", systemImage: "pencil") }
                Button { onSelectFromMenu(tx) } label: { Label("Select", systemImage: "checkmark.circle") }
            }
        } else {
            row
        }
    }

    @ViewBuilder
    private var footer: some View {
        if loader.hasMore {
            Button {
                Task { await loader.loadMore() }
            } label: {
                HStack(spacing: 8) {
                    if loader.loading { ProgressView().controlSize(.small) }
                    Text(loader.loading ? "Loading…" : "Show more (\(loader.remaining) left)")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .disabled(loader.loading)
            // Reaching the end of what is loaded fetches the next page by itself; the button is
            // there for when it can't, and to say how much is left.
            .onAppear { Task { await loader.loadMore() } }
        }
    }
}

/// A filtered list pushed from somewhere else — a wedge of the spending ring, an account.
struct FilteredTransactionsScreen: View {
    let title: String
    let filter: TransactionFilter
    @Environment(AppContainer.self) private var app

    var body: some View {
        FilteredTransactionsContent(title: title, filter: filter, loader: app.makePageLoader())
    }
}

private struct FilteredTransactionsContent: View {
    let title: String
    let filter: TransactionFilter
    @State private var loader: TransactionPageLoader
    @State private var editing: Tx?
    @Environment(AppContainer.self) private var app
    @Environment(LedgerStore.self) private var ledger

    init(title: String, filter: TransactionFilter, loader: TransactionPageLoader) {
        self.title = title
        self.filter = filter
        _loader = State(initialValue: loader)
    }

    var body: some View {
        ScrollView {
            TransactionList(loader: loader) { editing = $0 }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 96)
        }
        .background(Palette.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await ledger.invalidate() }
        .task(id: "\(ledger.revision)|\(filter.key)") { await loader.reload(filter) }
        .sheet(item: $editing) { TransactionEditor(model: app.makeTransactionEditor(for: $0)) }
    }
}
