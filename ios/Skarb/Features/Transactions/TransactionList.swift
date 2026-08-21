import SwiftUI

/// Loads one filtered page of transactions at a time and keeps what it already has, so the
/// list grows as it is scrolled instead of paging in and out.
@Observable
final class TransactionsLoader {
    private(set) var items: [Tx] = []
    private(set) var total = 0
    private(set) var loading = false
    private(set) var error: String?

    private var page = 1
    private var filter = TransactionFilter()

    var hasMore: Bool { items.count < total }

    /// Starts over on a new filter. The caller's `.task(id:)` cancels whatever was in flight,
    /// and `loadNext` drops a cancelled page — a filter changed twice quickly shows the second
    /// answer, not whichever request happens to land last.
    func reset(to filter: TransactionFilter) {
        self.filter = filter
        page = 1
        items = []
        total = 0
        error = nil
    }

    func loadNext(_ model: AppModel) async {
        guard !loading, page == 1 || hasMore else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await APIClient.shared.transactions(filter, page: page)
            // A page that arrives after a reset belongs to a filter nobody is looking at.
            guard !Task.isCancelled else { return }
            if result.page == 1 { items = result.items } else { items.append(contentsOf: result.items) }
            total = result.total
            page = result.page + 1
            error = nil
        } catch {
            model.handle(error)
            self.error = error.localizedDescription
        }
    }
}

/// The transactions themselves, grouped into days. Shared by the Activity tab and by every
/// list reached from a slice of the spending ring.
struct TransactionList: View {
    let filter: TransactionFilter
    /// Bumped by the app after any mutation, and by the screen when the filter changes.
    let revision: Int
    var onSelect: (Tx) -> Void

    @Environment(AppModel.self) private var model
    @State private var loader = TransactionsLoader()

    private struct Day: Identifiable {
        var id: String { key }
        let key: String
        let items: [Tx]
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                if let error = loader.error, loader.items.isEmpty {
                    EmptyNote(text: error)
                } else if loader.items.isEmpty && !loader.loading {
                    EmptyNote(text: "Nothing here yet. Adjust the filters, or add a transaction.")
                } else {
                    ForEach(days) { day in
                        MicroLabel(Format.dayLabel(day.items[0].occurredAt))
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        ForEach(day.items) { tx in
                            TransactionRow(tx: tx) { onSelect(tx) }
                        }
                    }

                    if loader.hasMore {
                        Button {
                            Task { await loader.loadNext(model) }
                        } label: {
                            HStack(spacing: 8) {
                                if loader.loading { ProgressView().controlSize(.small) }
                                Text(loader.loading
                                    ? "Loading…"
                                    : "Show more (\(loader.total - loader.items.count) left)")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .disabled(loader.loading)
                    } else if loader.loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .task(id: "\(revision)|\(filterKey)") {
            loader.reset(to: filter)
            await loader.loadNext(model)
        }
    }

    private var filterKey: String {
        filter.queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }

    private var days: [Day] {
        var out: [Day] = []
        for tx in loader.items {
            let key = Format.dayKey(tx.occurredAt)
            if out.last?.key == key {
                out[out.count - 1] = Day(key: key, items: out[out.count - 1].items + [tx])
            } else {
                out.append(Day(key: key, items: [tx]))
            }
        }
        return out
    }
}

/// A filtered list pushed from somewhere else — a wedge of the spending ring, an account.
struct FilteredTransactionsScreen: View {
    let title: String
    let filter: TransactionFilter

    @Environment(AppModel.self) private var model
    @State private var editing: Tx?

    var body: some View {
        ScrollView {
            TransactionList(filter: filter, revision: model.revision) { editing = $0 }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 96)
        }
        .background(Palette.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { TransactionEditor(tx: $0) }
    }
}
