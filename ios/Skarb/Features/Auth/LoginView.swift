import SwiftUI

@Observable
final class LoginModel {
    var email = ""
    var password = ""
    var code = ""
    var recoveryCode = ""
    var usingRecovery = false {
        didSet { error = nil }
    }
    private(set) var busy = false
    private(set) var error: String?

    private let auth: any AuthService
    private let session: SessionStore

    init(auth: any AuthService, session: SessionStore) {
        self.auth = auth
        self.session = session
    }

    private var secondFactorFilled: Bool {
        usingRecovery ? !recoveryCode.trimmed.isEmpty : code.count == 6
    }

    var canSubmit: Bool {
        !busy && !email.trimmed.isEmpty && !password.isEmpty && secondFactorFilled
    }

    func submit() async {
        guard canSubmit else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await auth.login(
                email: email.trimmed,
                password: password,
                code: usingRecovery ? nil : code,
                recoveryCode: usingRecovery ? recoveryCode.trimmed : nil)
            password = ""
            await session.load()
        } catch {
            self.error = error.localizedDescription
        }
        // Each code works once, so a used or rejected one is never worth keeping in the field.
        code = ""
        recoveryCode = ""
    }
}

extension AppContainer {
    func makeLogin() -> LoginModel { LoginModel(auth: auth, session: session) }
}

/// Password plus a second factor, exactly as the web asks for it. There is no signup — a
/// Skarb instance is claimed once, and only its owner ever signs in.
struct LoginView: View {
    @State private var model: LoginModel
    @State private var showingServer = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, password, code }

    init(model: LoginModel) { _model = State(initialValue: model) }

    var body: some View {
        AuthShell(title: "Skarb", subtitle: "Sign in to your ledger.") {
            VStack(alignment: .leading, spacing: 16) {
                AuthField("Email") {
                    TextField("", text: $model.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }

                AuthField("Password") {
                    SecureField("", text: $model.password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focus = .code }
                }

                if model.usingRecovery {
                    AuthField("Recovery code") {
                        TextField("xxxxx-xxxxx", text: $model.recoveryCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .monospaced()
                            .focused($focus, equals: .code)
                            .submitLabel(.go)
                            .onSubmit { Task { await model.submit() } }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        AuthField("Authenticator code") {
                            TOTPField(code: $model.code).focused($focus, equals: .code)
                        }
                        Text("Each code works once. If you just signed in, wait for the next one.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.faint)
                    }
                }

                if let error = model.error { FormError(error) }

                Button(model.busy ? "Signing in…" : "Sign in") { Task { await model.submit() } }
                    .buttonStyle(.skarbPrimary)
                    .disabled(!model.canSubmit)
                    .opacity(model.canSubmit ? 1 : 0.5)

                Button(model.usingRecovery ? "Use my authenticator app" : "Lost your phone? Use a recovery code") {
                    model.usingRecovery.toggle()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
            }
        } footer: {
            ServerFootnote { showingServer = true }
        }
        .sheet(isPresented: $showingServer) { ServerSheet() }
    }
}

/// Six digits, big and spaced, and nothing else — pasting "123 456" or a whole SMS still works.
struct TOTPField: View {
    @Binding var code: String

    var body: some View {
        TextField("000000", text: $code)
            .textContentType(.oneTimeCode)
            .keyboardType(.numberPad)
            .monospacedDigit()
            .font(.system(size: 18, weight: .semibold))
            .tracking(6)
            .multilineTextAlignment(.center)
            .onChange(of: code) { _, new in
                let digits = CredentialPolicy.totpDigits(new)
                if digits != new { code = digits }
            }
    }
}

/// The server address under a signed-out form, tappable to change it.
struct ServerFootnote: View {
    var action: () -> Void
    @Environment(AppContainer.self) private var app

    var body: some View {
        Button(action: action) {
            Text(app.server.host)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.faint)
                .underline()
        }
        .accessibilityLabel("Server \(app.server.host). Change it.")
    }
}
