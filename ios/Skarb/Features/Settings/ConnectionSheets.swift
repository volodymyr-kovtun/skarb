import SwiftUI

// MARK: - Monobank

@Observable
final class MonobankModel {
    var token = ""
    private(set) var busy = false
    private(set) var error: String?

    private let service: any ConnectionService
    private let ledger: LedgerStore
    private let toasts: ToastCenter

    init(service: any ConnectionService, ledger: LedgerStore, toasts: ToastCenter) {
        self.service = service
        self.ledger = ledger
        self.toasts = toasts
    }

    var canConnect: Bool { !busy && !token.trimmed.isEmpty }

    func connect() async -> Bool {
        guard canConnect else { return false }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await service.connectMonobank(token: token.trimmed)
            await ledger.invalidate()
            toasts.show("Monobank connected — the first sync has started")
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

/// Monobank's own personal API: one token, read-only, pasted once.
struct MonobankSheet: View {
    @State private var model: MonobankModel
    @Environment(\.dismiss) private var dismiss

    init(model: MonobankModel) { _model = State(initialValue: model) }

    var body: some View {
        SheetScaffold(title: "Connect Monobank") {
            VStack(alignment: .leading, spacing: 8) {
                NumberedStep(1) {
                    Text("Open [api.monobank.ua](https://api.monobank.ua/) in a browser")
                }
                NumberedStep(2) { Text("Scan the QR code with your Monobank app and confirm") }
                NumberedStep(3) { Text("Copy the personal token and paste it below") }
            }

            SecureField("Personal API token", text: $model.token)
                .skarbField()
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Footnote("The token grants read access to your statements and is stored only in your Skarb database. The first sync fetches the last 31 days and can take a few minutes — Monobank allows one request per minute.")

            if let error = model.error { FormError(error) }

            Button(model.busy ? "Connecting…" : "Connect & sync") {
                Task { if await model.connect() { dismiss() } }
            }
            .buttonStyle(.skarbPrimary)
            .disabled(!model.canConnect)
            .opacity(model.canConnect ? 1 : 0.5)
        }
    }
}

// MARK: - Webhook

@Observable
final class WebhookModel {
    let connection: Connection
    var baseURL: String
    private(set) var registered: String?
    private(set) var busy = false
    private(set) var error: String?

    private let service: any ConnectionService

    init(connection: Connection, suggestedBaseURL: URL, service: any ConnectionService) {
        self.connection = connection
        self.service = service
        // The app already talks to this server over the internet, so its address is almost always
        // the public one Monobank needs — offered, never assumed.
        baseURL = suggestedBaseURL.scheme == "https" ? suggestedBaseURL.absoluteString : ""
    }

    var canEnable: Bool { !busy && baseURL.trimmed.hasPrefix("https://") }

    func enable() async {
        guard canEnable else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            registered = try await service.registerMonobankWebhook(connection.id, publicBaseURL: baseURL.trimmed)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Monobank can push every payment to Skarb the moment it happens, instead of waiting for the
/// next sync round.
struct WebhookSheet: View {
    @State private var model: WebhookModel

    init(model: WebhookModel) { _model = State(initialValue: model) }

    var body: some View {
        SheetScaffold(title: "Instant sync") {
            Text("Monobank can push every payment to Skarb the moment it happens. That needs a public HTTPS address for your server — for personal use a Cloudflare Tunnel or Tailscale Funnel works well (see docs/BANKS.md).")
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
                .lineSpacing(3)

            TextField("https://skarb.example.com", text: $model.baseURL)
                .skarbField()
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if let registered = model.registered {
                Text("Webhook registered: \(registered)")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.income)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.income.opacity(0.1), in: .rect(cornerRadius: Palette.Radius.row))
            }
            if let error = model.error { FormError(error) }

            Button(model.busy ? "Registering…" : "Enable") { Task { await model.enable() } }
                .buttonStyle(.skarbPrimary)
                .disabled(!model.canEnable)
                .opacity(model.canEnable ? 1 : 0.5)
        }
    }
}

// MARK: - Rename

@Observable
final class RenameConnectionModel {
    let connection: Connection
    var name: String
    private(set) var busy = false
    private(set) var error: String?

    private let service: any ConnectionService
    private let ledger: LedgerStore

    init(connection: Connection, service: any ConnectionService, ledger: LedgerStore) {
        self.connection = connection
        name = connection.displayName
        self.service = service
        self.ledger = ledger
    }

    var canSave: Bool { !busy && !name.trimmed.isEmpty && name.trimmed != connection.displayName }

    func save() async -> Bool {
        guard canSave else { return false }
        busy = true
        error = nil
        defer { busy = false }
        do {
            _ = try await service.rename(connection.id, to: name.trimmed)
            await ledger.invalidate()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

/// Accounts synced through a connection are grouped under its name, so renaming it relabels
/// them too.
struct RenameConnectionSheet: View {
    @State private var model: RenameConnectionModel
    @Environment(\.dismiss) private var dismiss

    init(model: RenameConnectionModel) { _model = State(initialValue: model) }

    var body: some View {
        SheetScaffold(title: "Rename connection", detents: [.medium]) {
            TextField("PKO Bank Polski", text: $model.name)
                .skarbField()
                .submitLabel(.done)
                .onSubmit { Task { if await model.save() { dismiss() } } }

            Footnote("Accounts synced through this connection are grouped under this name — renaming it relabels them too.")

            if let error = model.error { FormError(error) }

            Button(model.busy ? "Saving…" : "Save") { Task { if await model.save() { dismiss() } } }
                .buttonStyle(.skarbPrimary)
                .disabled(!model.canSave)
                .opacity(model.canSave ? 1 : 0.5)
        }
    }
}

// MARK: - Notifications

@Observable
final class NotificationsModel {
    private(set) var settings: TelegramSettings?
    var token = ""
    private(set) var note: StatusMessage?
    private(set) var busy = false

    private let service: any NotificationService

    init(service: any NotificationService) {
        self.service = service
    }

    var connected: Bool { settings?.hasToken == true }

    func load() async {
        settings = try? await service.telegramSettings()
    }

    func save() async {
        await run {
            let saved = try await service.saveTelegram(botToken: token.trimmed)
            settings = saved
            token = ""
            note = StatusMessage(ok: true, text: "Connected — the bot is @\(saved.botUsername ?? "…").")
        }
    }

    func disconnect() async {
        await run {
            settings = try await service.saveTelegram(botToken: "")
            token = ""
            note = StatusMessage(ok: true, text: "Bot disconnected — no more alerts until a new token is saved.")
        }
    }

    private func run(_ body: () async throws -> Void) async {
        busy = true
        note = nil
        defer { busy = false }
        do { try await body() } catch { note = StatusMessage(ok: false, text: error.localizedDescription) }
    }
}

/// The Telegram bot alerts travel through — the only global piece. Who gets pinged is chosen
/// per account, in the account editor next to the limit itself.
struct NotificationsScreen: View {
    @State private var model: NotificationsModel

    init(model: NotificationsModel) { _model = State(initialValue: model) }

    var body: some View {
        ScrollView {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Skarb can ping a Telegram chat the moment an account drops below its limit — handy when someone else tops the card up. Create a bot with [@BotFather](https://t.me/BotFather) (send it /newbot) and paste its token here. The limit, and who gets pinged, is set on each account.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(3)

                    if model.connected {
                        Label("Bot \(model.settings?.botUsername.map { "@\($0)" } ?? "") is connected.", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.income)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bot token")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.muted)
                        SecureField(
                            model.connected ? "saved — paste a new one to replace" : "1234567890:ABC-…",
                            text: $model.token)
                            .skarbField()
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    if let note = model.note { StatusNote(note) }

                    Button(model.busy ? "Saving…" : "Save token") { Task { await model.save() } }
                        .buttonStyle(.skarbPrimary)
                        .disabled(model.busy || model.token.trimmed.isEmpty)
                        .opacity(model.token.trimmed.isEmpty ? 0.5 : 1)

                    if model.connected {
                        Button("Disconnect bot", role: .destructive) { Task { await model.disconnect() } }
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .disabled(model.busy)
                    }
                }
                .padding(20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96)
        }
        .background(Palette.paper)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }
}

extension AppContainer {
    func makeMonobank() -> MonobankModel { MonobankModel(service: connections, ledger: ledger, toasts: toasts) }

    func makeWebhook(for connection: Connection) -> WebhookModel {
        WebhookModel(connection: connection, suggestedBaseURL: server.baseURL, service: connections)
    }

    func makeRename(for connection: Connection) -> RenameConnectionModel {
        RenameConnectionModel(connection: connection, service: connections, ledger: ledger)
    }

    func makeNotifications() -> NotificationsModel { NotificationsModel(service: notifications) }
}

// MARK: - Shared sheet chrome

/// A sheet with a title, a Cancel button and a scrolling column — what every settings sheet is.
struct SheetScaffold<Content: View>: View {
    let title: String
    var detents: Set<PresentationDetent> = [.large]
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { content }
                        .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents(detents)
    }
}

struct NumberedStep<Content: View>: View {
    let number: Int
    @ViewBuilder var content: Content

    init(_ number: Int, @ViewBuilder content: () -> Content) {
        self.number = number
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.paper)
                .frame(width: 20, height: 20)
                .background(Palette.accent, in: .circle)
            content
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
                .tint(Palette.ink)
        }
    }
}

struct Footnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Palette.faint)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
