import SwiftUI

/// Account security, as its own slice of Settings — nothing here touches bank connections.
struct SecurityScreen: View {
    @Environment(AppModel.self) private var model

    @State private var remaining = 0
    @State private var changingPassword = false
    @State private var regenerating = false

    private var email: String {
        if case .signedIn(let email) = model.phase { return email ?? "—" }
        return "—"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    VStack(spacing: 0) {
                        SettingsRow(title: "Signed in as") {
                            Text(email)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                        }
                        Divider().padding(.leading, 16)
                        SettingsRow(title: "Two-factor") {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.shield.fill")
                                Text("Authenticator app")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.income)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Palette.income.opacity(0.1), in: .capsule)
                        }
                        Divider().padding(.leading, 16)
                        SettingsRow(title: "Recovery codes") {
                            Text("\(remaining) unused")
                                .font(.system(size: 13.5, weight: remaining <= 2 ? .semibold : .regular))
                                .foregroundStyle(remaining <= 2 ? Palette.danger : Palette.muted)
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
        .task { remaining = (try? await APIClient.shared.recoveryCodesLeft()) ?? 0 }
        .sheet(isPresented: $changingPassword) { ChangePasswordSheet() }
        .sheet(isPresented: $regenerating) {
            RegenerateCodesSheet { remaining = (try? await APIClient.shared.recoveryCodesLeft()) ?? 0 }
        }
    }
}

private struct ChangePasswordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Matches the server's floor, so a rejected password is a surprise rather than the norm.
    private static let minimum = 12

    @State private var current = ""
    @State private var next = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var error: String?
    @State private var done = false

    private var canSubmit: Bool {
        !busy && !current.isEmpty && next.count >= Self.minimum && next == confirmation
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()
                ScrollView {
                    if done {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Password updated. Every other signed-in device has been signed out.")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.muted)
                            Button("Done") { dismiss() }.buttonStyle(.skarbPrimary)
                        }
                        .padding(20)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            secure("Current password", $current, content: .password)
                            VStack(alignment: .leading, spacing: 5) {
                                secure("New password", $next, content: .newPassword)
                                Text("At least \(Self.minimum) characters.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.faint)
                            }
                            secure("Confirm new password", $confirmation, content: .newPassword)
                            if let error { FormError(error) }
                            Button(busy ? "Saving…" : "Change password") { Task { await save() } }
                                .buttonStyle(.skarbPrimary)
                                .disabled(!canSubmit)
                                .opacity(canSubmit ? 1 : 0.5)
                        }
                        .padding(20)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !done {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                }
            }
        }
    }

    private func secure(
        _ label: String, _ text: Binding<String>, content: UITextContentType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
            SecureField("", text: text)
                .textContentType(content)
                .skarbField()
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        error = nil
        do {
            try await APIClient.shared.changePassword(current: current, new: next)
            current = ""
            next = ""
            confirmation = ""
            done = true
        } catch {
            model.handle(error)
            self.error = error.localizedDescription
        }
    }
}

private struct RegenerateCodesSheet: View {
    var onDone: () async -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var codes: [String]?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()
                ScrollView {
                    if let codes {
                        VStack(alignment: .leading, spacing: 16) {
                            RecoveryCodesView(codes: codes)
                            Text("The previous set no longer works. Replace whatever copy you kept.")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                            Button("Done") {
                                Task { await onDone() }
                                dismiss()
                            }
                            .buttonStyle(.skarbPrimary)
                        }
                        .padding(20)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("This issues a fresh set and invalidates the old one. Confirm with your password.")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.muted)
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .skarbField()
                            if let error { FormError(error) }
                            Button(busy ? "Generating…" : "Generate new codes") { Task { await regenerate() } }
                                .buttonStyle(.skarbPrimary)
                                .disabled(busy || password.isEmpty)
                                .opacity(password.isEmpty ? 0.5 : 1)
                        }
                        .padding(20)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Recovery codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if codes == nil {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                }
            }
        }
        .interactiveDismissDisabled(codes != nil)
    }

    private func regenerate() async {
        busy = true
        defer { busy = false }
        error = nil
        do {
            codes = try await APIClient.shared.newRecoveryCodes(currentPassword: password).recoveryCodes
            password = ""
        } catch {
            model.handle(error)
            self.error = error.localizedDescription
        }
    }
}

/// Single-use codes, shown once. Copying them is the only thing that matters here, so the
/// button that does it sits right under them.
struct RecoveryCodesView: View {
    let codes: [String]
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Each code signs you in once if you lose your authenticator. Store them somewhere safe — this is the only time they are shown.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(codes, id: \.self) { code in
                    Text(code)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Palette.surface2, in: .rect(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            }

            Button {
                UIPasteboard.general.string = codes.joined(separator: "\n")
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy all codes", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Palette.accent)
        }
    }
}
