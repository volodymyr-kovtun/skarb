import SwiftUI

/// The app's five destinations, in a bottom tab bar.
///
/// On iOS 26 `TabView` draws itself in Liquid Glass — the bar floats over the content,
/// refracts what scrolls beneath it, and shrinks to a pill on the way down a long list.
/// That is the platform's own material, so the app asks for the behaviour and lets the
/// system do the drawing rather than faking glass with a blur.
struct MainTabView: View {
    @Environment(AppModel.self) private var model
    /// Reopen on the tab you left — a ledger you check twice a day shouldn't reset to the
    /// overview every time.
    @AppStorage("skarb.tab") private var selection: Destination = .overview

    enum Destination: String, Hashable {
        case overview, transactions, accounts, categories, settings
    }

    var body: some View {
        @Bindable var model = model
        TabView(selection: $selection) {
            Tab("Overview", systemImage: "chart.pie", value: .overview) {
                OverviewScreen()
            }
            Tab("Activity", systemImage: "list.bullet", value: .transactions) {
                TransactionsScreen()
            }
            Tab("Accounts", systemImage: "building.columns", value: .accounts) {
                AccountsScreen()
            }
            Tab("Categories", systemImage: "square.grid.2x2", value: .categories) {
                CategoriesScreen()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsScreen()
            }
        }
        // The bar tucks itself away as you read down a long list of transactions and comes
        // back the moment you scroll up.
        .tabBarMinimizeBehavior(.onScrollDown)
        .toastOverlay(model.toast) { model.dismissToast() }
        .onOpenURL { url in
            // Deep links from a slice of the spending ring: skarb://transactions?account=…
            guard url.scheme == "skarb", url.host() == "transactions" else { return }
            selection = .transactions
        }
    }
}

// MARK: - Toast

/// A one-line note that slides in above the tab bar and leaves on its own. It rides on the
/// same glass as the bar so it reads as part of the chrome rather than a banner over content.
private struct ToastOverlay: ViewModifier {
    let toast: AppModel.Toast?
    let dismiss: () -> Void
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                HStack(spacing: 10) {
                    Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? Palette.danger : Palette.income)
                    Text(toast.message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(3)
                    if let undoLabel = toast.undoLabel {
                        Button(undoLabel) { Task { await model.runUndo() } }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 20)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture(perform: dismiss)
                .task(id: toast.id) {
                    // Long enough to read a count and reach for Undo, short enough not to linger.
                    let seconds: Double = toast.undoLabel != nil ? 9 : (toast.isError ? 5 : 2.5)
                    try? await Task.sleep(for: .seconds(seconds))
                    dismiss()
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: toast)
    }
}

extension View {
    func toastOverlay(_ toast: AppModel.Toast?, dismiss: @escaping () -> Void) -> some View {
        modifier(ToastOverlay(toast: toast, dismiss: dismiss))
    }
}

// MARK: - Screen chrome

/// The scaffolding every tab shares: the paper background, a large title, and the sync and
/// theme controls in the toolbar.
struct SkarbScreen<Content: View, Extra: ToolbarContent>: View {
    private let title: String
    private let showsSync: Bool
    private let content: Content
    private let extraToolbar: Extra

    @Environment(AppModel.self) private var model

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
            .refreshable { await model.invalidate() }
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
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            Task { await model.syncNow() }
        } label: {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: model.isSyncing)
        }
        .disabled(model.isSyncing)
        .accessibilityLabel(model.isSyncing
            ? "Syncing \(model.syncRunning.joined(separator: ", "))"
            : "Sync every connected bank now")
    }
}
