import SwiftUI

/// Connections, alerts, security and appearance.
///
/// Two of the web's flows deliberately aren't here: linking a bank through Enable Banking
/// (an OAuth round trip that wants a private key pasted in) and the CSV importer. Both are
/// one-time desktop errands, and the screen says where to do them rather than pretending.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.themeKey) private var theme = ThemeMode.system

    @State private var connections: [Connection] = []
    @State private var logs: [SyncStatus.LogEntry] = []
    @State private var connectingMonobank = false
    @State private var renaming: Connection?
    @State private var confirmingDelete: Connection?
    @State private var confirmingRestore: Connection?
    @State private var showingServer = false
    @State private var confirmingSignOut = false

    var body: some View {
        SkarbScreen(title: "Settings") {
            connectionsCard
            syncActivityCard

            Card {
                VStack(spacing: 0) {
                    NavigationLink { NotificationsScreen() } label: {
                        SettingsRow(
                            title: "Notifications",
                            subtitle: "Telegram alerts when an account runs low",
                            icon: "bell") { DisclosureChevron() }
                    }
                    .buttonStyle(RowButtonStyle())

                    Divider().padding(.leading, 54)

                    NavigationLink { SecurityScreen() } label: {
                        SettingsRow(
                            title: "Security",
                            subtitle: signedInAs,
                            icon: "lock.shield") { DisclosureChevron() }
                    }
                    .buttonStyle(RowButtonStyle())
                }
                .padding(.vertical, 4)
            }

            appearanceCard

            Card {
                VStack(spacing: 0) {
                    Button { showingServer = true } label: {
                        SettingsRow(
                            title: "Server",
                            subtitle: APIClient.shared.baseURL.absoluteString,
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
        .task(id: model.revision) { await load() }
        .sheet(isPresented: $connectingMonobank) { MonobankSheet() }
        .sheet(item: $renaming) { RenameConnectionSheet(connection: $0) }
        .sheet(isPresented: $showingServer) { ServerSheet() }
        .confirmationDialog(
            deleteWarning, isPresented: .init(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let connection = confirmingDelete {
                    Task {
                        await model.perform("Connection removed") {
                            try await APIClient.shared.deleteConnection(connection.id)
                        }
                        await load()
                    }
                }
            }
        }
        .confirmationDialog(
            restoreWarning, isPresented: .init(
                get: { confirmingRestore != nil },
                set: { if !$0 { confirmingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Bring back") {
                if let connection = confirmingRestore {
                    Task {
                        await model.perform("Accounts restored — they return on the next sync") {
                            try await APIClient.shared.restoreIgnoredAccounts(connection.id)
                        }
                        await load()
                    }
                }
            }
        }
        .confirmationDialog("Sign out of Skarb?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOut() } }
        }
    }

    // MARK: - Connections

    private var connectionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bank connections")
                    .font(.display(17))
                    .foregroundStyle(Palette.ink)

                if connections.isEmpty {
                    Text("Nothing connected yet. Link Monobank with a personal token below — for PKO BP and 2,500+ other European banks, use Enable Banking from the web app.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(3)
                } else {
                    ForEach(connections) { connection in
                        connectionRow(connection)
                    }
                }

                Button("Connect Monobank") { connectingMonobank = true }
                    .buttonStyle(.skarbPrimary)

                Text("Linking a bank through Enable Banking, and importing a CSV statement, both live in the web app at \(APIClient.shared.baseURL.host() ?? "your server") — they need a browser round trip and a file picker.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.faint)
                    .lineSpacing(2)
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
                    Text(connectionSubtitle(connection))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Menu {
                    Button {
                        Task { await syncOne(connection, full: false) }
                    } label: {
                        Label("Sync now", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    }
                    Button {
                        Task { await syncOne(connection, full: true) }
                    } label: {
                        Label("Full re-sync", systemImage: "clock.arrow.circlepath")
                    }
                    Button { renaming = connection } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) { confirmingDelete = connection } label: {
                        Label("Remove connection", systemImage: "trash")
                    }
                } label: {
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

            if connection.ignoredAccountCount > 0 {
                HStack(spacing: 8) {
                    Text(connection.ignoredAccountCount == 1
                        ? "1 deleted account is kept out of sync."
                        : "\(connection.ignoredAccountCount) deleted accounts are kept out of sync.")
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

    private func connectionSubtitle(_ connection: Connection) -> String {
        var parts = ["\(connection.accountCount) account\(connection.accountCount == 1 ? "" : "s")"]
        if let synced = connection.lastSyncedAt { parts.append("synced \(Format.relative(synced))") }
        if let until = connection.consentValidUntil {
            parts.append("consent until \(until.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    private var deleteWarning: String {
        guard let connection = confirmingDelete else { return "" }
        guard connection.accountCount > 0 else { return "Remove \(connection.displayName)?" }
        let accounts = connection.accountCount == 1
            ? "Its 1 account" : "Its \(connection.accountCount) accounts"
        return "Remove \(connection.displayName)? \(accounts) and every transaction on them will be deleted. This cannot be undone."
    }

    private var restoreWarning: String {
        guard let connection = confirmingRestore else { return "" }
        let what = connection.ignoredAccountCount == 1 ? "it" : "them"
        return "Bring \(what) back? The next sync recreates \(what) and re-fetches history from scratch."
    }

    private func syncOne(_ connection: Connection, full: Bool) async {
        do {
            try await APIClient.shared.syncOne(connection.id, full: full)
            model.show(full ? "Full re-sync started" : "Syncing \(connection.displayName)…")
            await model.refreshSyncStatus()
            await load()
        } catch {
            model.handle(error)
            model.show(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Sync activity

    private var syncActivityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Sync activity")

                if logs.isEmpty {
                    EmptyNote(text: "No syncs yet.")
                } else {
                    ForEach(logs.prefix(10)) { entry in
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

    private var signedInAs: String {
        if case .signedIn(let email) = model.phase, let email { return email }
        return "Password, two-factor and recovery codes"
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func load() async {
        do {
            async let connections = APIClient.shared.connections()
            async let status = APIClient.shared.syncStatus()
            self.connections = try await connections
            self.logs = try await status.logs
        } catch {
            model.handle(error)
        }
    }
}
