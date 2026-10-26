import SwiftUI

struct AccountEditor: View {
    @State private var model: AccountEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    init(model: AccountEditorModel) { _model = State(initialValue: model) }

    var body: some View {
        NavigationStack {
            Form {
                if !model.isEdit {
                    Section {
                        Picker("Kind", selection: $model.kind) {
                            ForEach(AccountEditorModel.Kind.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                    .listRowBackground(Color.clear)
                }

                if model.addsWallet { walletSection } else { accountSection }

                Section("Color") {
                    ColorSwatchPicker(colors: Palette.accountColors, selection: $model.color)
                }

                if let account = model.original {
                    LowBalanceSection(model: model, account: account)

                    if model.canToggleWallet {
                        Section {
                            Toggle("This is my \(account.currency) cash wallet", isOn: $model.isCash)
                        } footer: {
                            Text("ATM withdrawals in \(account.currency) land here as transfers instead of counting as spending. There is one wallet per currency; archive it to stop tracking \(account.currency) cash.")
                        }
                    }

                    Section {
                        Toggle("Don't count this account", isOn: $model.isExcluded)
                    } footer: {
                        Text("It keeps syncing and keeps showing its balance here, but stops counting toward net worth and everything else on the overview, and its transactions leave the list. Pick it in the account filter to see them again.")
                    }

                    Section {
                        Toggle("Archive", isOn: $model.isArchived)
                    } footer: {
                        Text("For an account you've closed: the same, and it stops syncing and moves out of the list.")
                    }

                    Section {
                        Button("Delete account", role: .destructive) { confirmingDelete = true }
                    }
                }

                if let error = model.error {
                    Section { FormError(error).listRowInsets(EdgeInsets()) }
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.busy ? "Saving…" : "Save") {
                        Task { if await model.save() { dismiss() } }
                    }
                    .fontWeight(.semibold)
                    .disabled(model.busy)
                }
            }
            .confirmationDialog(model.deleteWarning, isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { if await model.delete() { dismiss() } }
                }
            }
        }
        .task { await model.loadTelegram() }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            TextField("Savings jar", text: $model.name)
            if !model.isEdit {
                TextField("Bank or institution (optional)", text: $model.bank)
                Picker("Currency", selection: $model.currency) {
                    ForEach(Currencies.offered, id: \.self) { Text($0).tag($0) }
                }
                balanceField("Current balance")
            }
        }
    }

    @ViewBuilder
    private var walletSection: some View {
        Section {
            if model.freeCurrencies.isEmpty {
                Text("Every currency Skarb lists already has a wallet.")
                    .foregroundStyle(Palette.muted)
            } else {
                Picker("Currency", selection: $model.walletCurrency) {
                    ForEach(model.freeCurrencies, id: \.self) { Text($0).tag($0) }
                }
                balanceField("Cash on hand")
            }
        } footer: {
            Text("The cash you hold in one currency. ATM withdrawals in it land here as transfers instead of counting as spending — there is one wallet per currency, so a withdrawal always knows where to go.")
        }
    }

    private func balanceField(_ label: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0.00", text: $model.balanceText)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}

/// The per-account Telegram alert: a limit, and who gets pinged when the balance drops below it.
/// Config lives where it is used — the bot itself is the only global piece, in Settings.
private struct LowBalanceSection: View {
    @Bindable var model: AccountEditorModel
    let account: Account

    var body: some View {
        Section {
            HStack {
                Text("Alert below")
                Spacer()
                TextField("off", text: $model.threshold)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(account.currency).foregroundStyle(Palette.faint)
            }

            if model.alertsOn {
                HStack {
                    TextField("Telegram chat ID", text: $model.alertChat)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Find chats") { Task { await model.findChats() } }
                        .font(.system(size: 13, weight: .semibold))
                        .disabled(model.telegramBusy || model.telegram?.hasToken != true)
                }

                ForEach(model.chats) { chat in
                    Button { model.pick(chat) } label: {
                        HStack {
                            Text(chat.name).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(chat.id).foregroundStyle(Palette.faint).monospacedDigit()
                        }
                        .font(.system(size: 14))
                    }
                }

                if let note = model.telegramNote { StatusNote(note) }

                if !model.alertChat.trimmed.isEmpty, model.telegram?.hasToken == true {
                    Button("Send a test message to this chat") { Task { await model.sendTest() } }
                        .font(.system(size: 13, weight: .semibold))
                        .disabled(model.telegramBusy)
                }

                if model.botMissing {
                    StatusNote(ok: false, text: "No Telegram bot is connected yet — paste its token in Settings → Notifications first, or this alert has nowhere to go.")
                }
            }
        } header: {
            Text("Low balance alert")
        } footer: {
            Text("A Telegram message goes out the moment the balance drops below this, with a daily reminder while it stays low. Who to ping is usually the person who tops the account up: they message the bot once, then Find chats lists them.")
        }
    }
}
