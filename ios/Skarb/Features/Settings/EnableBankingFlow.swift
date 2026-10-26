import AuthenticationServices
import SwiftUI
import UniformTypeIdentifiers

/// Linking a bank through Enable Banking, in the web's two steps — the owner's application
/// credentials, then the bank — plus a way back into the second step for a connection whose
/// consent ran out or whose first attempt never finished.
@Observable
final class EnableBankingModel {
    enum Step: Equatable { case credentials, bank }

    /// Opens the bank's page and comes back with the URL it returned to. Supplied by the view,
    /// which owns the browser sheet; a cancelled sheet throws `CancellationError`.
    typealias Authenticate = (URL) async throws -> URL

    private(set) var step: Step
    var displayName = "PKO Bank Polski"
    var applicationId = ""
    var privateKey = ""
    var country = "PL"
    var bankFilter = ""
    private(set) var banks: [Aspsp] = []
    private(set) var loadingBanks = false
    private(set) var busy = false
    private(set) var error: String?

    /// Set when picking up an existing connection rather than creating one.
    let renewing: Connection?
    private(set) var connectionId: UUID?

    private let service: any EnableBankingService
    private let redirectURL: URL
    private let finish: (EnableBankingHandoff.Outcome) async -> Bool

    /// The bank list is long — Enable Banking reaches 2,500+ — so a filter narrows it and only
    /// the first stretch of what matches is drawn.
    static let shownLimit = 200

    init(
        renewing: Connection?, service: any EnableBankingService, redirectURL: URL,
        finish: @escaping (EnableBankingHandoff.Outcome) async -> Bool
    ) {
        self.renewing = renewing
        self.service = service
        self.redirectURL = redirectURL
        self.finish = finish
        connectionId = renewing?.id
        step = renewing == nil ? .credentials : .bank
        if let renewing { displayName = renewing.displayName }
    }

    var canContinue: Bool {
        !busy && !applicationId.trimmed.isEmpty && privateKey.contains("PRIVATE KEY")
    }

    var matchingBanks: [Aspsp] {
        let query = bankFilter.trimmed.lowercased()
        return query.isEmpty ? banks : banks.filter { $0.name.lowercased().contains(query) }
    }

    var shownBanks: [Aspsp] { Array(matchingBanks.prefix(Self.shownLimit)) }

    var redirectNote: String {
        "You'll be sent to the bank to approve read-only access (valid about 90 days), then brought back here. "
            + "\(redirectURL.absoluteString) has to be one of the redirect URLs your Enable Banking app allows — "
            + "it is the same one the web app uses."
    }

    /// A key file picked from Files, read as the text it is.
    func importKey(_ data: Data) {
        privateKey = String(decoding: data, as: UTF8.self).trimmed
    }

    func createConnection() async {
        guard canContinue else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            connectionId = try await service.createConnection(
                displayName: displayName.trimmed.isEmpty ? "Bank" : displayName.trimmed,
                applicationId: applicationId.trimmed,
                privateKeyPEM: privateKey.trimmed)
            step = .bank
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadBanks() async {
        guard let connectionId else { return }
        let asked = country
        loadingBanks = true
        defer { loadingBanks = false }
        do {
            let list = try await service.banks(for: connectionId, country: asked)
            if asked == country { banks = list }
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }

    /// Authorizes at the bank and finishes the link. True when the connection is linked.
    func link(_ bank: Aspsp, authenticate: Authenticate) async -> Bool {
        guard let connectionId, !busy else { return false }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let page = try await service.authorize(connectionId, bank: bank, redirectURL: redirectURL)
            let callback = try await authenticate(page)
            switch EnableBankingHandoff.outcome(from: callback) {
            case .authorized(let connection, let code):
                return await finish(.authorized(connection: connection, code: code))
            case .refused(let reason):
                error = reason
            case nil:
                error = "The bank sent back an answer Skarb couldn't read. Try linking again."
            }
        } catch {
            // Closing the bank's sheet is changing one's mind, not a failure.
            if !error.isCancellation { self.error = error.localizedDescription }
        }
        return false
    }
}

extension AppContainer {
    func makeEnableBanking(renewing connection: Connection? = nil) -> EnableBankingModel {
        EnableBankingModel(
            renewing: connection, service: enableBanking, redirectURL: server.bankRedirectURL,
            finish: { [weak self] outcome in await self?.finishBankLink(outcome) ?? false })
    }
}

struct EnableBankingFlow: View {
    @State private var model: EnableBankingModel
    @State private var importingKey = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    init(model: EnableBankingModel) { _model = State(initialValue: model) }

    var body: some View {
        SheetScaffold(title: model.renewing == nil ? "Connect a bank" : "Renew \(model.displayName)") {
            switch model.step {
            case .credentials: credentials
            case .bank: bankPicker
            }
        }
        .fileImporter(isPresented: $importingKey, allowedContentTypes: [.data, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { model.importKey(data) }
        }
        .task(id: "\(model.step == .bank)|\(model.country)") {
            if model.step == .bank { await model.loadBanks() }
        }
    }

    // MARK: - Step one

    @ViewBuilder
    private var credentials: some View {
        Text("Enable Banking is a licensed open-banking provider covering 2,500+ European banks, free for accessing your own accounts. Create an application at [enablebanking.com](https://enablebanking.com/cp/applications) — environment *Production*, with your own bank account linked in their portal — then paste its credentials here. The full walkthrough is in docs/BANKS.md.")
            .font(.system(size: 14))
            .foregroundStyle(Palette.muted)
            .tint(Palette.ink)
            .lineSpacing(3)

        LabeledField("Connection name") {
            TextField("PKO Bank Polski", text: $model.displayName)
        }
        LabeledField("Application ID") {
            TextField("xxxxxxxx-xxxx-…", text: $model.applicationId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14, design: .monospaced))
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RSA private key (PEM)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Button("Import from Files") { importingKey = true }
                    .font(.system(size: 12.5, weight: .semibold))
            }
            TextEditor(text: $model.privateKey)
                .font(.system(size: 11, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .frame(minHeight: 130)
                .padding(8)
                .background(Palette.surface2, in: .rect(cornerRadius: Palette.Radius.row))
                .overlay(alignment: .topLeading) {
                    if model.privateKey.isEmpty {
                        Text("-----BEGIN PRIVATE KEY-----\n…\n-----END PRIVATE KEY-----")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Palette.faint)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
        }

        if let error = model.error { FormError(error) }

        Button(model.busy ? "Checking…" : "Continue") { Task { await model.createConnection() } }
            .buttonStyle(.skarbPrimary)
            .disabled(!model.canContinue)
            .opacity(model.canContinue ? 1 : 0.5)
    }

    // MARK: - Step two

    @ViewBuilder
    private var bankPicker: some View {
        if let renewing = model.renewing {
            Footnote("Pick \(renewing.displayName)'s bank again and approve access. Its accounts and history stay as they are; syncing picks up where it left off.")
        }

        HStack(spacing: 10) {
            Menu {
                Picker("Country", selection: $model.country) {
                    ForEach(ConnectionCopy.countries, id: \.self) { Text(ConnectionCopy.countryLabel($0)).tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(ConnectionCopy.countryLabel(model.country))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Palette.surface2, in: .capsule)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                TextField("Filter banks…", text: $model.bankFilter)
                    .autocorrectionDisabled()
            }
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Palette.surface2, in: .capsule)
        }

        Card {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.shownBanks.isEmpty {
                    EmptyNote(text: model.loadingBanks ? "Loading…" : "No banks found.")
                }
                ForEach(model.shownBanks) { bank in
                    Button { Task { await link(bank) } } label: { bankRow(bank) }
                        .buttonStyle(RowButtonStyle())
                        .disabled(model.busy)
                }
                if model.matchingBanks.count > EnableBankingModel.shownLimit {
                    Footnote("Showing the first \(EnableBankingModel.shownLimit) — refine the filter.")
                        .frame(maxWidth: .infinity)
                        .padding(12)
                }
            }
            .padding(.vertical, 6)
        }
        .overlay {
            if model.busy { ProgressView().controlSize(.large) }
        }

        Footnote(model.redirectNote)

        if let error = model.error { FormError(error) }
    }

    private func bankRow(_ bank: Aspsp) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "building.columns")
                .font(.system(size: 14))
                .foregroundStyle(Palette.faint)
            Text(bank.name)
                .font(.system(size: 14.5))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(bank.country)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.faint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.surface2, in: .rect(cornerRadius: 4))
            DisclosureChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }

    private func link(_ bank: Aspsp) async {
        let linked = await model.link(bank) { page in
            do {
                // Ephemeral on purpose: the sheet holds no Skarb session either way, and a bank
                // login is better not kept in a browser jar.
                return try await webAuthenticationSession.authenticate(
                    using: page,
                    callbackURLScheme: EnableBankingHandoff.callbackScheme,
                    preferredBrowserSession: .ephemeral)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                throw CancellationError()
            }
        }
        if linked { dismiss() }
    }
}

/// A caption over a filled field — the settings sheets' form row.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
            content.skarbField()
        }
    }
}
