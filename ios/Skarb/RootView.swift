import SwiftUI

/// Decides what the app is right now: unreachable, unclaimed, signed out, or ready.
/// Everything else sits behind it, so no screen can be reached without a session.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                Splash()
            case .unreachable(let message):
                UnreachableView(message: message)
            case .setupRequired:
                SetupRequiredView()
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabView()
            }
        }
        .animation(.smooth(duration: 0.25), value: model.phase)
        .task {
            if case .loading = model.phase { await model.loadSession() }
        }
    }
}

private struct Splash: View {
    @State private var breathing = false

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            Mark(size: 56)
                .opacity(breathing ? 0.45 : 1)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: breathing)
                .onAppear { breathing = true }
        }
        .accessibilityLabel("Loading")
    }
}

/// The server didn't answer. Almost always the address or the network, so both the retry and
/// the way to change the address are right here.
private struct UnreachableView: View {
    let message: String
    @Environment(AppModel.self) private var model
    @State private var showingServer = false

    var body: some View {
        AuthShell(title: "Skarb", subtitle: "No answer from your ledger.") {
            VStack(spacing: 14) {
                FormError(message)
                Button("Try again") {
                    Task { await model.loadSession() }
                }
                .buttonStyle(.skarbPrimary)

                Button("Change server address") { showingServer = true }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
        } footer: {
            Text(APIClient.shared.baseURL.absoluteString)
        }
        .sheet(isPresented: $showingServer) { ServerSheet() }
    }
}

/// An unclaimed instance needs the one-time setup token that Skarb prints to the server log.
/// That is a desktop errand, and saying so beats a form nobody can fill in from a phone.
private struct SetupRequiredView: View {
    @Environment(AppModel.self) private var model
    @State private var showingServer = false

    var body: some View {
        AuthShell(title: "Not claimed yet", subtitle: "This Skarb instance has no owner.") {
            VStack(spacing: 14) {
                Text("""
                    Finish setup in a browser at \(APIClient.shared.baseURL.absoluteString). \
                    It needs the one-time setup token from the server log, plus an authenticator \
                    app to scan the QR code. Come back here once you can sign in.
                    """)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(3)

                Button("Check again") {
                    Task { await model.loadSession() }
                }
                .buttonStyle(.skarbPrimary)

                Button("Change server address") { showingServer = true }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
        }
        .sheet(isPresented: $showingServer) { ServerSheet() }
    }
}
