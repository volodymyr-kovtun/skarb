import SwiftUI

/// Claiming a fresh instance, in the web's three steps: credentials, authenticator, recovery
/// codes. The account only becomes usable at the end, so a half-finished setup can be redone.
@Observable
final class SetupModel {
    enum Step: Equatable {
        case credentials
        case authenticator(SetupChallenge)
        case recoveryCodes([String])

        var number: Int {
            switch self {
            case .credentials: 1
            case .authenticator: 2
            case .recoveryCodes: 3
            }
        }
    }

    private(set) var step: Step = .credentials
    var token = ""
    var email = ""
    var password = ""
    var confirmation = ""
    var code = ""
    private(set) var busy = false
    private(set) var error: String?

    private let auth: any AuthService
    private let session: SessionStore

    init(auth: any AuthService, session: SessionStore) {
        self.auth = auth
        self.session = session
    }

    var passwordsDiffer: Bool { !confirmation.isEmpty && confirmation != password }

    var canBegin: Bool {
        !busy && !token.trimmed.isEmpty && CredentialPolicy.isPlausibleEmail(email)
            && CredentialPolicy.isLongEnough(password) && confirmation == password
    }

    var canConfirm: Bool { !busy && code.count == 6 }

    func begin() async {
        guard canBegin else { return }
        await run {
            let challenge = try await auth.beginSetup(token: token.trimmed, email: email.trimmed, password: password)
            password = ""
            confirmation = ""
            step = .authenticator(challenge)
        }
    }

    func confirm() async {
        guard canConfirm else { return }
        await run {
            do {
                step = .recoveryCodes(try await auth.confirmSetup(token: token.trimmed, code: code))
            } catch {
                code = ""
                throw error
            }
        }
    }

    /// The server signed the new owner in when the code was confirmed; reading the session
    /// again is what opens the app.
    func finish() async {
        await session.load()
    }

    private func run(_ body: () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do { try await body() } catch { self.error = error.localizedDescription }
    }
}

extension AppContainer {
    func makeSetup() -> SetupModel { SetupModel(auth: auth, session: session) }
}

struct SetupFlow: View {
    @State private var model: SetupModel
    @State private var showingServer = false

    init(model: SetupModel) { _model = State(initialValue: model) }

    var body: some View {
        AuthShell(title: title, subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 18) {
                StepBars(current: model.step.number)
                switch model.step {
                case .credentials:
                    CredentialsStep(model: model)
                case .authenticator(let challenge):
                    AuthenticatorStep(model: model, challenge: challenge)
                case .recoveryCodes(let codes):
                    VStack(alignment: .leading, spacing: 16) {
                        RecoveryCodesView(codes: codes)
                        Text("Store them somewhere other than the device holding your authenticator — a password manager or a printout. They are shown only now.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.muted)
                            .padding(12)
                            .background(Palette.surface2, in: .rect(cornerRadius: Palette.Radius.row))
                        Button("I've saved them — open Skarb") { Task { await model.finish() } }
                            .buttonStyle(.skarbPrimary)
                    }
                }
            }
        } footer: {
            if model.step == .credentials {
                VStack(spacing: 8) {
                    Text("The setup token was printed in the server log when Skarb started.")
                    ServerFootnote { showingServer = true }
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: model.step)
        .sheet(isPresented: $showingServer) { ServerSheet() }
    }

    private var title: String {
        model.step.number == 3 ? "Save your recovery codes" : "Set up Skarb"
    }

    private var subtitle: String {
        switch model.step {
        case .credentials: "This instance has no owner yet. Claim it to keep your finances yours."
        case .authenticator: "Add Skarb to your authenticator app, then confirm a code."
        case .recoveryCodes: "Each code signs you in once if you ever lose your authenticator."
        }
    }
}

private struct StepBars: View {
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { n in
                Capsule()
                    .fill(n <= current ? Palette.ink : Palette.line)
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current) of 3")
    }
}

private struct CredentialsStep: View {
    @Bindable var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AuthField("Setup token") {
                TextField("", text: $model.token)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            AuthField("Email") {
                TextField("", text: $model.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            VStack(alignment: .leading, spacing: 5) {
                AuthField("Password") {
                    SecureField("", text: $model.password).textContentType(.newPassword)
                }
                Text("At least \(CredentialPolicy.minimumPasswordLength) characters. A passphrase of a few words beats a short scramble.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.faint)
            }
            VStack(alignment: .leading, spacing: 5) {
                AuthField("Confirm password") {
                    SecureField("", text: $model.confirmation).textContentType(.newPassword)
                }
                if model.passwordsDiffer {
                    Text("Passwords don't match.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.danger)
                }
            }
            if let error = model.error { FormError(error) }
            Button(model.busy ? "Creating…" : "Continue") { Task { await model.begin() } }
                .buttonStyle(.skarbPrimary)
                .disabled(!model.canBegin)
                .opacity(model.canBegin ? 1 : 0.5)
        }
    }
}

private struct AuthenticatorStep: View {
    @Bindable var model: SetupModel
    let challenge: SetupChallenge
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // On the phone that will hold the authenticator, scanning its own screen is impossible
            // — so the link that opens the authenticator comes first, and the code is there for
            // an authenticator on another device.
            if let url = URL(string: challenge.provisioningUri) {
                Button {
                    openURL(url)
                } label: {
                    Label("Add to an authenticator on this iPhone", systemImage: "key.viewfinder")
                }
                .buttonStyle(.skarbPrimary)
            }

            HStack {
                Spacer()
                QRCodeImage(text: challenge.provisioningUri, size: 156)
                Spacer()
            }
            Text("Or scan with 1Password, Aegis, Bitwarden, Google Authenticator — any TOTP app.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("Can't scan? Enter the key by hand")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.faint)
                HStack(alignment: .top) {
                    Text(challenge.secret)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = challenge.secret
                        copied = true
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                }
                .padding(12)
                .background(Palette.surface2, in: .rect(cornerRadius: Palette.Radius.row))
            }

            AuthField("Code from the app") { TOTPField(code: $model.code) }

            if let error = model.error { FormError(error) }

            Button {
                Task { await model.confirm() }
            } label: {
                Label(model.busy ? "Verifying…" : "Turn on two-factor", systemImage: "checkmark.shield")
            }
            .buttonStyle(.skarbPrimary)
            .disabled(!model.canConfirm)
            .opacity(model.canConfirm ? 1 : 0.5)
        }
    }
}
