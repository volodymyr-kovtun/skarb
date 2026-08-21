import SwiftUI

/// Password plus a second factor, exactly as the web asks for it. There is no signup — a
/// Skarb instance is claimed once, and only its owner ever signs in.
struct LoginView: View {
    @Environment(AppModel.self) private var model

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var recoveryCode = ""
    @State private var usingRecovery = false
    @State private var busy = false
    @State private var error: String?
    @State private var showingServer = false

    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, password, code }

    private var secondFactorFilled: Bool {
        usingRecovery ? !recoveryCode.trimmed.isEmpty : code.trimmed.count >= 6
    }
    private var canSubmit: Bool {
        !busy && !email.trimmed.isEmpty && !password.isEmpty && secondFactorFilled
    }

    var body: some View {
        AuthShell(title: "Skarb", subtitle: "Sign in to your ledger.") {
            VStack(alignment: .leading, spacing: 16) {
                field("Email") {
                    TextField("", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }

                field("Password") {
                    SecureField("", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focus = .code }
                }

                if usingRecovery {
                    field("Recovery code") {
                        TextField("xxxxx-xxxxx", text: $recoveryCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .monospaced()
                            .focused($focus, equals: .code)
                            .submitLabel(.go)
                            .onSubmit(submit)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        field("Authenticator code") {
                            TextField("000000", text: $code)
                                .textContentType(.oneTimeCode)
                                .keyboardType(.numberPad)
                                .monospacedDigit()
                                .font(.system(size: 18, weight: .semibold))
                                .tracking(6)
                                .multilineTextAlignment(.center)
                                .focused($focus, equals: .code)
                                .onChange(of: code) { _, new in
                                    code = String(new.filter(\.isNumber).prefix(6))
                                }
                        }
                        Text("Each code works once. If you just signed in, wait for the next one.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.faint)
                    }
                }

                if let error { FormError(error) }

                Button(busy ? "Signing in…" : "Sign in", action: submit)
                    .buttonStyle(.skarbPrimary)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)

                Button(usingRecovery ? "Use my authenticator app" : "Lost your phone? Use a recovery code") {
                    usingRecovery.toggle()
                    error = nil
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
            }
        } footer: {
            Button {
                showingServer = true
            } label: {
                Text(APIClient.shared.baseURL.host() ?? APIClient.shared.baseURL.absoluteString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.faint)
                    .underline()
            }
        }
        .sheet(isPresented: $showingServer) { ServerSheet() }
    }

    @ViewBuilder
    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
            content().skarbField()
        }
    }

    private func submit() {
        guard canSubmit else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await APIClient.shared.login(
                    email: email.trimmed,
                    password: password,
                    code: usingRecovery ? nil : code.trimmed,
                    recoveryCode: usingRecovery ? recoveryCode.trimmed : nil)
                password = ""
                code = ""
                recoveryCode = ""
                await model.loadSession()
            } catch {
                self.error = error.localizedDescription
                code = ""
                recoveryCode = ""
            }
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
