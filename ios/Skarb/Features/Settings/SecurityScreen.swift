import SwiftUI

@Observable
final class SecurityModel {
    private(set) var remaining = 0
    private let auth: any AuthService

    init(auth: any AuthService) {
        self.auth = auth
    }

    func load() async {
        if let left = try? await auth.recoveryCodesLeft() { remaining = left }
    }

    func makeChangePassword() -> ChangePasswordModel { ChangePasswordModel(auth: auth) }
    func makeRegenerate() -> RegenerateCodesModel { RegenerateCodesModel(auth: auth) }
}

@Observable
final class ChangePasswordModel {
    var current = ""
    var next = ""
    var confirmation = ""
    private(set) var busy = false
    private(set) var error: String?
    private(set) var done = false

    private let auth: any AuthService

    init(auth: any AuthService) {
        self.auth = auth
    }

    var canSubmit: Bool {
        !busy && !current.isEmpty && CredentialPolicy.isLongEnough(next) && next == confirmation
    }

    func submit() async {
        guard canSubmit else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await auth.changePassword(current: current, new: next)
            current = ""
            next = ""
            confirmation = ""
            done = true
        } catch {
            // "Current password is incorrect" arrives as a 401; the session re-check that every
            // 401 triggers finds the session alive, so it stays a message here and nothing more.
            self.error = error.localizedDescription
        }
    }
}

@Observable
final class RegenerateCodesModel {
    var password = ""
    private(set) var codes: [String]?
    private(set) var busy = false
    private(set) var error: String?

    private let auth: any AuthService

    init(auth: any AuthService) {
        self.auth = auth
    }

    func regenerate() async {
        guard !busy, !password.isEmpty else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            codes = try await auth.newRecoveryCodes(currentPassword: password)
            password = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension AppContainer {
    func makeSecurity() -> SecurityModel { SecurityModel(auth: auth) }
}

/// Account security, as its own slice of Settings — nothing here touches bank connections.
struct SecurityScreen: View {
    @State private var model: SecurityModel
    @State private var changingPassword = false
    @State private var regenerating = false
    @Environment(SessionStore.self) private var session

    init(model: SecurityModel) { _model = State(initialValue: model) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    VStack(spacing: 0) {
                        SettingsRow(title: "Signed in as") {
                            Text(session.email ?? "—")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                        }
                        Divider().padding(.leading, 16)
                        SettingsRow(title: "Two-factor") {
                            Label("Authenticator app", systemImage: "checkmark.shield.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.income)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Palette.income.opacity(0.1), in: .capsule)
                        }
                        Divider().padding(.leading, 16)
                        SettingsRow(title: "Recovery codes") {
                            Text("\(model.remaining) unused")
                                .font(.system(size: 13.5, weight: model.remaining <= 2 ? .semibold : .regular))
                                .foregroundStyle(model.remaining <= 2 ? Palette.danger : Palette.muted)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 4)
                }

                Card {
                    VStack(spacing: 0) {
                        Button { changingPassword = true } label: {
                            SettingsRow(title: "Change password", icon: "key") { DisclosureChevron() }
                        }
                        .buttonStyle(RowButtonStyle())
                        Divider().padding(.leading, 54)
                        Button { regenerating = true } label: {
                            SettingsRow(
                                title: "Regenerate recovery codes",
                                subtitle: "Issues a fresh set and invalidates the old one",
                                icon: "arrow.triangle.2.circlepath") { DisclosureChevron() }
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96)
        }
        .background(Palette.paper)
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .sheet(isPresented: $changingPassword) { ChangePasswordSheet(model: model.makeChangePassword()) }
        .sheet(isPresented: $regenerating, onDismiss: { Task { await model.load() } }) {
            RegenerateCodesSheet(model: model.makeRegenerate())
        }
    }
}

private struct ChangePasswordSheet: View {
    @State private var model: ChangePasswordModel
    @Environment(\.dismiss) private var dismiss

    init(model: ChangePasswordModel) { _model = State(initialValue: model) }

    var body: some View {
        SheetScaffold(title: "Change password") {
            if model.done {
                Text("Password updated. Every other signed-in device has been signed out.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                Button("Done") { dismiss() }.buttonStyle(.skarbPrimary)
            } else {
                secure("Current password", $model.current, content: .password)
                VStack(alignment: .leading, spacing: 5) {
                    secure("New password", $model.next, content: .newPassword)
                    Footnote("At least \(CredentialPolicy.minimumPasswordLength) characters.")
                }
                secure("Confirm new password", $model.confirmation, content: .newPassword)
                if let error = model.error { FormError(error) }
                Button(model.busy ? "Saving…" : "Change password") { Task { await model.submit() } }
                    .buttonStyle(.skarbPrimary)
                    .disabled(!model.canSubmit)
                    .opacity(model.canSubmit ? 1 : 0.5)
            }
        }
    }

    private func secure(_ label: String, _ text: Binding<String>, content: UITextContentType) -> some View {
        LabeledField(label) {
            SecureField("", text: text).textContentType(content)
        }
    }
}

private struct RegenerateCodesSheet: View {
    @State private var model: RegenerateCodesModel
    @Environment(\.dismiss) private var dismiss

    init(model: RegenerateCodesModel) { _model = State(initialValue: model) }

    var body: some View {
        SheetScaffold(title: "Recovery codes") {
            if let codes = model.codes {
                RecoveryCodesView(codes: codes)
                Footnote("The previous set no longer works. Replace whatever copy you kept.")
                Button("Done") { dismiss() }.buttonStyle(.skarbPrimary)
            } else {
                Text("This issues a fresh set and invalidates the old one. Confirm with your password.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                SecureField("Password", text: $model.password)
                    .textContentType(.password)
                    .skarbField()
                if let error = model.error { FormError(error) }
                Button(model.busy ? "Generating…" : "Generate new codes") { Task { await model.regenerate() } }
                    .buttonStyle(.skarbPrimary)
                    .disabled(model.busy || model.password.isEmpty)
                    .opacity(model.password.isEmpty ? 0.5 : 1)
            }
        }
        // Codes that were never written down are a lock-out waiting to happen.
        .interactiveDismissDisabled(model.codes != nil)
    }
}
