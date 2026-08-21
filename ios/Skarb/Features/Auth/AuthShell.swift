import SwiftUI

/// The chrome every signed-out screen shares: the Skarb mark, a title, one card.
/// Signed-out screens have no tab bar and no data, so the screen itself is the layout.
struct AuthShell<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 14) {
                        Mark(size: 52)
                        VStack(spacing: 6) {
                            Text(title)
                                .font(.display(28))
                                .foregroundStyle(Palette.ink)
                            if let subtitle {
                                Text(subtitle)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Palette.muted)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 28)

                    Card { content.padding(22) }

                    footer
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.faint)
                        .multilineTextAlignment(.center)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

extension AuthShell where Footer == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, content: content) { EmptyView() }
    }
}

/// Inline error, sized to sit under a field without shifting the card around.
struct FormError: View {
    let message: String

    init(_ message: String) { self.message = message }

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Palette.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.danger.opacity(0.1), in: .rect(cornerRadius: Palette.Radius.row))
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Where the app looks for a ledger. Editable before sign-in and from Settings after, because
/// a self-hosted app whose address is baked in is a self-hosted app you can only use once.
struct ServerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = APIClient.shared.baseURL.absoluteString
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("The address of your Skarb server. Signing in again is expected — the session belongs to the server you leave behind.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(3)

                    TextField("https://skarb.example.com", text: $text)
                        .skarbField()
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit(save)

                    if let error { FormError(error) }

                    Button("Use this server", action: save)
                        .buttonStyle(.skarbPrimary)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let url = ServerSettings.normalize(text) else {
            error = "That doesn't look like a web address."
            return
        }
        dismiss()
        Task { await model.switchServer(to: url) }
    }
}
