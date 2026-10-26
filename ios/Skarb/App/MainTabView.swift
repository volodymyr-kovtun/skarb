import SwiftUI

/// The app's five destinations, in a bottom tab bar.
///
/// On iOS 26 `TabView` draws itself in Liquid Glass — the bar floats over the content,
/// refracts what scrolls beneath it, and shrinks to a pill on the way down a long list.
/// That is the platform's own material, so the app asks for the behaviour and lets the
/// system do the drawing rather than faking glass with a blur.
struct MainTabView: View {
    @Environment(AppContainer.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Overview", systemImage: "chart.pie", value: AppRouter.Destination.overview) {
                OverviewScreen(model: app.makeOverview())
            }
            Tab("Activity", systemImage: "list.bullet", value: AppRouter.Destination.transactions) {
                TransactionsScreen(model: app.makeTransactions())
            }
            Tab("Accounts", systemImage: "building.columns", value: AppRouter.Destination.accounts) {
                AccountsScreen()
            }
            Tab("Categories", systemImage: "square.grid.2x2", value: AppRouter.Destination.categories) {
                CategoriesScreen(model: app.makeCategories())
            }
            Tab("Settings", systemImage: "gearshape", value: AppRouter.Destination.settings) {
                SettingsScreen(model: app.makeSettings())
            }
        }
        // The bar tucks itself away as you read down a long list of transactions and comes
        // back the moment you scroll up.
        .tabBarMinimizeBehavior(.onScrollDown)
        .toastOverlay(toasts)
    }
}

// MARK: - Toast

/// A one-line note that slides in above the tab bar and leaves on its own. It rides on the
/// same glass as the bar so it reads as part of the chrome rather than a banner over content.
private struct ToastOverlay: ViewModifier {
    let toasts: ToastCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = toasts.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? Palette.danger : Palette.income)
                    Text(toast.message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(3)
                    if let undoLabel = toast.undoLabel {
                        Button(undoLabel) { Task { await toasts.runUndo() } }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 20)
                .padding(.bottom, toasts.clearance)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { toasts.dismiss() }
                .sensoryFeedback(toast.isError ? .error : .success, trigger: toast.id)
                .task(id: toast.id) {
                    try? await Task.sleep(for: toast.lifetime)
                    guard !Task.isCancelled, toasts.current?.id == toast.id else { return }
                    toasts.dismiss()
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: toasts.current)
    }
}

extension View {
    func toastOverlay(_ toasts: ToastCenter) -> some View {
        modifier(ToastOverlay(toasts: toasts))
    }
}

// MARK: - Screen chrome

/// The scaffolding most tabs share: the paper background, a large title, and the sync control
/// in the toolbar.
struct SkarbScreen<Content: View, Extra: ToolbarContent>: View {
    private let title: String
    private let showsSync: Bool
    private let content: Content
    private let extraToolbar: Extra

    @Environment(LedgerStore.self) private var ledger

    /// `extraToolbar` takes a value rather than a `@ToolbarContentBuilder` closure on purpose:
    /// the builder only ever yields an opaque type, which a stored generic can't name. One
    /// `ToolbarItem` or `ToolbarItemGroup` is already `ToolbarContent`, so nothing is lost.
    init(
        title: String, showsSync: Bool = true,
        @ViewBuilder content: () -> Content,
        extraToolbar: () -> Extra
    ) {
        self.title = title
        self.showsSync = showsSync
        self.content = content()
        self.extraToolbar = extraToolbar()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                // Clears the floating glass tab bar, which sits over the content by design.
                .padding(.bottom, 96)
            }
            .background(Palette.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if showsSync {
                    ToolbarItem(placement: .topBarTrailing) { SyncButton() }
                }
                extraToolbar
            }
            .refreshable { await ledger.invalidate() }
        }
    }
}

/// The "no extra buttons" case, so a screen that only wants the shared chrome can leave the
/// toolbar closure off entirely.
struct NoToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { EmptyView() }
    }
}

extension SkarbScreen where Extra == NoToolbar {
    init(title: String, showsSync: Bool = true, @ViewBuilder content: () -> Content) {
        self.init(title: title, showsSync: showsSync, content: content, extraToolbar: { NoToolbar() })
    }
}

/// "Sync now", and the spinner that says it is running.
struct SyncButton: View {
    @Environment(SyncMonitor.self) private var sync

    var body: some View {
        Button {
            Task { await sync.syncAll() }
        } label: {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: sync.isSyncing)
        }
        .disabled(sync.isSyncing)
        .accessibilityLabel(sync.isSyncing
            ? "Syncing \(sync.running.joined(separator: ", "))"
            : "Sync every connected bank now")
    }
}
