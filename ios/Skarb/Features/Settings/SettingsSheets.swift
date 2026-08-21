import SwiftUI

/// Monobank's own personal API: one token, read-only, pasted once.
struct MonobankSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            step(1, "Open api.monobank.ua in a browser")
                            step(2, "Scan the QR code with your Monobank app and confirm")
                            step(3, "Copy the personal token and paste it below")
                        }

                        SecureField("Personal API token", text: $token)
                            .skarbField()
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Text("The token grants read access to your statements and is stored only in your Skarb database. The first sync fetches the last 31 days and can take a few minutes — Monobank allows one request per minute.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.faint)
                            .lineSpacing(2)

                        if let error { FormError(error) }

                        Button(busy ? "Connecting…" : "Connect & sync") { Task { await connect() } }
                            .buttonStyle(.skarbPrimary)
                            .disabled(busy || token.trimmed.isEmpty)
                            .opacity(token.trimmed.isEmpty ? 0.5 : 1)
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Connect Monobank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.paper)
                .frame(width: 20, height: 20)
                .background(Palette.accent, in: .circle)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
        }
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        error = nil
        do {
            try await APIClient.shared.connectMonobank(token: token.trimmed)
            await model.invalidate()
            model.show("Monobank connected — the first sync has started")
            dismiss()
        } catch {
            model.handle(error)
            self.error = error.localizedDescription
        }
    }
}

/// Accounts synced through a connection are grouped under its name, so renaming it relabels
/// them too.
struct RenameConnectionSheet: View {
    let connection: Connection

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    TextField("PKO Bank Polski", text: $name)
                        .skarbField()
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }

                    Text("Accounts synced through this connection are grouped under this name — renaming it relabels them too.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.faint)
                        .lineSpacing(2)

                    if let error { FormError(error) }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Rename connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(busy ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(busy || name.trimmed.isEmpty || name.trimmed == connection.displayName)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { if name.isEmpty { name = connection.displayName } }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        error = nil
        do {
            try await APIClient.shared.renameConnection(connection.id, to: name.trimmed)
            await model.invalidate()
            dismiss()
        } catch {
            model.handle(error)
            self.error = error.localizedDescription
        }
    }
}

/// The Telegram bot alerts travel through — the only global piece. Who gets pinged is chosen
/// per account, in the account editor next to the limit itself.
struct NotificationsScreen: View {
    @Environment(AppModel.self) private var model

    @State private var settings: TelegramSettings?
    @State private var token = ""
    @State private var note: (ok: Bool, text: String)?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Skarb can ping a Telegram chat the moment an account drops below its limit — handy when someone else tops the card up. Create a bot with @BotFather (send it /newbot) and paste its token here. The limit, and who gets pinged, is set on each account.")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.muted)
                            .lineSpacing(3)

                        if settings?.hasToken == true {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Bot \(settings?.botUsername.map { "@\($0)" } ?? "") is connected.")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.income)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Bot token")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.muted)
                            SecureField(
                                settings?.hasToken == true
                                    ? "saved — paste a new one to replace"
                                    : "1234567890:ABC-…",
                                text: $token)
                                .skarbField()
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        if let note {
                            Text(note.text)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(note.ok ? Palette.income : Palette.danger)
                        }

                        Button(busy ? "Saving…" : "Save token") { Task { await save() } }
                            .buttonStyle(.skarbPrimary)
                            .disabled(busy || token.trimmed.isEmpty)
                            .opacity(token.trimmed.isEmpty ? 0.5 : 1)

                        if settings?.hasToken == true {
                            Button("Disconnect bot", role: .destructive) { Task { await disconnect() } }
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .disabled(busy)
                        }
                    }
                    .padding(20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96)
        }
        .background(Palette.paper)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { settings = try? await APIClient.shared.telegramSettings() }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        note = nil
        do {
            let saved = try await APIClient.shared.saveTelegramSettings(botToken: token.trimmed)
            settings = saved
            token = ""
            note = (true, "Connected — the bot is @\(saved.botUsername ?? "…").")
        } catch {
            model.handle(error)
            note = (false, error.localizedDescription)
        }
    }

    private func disconnect() async {
        busy = true
        defer { busy = false }
        note = nil
        do {
            settings = try await APIClient.shared.saveTelegramSettings(botToken: "")
            token = ""
            note = (true, "Bot disconnected — no more alerts until a new token is saved.")
        } catch {
            model.handle(error)
            note = (false, error.localizedDescription)
        }
    }
}
