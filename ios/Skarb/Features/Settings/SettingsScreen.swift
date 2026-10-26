import SwiftUI

@Observable
final class SettingsModel {
    private(set) var connections: [Connection] = []

    private let service: any ConnectionService
    private let monitor: SyncMonitor
    private let actions: ActionRunner

    init(service: any ConnectionService, monitor: SyncMonitor, actions: ActionRunner) {
        self.service = service
        self.monitor = monitor
        self.actions = actions
    }

    func load() async {
        if let fresh = try? await service.connections() { connections = fresh }
        await monitor.refresh()
    }

    func sync(_ connection: Connection, full: Bool) async {
        await monitor.sync(connection, full: full)
        await load()
    }

    func remove(_ connection: Connection) async {
        await actions.perform("Connection removed") { try await service.delete(connection.id) }
        await load()
    }

    func restoreIgnored(_ connection: Connection) async {
        await actions.perform("Accounts restored — they return on the next sync") {
            _ = try await service.restoreIgnoredAccounts(connection.id)
        }
        await load()
    }
}

extension AppContainer {
    func makeSettings() -> SettingsModel { SettingsModel(service: connections, monitor: sync, actions: actions) }
}

/// Connections, imports, alerts, security and appearance — the instance-wide plumbing. Settings
/// for one account or one category live in that thing's own editor, as on the web.
struct SettingsScreen: View {
    /// Everything this screen can open on top of itself.
    private enum Sheet: Identifiable {
        case monobank, enableBanking, csvImport, server
        case renew(Connection), rename(Connection), webhook(Connection)

        var id: String {
            switch self {
            case .monobank: "monobank"
            case .enableBanking: "enableBanking"
            case .csvImport: "csvImport"
            case .server: "server"
            case .renew(let c): "renew-\(c.id)"
            case .rename(let c): "rename-\(c.id)"
            case .webhook(let c): "webhook-\(c.id)"
            }
        }
    }

    @State private var model: SettingsModel
    @State private var sheet: Sheet?
    @State private var confirmingDelete: Connection?
    @State private var confirmingRestore: Connection?
    @State private var confirmingSignOut = false

    @Environment(AppContainer.self) private var app
    @Environment(SessionStore.self) private var session
    @Environment(SyncMonitor.self) private var sync
    @Environment(LedgerStore.self) private var ledger
    @AppStorage(Prefs.themeKey) private var theme = ThemeMode.system

    init(model: SettingsModel) { _model = State(initialValue: model) }

    var body: some View {
        SkarbScreen(title: "Settings") {
            connectionsCard
            syncActivityCard

            Card {
                VStack(spacing: 0) {
                    NavigationLink { NotificationsScreen(model: app.makeNotifications()) } label: {
                        SettingsRow(
                            title: "Notifications",
                            subtitle: "Telegram alerts when an account runs low",
                            icon: "bell") { DisclosureChevron() }
                    }
                    .buttonStyle(RowButtonStyle())

                    Divider().padding(.leading, 54)

                    NavigationLink { SecurityScreen(model: app.makeSecurity()) } label: {
                        SettingsRow(
                            title: "Security",
                            subtitle: session.email ?? "Password, two-factor and recovery codes",
                            icon: "lock.shield") { DisclosureChevron() }
                    }
                    .buttonStyle(RowButtonStyle())
                }
                .padding(.vertical, 4)
            }

            appearanceCard

            Card {
                VStack(spacing: 0) {
                    Button { sheet = .server } label: {
                        SettingsRow(
                            title: "Server",
                            subtitle: app.server.baseURL.absoluteString,
                            icon: "server.rack") { DisclosureChevron() }
                    }
                    .buttonStyle(RowButtonStyle())

                    Divider().padding(.leading, 54)

                    Button { confirmingSignOut = true } label: {
                        SettingsRow(
                            title: "Sign out",
                            icon: "rectangle.portrait.and.arrow.right",
                            tint: Palette.danger)
                            .foregroundStyle(Palette.danger)
                    }
                    .buttonStyle(RowButtonStyle())
                }
                .padding(.vertical, 4)
            }

            Text("Skarb \(appVersion) · your data stays on your server")
                .font(.system(size: 12))
                .foregroundStyle(Palette.faint)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .task(id: ledger.revision) { await model.load() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .monobank: MonobankSheet(model: app.makeMonobank())
            case .enableBanking: EnableBankingFlow(model: app.makeEnableBanking())
            case .renew(let connection): EnableBankingFlow(model: app.makeEnableBanking(renewing: connection))
            case .csvImport: CSVImportSheet(model: app.makeCSVImport())
            case .rename(let connection): RenameConnectionSheet(model: app.makeRename(for: connection))
            case .webhook(let connection): WebhookSheet(model: app.makeWebhook(for: connection))
            case .server: ServerSheet()
            }
        }
        .confirmationDialog(
            confirmingDelete.map(ConnectionCopy.deleteWarning) ?? "",
            isPresented: isPresent($confirmingDelete), titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let connection = confirmingDelete { Task { await model.remove(connection) } }
            }
        }
        .confirmationDialog(
            confirmingRestore.map(ConnectionCopy.restoreWarning) ?? "",
            isPresented: isPresent($confirmingRestore), titleVisibility: .visible
        ) {
            Button("Bring back") {
                if let connection = confirmingRestore { Task { await model.restoreIgnored(connection) } }
            }
        }
        .confirmationDialog("Sign out of Skarb?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await app.signOut() } }
        }
    }

    // MARK: - Connections

    private var connectionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bank connections")
                    .font(.display(17))
                    .foregroundStyle(Palette.ink)

                if model.connections.isEmpty {
                    Text("Nothing connected yet. Link Monobank with a personal token, or any of 2,500+ European banks (PKO BP included) through Enable Banking.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(3)
                } else {
                    ForEach(model.connections) { connection in
                        connectionRow(connection)
                    }
                }

                HStack(spacing: 10) {
                    Button { sheet = .monobank } label: { Label("Monobank", systemImage: "powerplug") }
                    Button { sheet = .enableBanking } label: { Label("Other bank", systemImage: "building.columns") }
                }
                .buttonStyle(.skarbPrimary)

                Button { sheet = .csvImport } label: {
                    Label("Import a CSV statement (ZEN, …)", systemImage: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.surface2, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
    }

    private func connectionRow(_ connection: Connection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: Palette.Radius.tile)
                    .fill(Palette.accent)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(connection.displayName.prefix(1).uppercased())
                            .font(.display(16, .bold))
                            .foregroundStyle(Palette.paper)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(connection.displayName)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        statusChip(connection.status)
                    }
                    Text(ConnectionCopy.subtitle(connection))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Menu { connectionActions(connection) } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.muted)
                }
                .accessibilityLabel("Actions for \(connection.displayName)")
            }

            if let lastError = connection.lastError {
                Text(lastError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.danger.opacity(0.1), in: .rect(cornerRadius: Palette.Radius.row))
            }

            if ConnectionCopy.needsRenewal(connection) {
                Button { sheet = .renew(connection) } label: {
                    Label(connection.isLinked ? "Renew bank access" : "Finish linking", systemImage: "arrow.clockwise")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }

            if connection.ignoredAccountCount > 0 {
                HStack(spacing: 8) {
                    Text(ConnectionCopy.ignoredNote(connection))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                    Button("Bring back") { confirmingRestore = connection }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: .rect(cornerRadius: Palette.Radius.row))
            }
        }
        .padding(14)
        .background(Palette.surface2, in: .rect(cornerRadius: Palette.Radius.row))
    }

    @ViewBuilder
    private func connectionActions(_ connection: Connection) -> some View {
        Button {
            Task { await model.sync(connection, full: false) }
        } label: {
            Label("Sync now", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
        }
        Button {
            Task { await model.sync(connection, full: true) }
        } label: {
            Label("Full re-sync", systemImage: "clock.arrow.circlepath")
        }
        if connection.isMonobank {
            Button { sheet = .webhook(connection) } label: {
                Label("Instant sync (webhook)", systemImage: "bolt")
            }
        }
        if connection.isEnableBanking {
            Button { sheet = .renew(connection) } label: {
                Label("Renew bank access", systemImage: "arrow.clockwise")
            }
        }
        Button { sheet = .rename(connection) } label: {
            Label("Rename", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) { confirmingDelete = connection } label: {
            Label("Remove connection", systemImage: "trash")
        }
    }

    private func statusChip(_ status: String) -> some View {
        let color: Color = status == "linked" ? Palette.income
            : status == "error" ? Palette.danger : Palette.muted
        return Text(status)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
    }

    // MARK: - Sync activity

    private var syncActivityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Sync activity")

                if sync.logs.isEmpty {
                    EmptyNote(text: "No syncs yet.")
                } else {
                    ForEach(sync.logs.prefix(10)) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: entry.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(entry.success ? Palette.income : Palette.danger)
                            Text(entry.message)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(Format.relative(entry.at))
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.faint)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                    }
                }
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(.display(17))
                    .foregroundStyle(Palette.ink)
                Picker("Appearance", selection: $theme) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(20)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func isPresent<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}
