import SwiftUI

/// Add a manual account, or change one that already exists. A synced account's name, color and
/// alert are yours; its balance and currency belong to the bank.
struct AccountEditor: View {
    let account: Account?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var bank = ""
    @State private var currency = "PLN"
    @State private var balance = "0"
    @State private var color = Palette.accountColors[0]
    @State private var isArchived = false
    @State private var isExcluded = false
    @State private var threshold = ""
    @State private var alertChat = ""
    @State private var chats: [TelegramChat] = []
    @State private var telegram: TelegramSettings?
    @State private var note: (ok: Bool, text: String)?
    @State private var telegramBusy = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingDelete = false
    @State private var loaded = false

    private var isEdit: Bool { account != nil }
    private static let currencies = ["PLN", "UAH", "EUR", "USD", "GBP", "CZK", "CHF"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Cash wallet", text: $name)
                    if !isEdit {
                        TextField("Bank or institution (optional)", text: $bank)
                        Picker("Currency", selection: $currency) {
                            ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                        }
                        HStack {
                            Text("Current balance")
                            Spacer()
                            TextField("0.00", text: $balance)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                    }
                }

                Section("Color") {
                    ColorSwatchPicker(colors: Palette.accountColors, selection: $color)
                }

                if isEdit, let account {
                    lowBalanceSection(account)

                    Section {
                        Toggle("Don't count this account", isOn: $isExcluded)
                    } footer: {
                        Text("It keeps syncing and keeps showing its balance here, but stops counting toward net worth and everything else on the overview, and its transactions leave the list. Pick it in the account filter to see them again.")
                    }

                    Section {
                        Toggle("Archive", isOn: $isArchived)
                    } footer: {
                        Text("For an account you've closed: the same, and it stops syncing and moves out of the list.")
                    }

                    Section {
                        Button("Delete account", role: .destructive) { confirmingDelete = true }
                    }
                }

                if let error {
                    Section { FormError(error).listRowInsets(EdgeInsets()) }
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(isEdit ? "Edit account" : "Add manual account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(busy ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(busy)
                }
            }
            .confirmationDialog(deleteWarning, isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await remove() } }
            }
        }
        .task { await load() }
    }

    // MARK: - Low balance alert

    @ViewBuilder
    private func lowBalanceSection(_ account: Account) -> some View {
        Section {
            HStack {
                Text("Alert below")
                Spacer()
                TextField("off", text: $threshold)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(account.currency).foregroundStyle(Palette.faint)
            }

            if !threshold.trimmed.isEmpty {
                HStack {
                    TextField("Telegram chat ID", text: $alertChat)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Find chats") { Task { await findChats() } }
                        .font(.system(size: 13, weight: .semibold))
                        .disabled(telegramBusy || telegram?.hasToken != true)
                }

                ForEach(chats) { chat in
                    Button {
                        alertChat = chat.id
                        chats = []
                        note = nil
                    } label: {
                        HStack {
                            Text(chat.name).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(chat.id).foregroundStyle(Palette.faint).monospacedDigit()
                        }
                        .font(.system(size: 14))
                    }
                }

                if let note {
                    Text(note.text)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(note.ok ? Palette.income : Palette.danger)
                }

                if !alertChat.trimmed.isEmpty, telegram?.hasToken == true {
                    Button("Send a test message to this chat") { Task { await sendTest() } }
                        .font(.system(size: 13, weight: .semibold))
                        .disabled(telegramBusy)
                }

                if let telegram, !telegram.hasToken {
                    Text("No Telegram bot is connected yet — paste its token in Settings → Notifications first, or this alert has nowhere to go.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.danger)
                }
            }
        } header: {
            Text("Low balance alert")
        } footer: {
            Text("A Telegram message goes out the moment the balance drops below this, with a daily reminder while it stays low. Leave it empty for no alert.")
        }
    }

    private func findChats() async {
        telegramBusy = true
        defer { telegramBusy = false }
        note = nil
        do {
            chats = try await APIClient.shared.telegramChats()
            if chats.isEmpty {
                note = (false, "No chats found. The recipient has to open the bot in Telegram and send it anything first — messages only show up here for about a day.")
            }
        } catch {
            model.handle(error)
            note = (false, error.localizedDescription)
        }
    }

    private func sendTest() async {
        telegramBusy = true
        defer { telegramBusy = false }
        note = nil
        do {
            let sentTo = try await APIClient.shared.telegramTest(chatId: alertChat.trimmed)
            note = (true, "Test sent to chat \(sentTo) — check Telegram.")
        } catch {
            model.handle(error)
            note = (false, error.localizedDescription)
        }
    }

    // MARK: - Load and save

    private func load() async {
        guard !loaded else { return }
        loaded = true
        guard let account else { return }
        name = account.name
        color = account.color
        isArchived = account.isArchived
        isExcluded = account.isExcluded
        threshold = account.lowBalanceThreshold.map { "\($0)" } ?? ""
        alertChat = account.lowBalanceChatId ?? ""
        // Only to warn when an alert is configured but has nowhere to go.
        telegram = try? await APIClient.shared.telegramSettings()
    }

    private var deleteWarning: String {
        guard let account else { return "" }
        // A synced account is rediscovered every sync, so deleting one also tells its connection
        // to skip it from now on — say so, and say where that can be undone.
        return account.connectionId != nil
            ? "Delete “\(account.name)” and all its transactions? It stops syncing and won't come back on its own — Settings can bring it back later."
            : "Delete “\(account.name)” and all its transactions? This cannot be undone."
    }

    private func save() async {
        busy = true
        defer { busy = false }
        error = nil
        do {
            if let account {
                let limit = Decimal(string: threshold.trimmed.replacingOccurrences(of: ",", with: "."))
                if limit != nil, alertChat.trimmed.isEmpty {
                    error = "Pick who to ping — Find chats lists everyone who has messaged the bot."
                    return
                }
                try await APIClient.shared.updateAccount(account.id, AccountPatch(
                    name: name.trimmed,
                    color: color,
                    isArchived: isArchived,
                    isExcluded: isExcluded,
                    lowBalanceSet: true,
                    lowBalanceThreshold: limit,
                    lowBalanceChatId: alertChat.trimmed.isEmpty ? nil : alertChat.trimmed))
            } else {
                guard !name.trimmed.isEmpty else {
                    error = "Give the account a name."
                    return
                }
                try await APIClient.shared.createAccount(NewAccount(
                    name: name.trimmed,
                    bank: bank.trimmed,
                    currency: currency,
                    balance: Decimal(string: balance.replacingOccurrences(of: ",", with: ".")) ?? 0,
                    color: color))
            }
            await model.invalidate()
            dismiss()
        } catch {
            model.handle(error)
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        guard let account else { return }
        await model.perform("Account deleted") {
            try await APIClient.shared.deleteAccount(account.id)
        }
        dismiss()
    }
}

/// The eight hues the design is built from, so a picked color always belongs.
struct ColorSwatchPicker: View {
    let colors: [String]
    @Binding var selection: String

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(colors, id: \.self) { hex in
                Button { selection = hex } label: {
                    Circle()
                        .fill(Color(hexString: hex))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle()
                                .strokeBorder(Palette.ink, lineWidth: selection == hex ? 2 : 0)
                                .padding(-4)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(hex)")
                .accessibilityAddTraits(selection == hex ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 6)
    }
}
