import SwiftUI

/// Decides what the app is right now: unreachable, unclaimed, signed out, or ready.
/// Everything else sits behind it, so no screen can be reached without a session.
struct RootView: View {
    @Environment(AppContainer.self) private var app
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                Splash()
            case .unreachable(let message):
                UnreachableView(message: message)
            case .setupRequired:
                SetupFlow(model: app.makeSetup())
            case .signedOut:
                LoginView(model: app.makeLogin())
            case .signedIn:
                MainTabView()
            }
        }
        .animation(.smooth(duration: 0.25), value: session.phase)
        .task {
            if case .loading = session.phase { await session.load() }
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
    @Environment(AppContainer.self) private var app
    @State private var showingServer = false

    var body: some View {
        AuthShell(title: "Skarb", subtitle: "No answer from your ledger.") {
            VStack(spacing: 14) {
                FormError(message)
                Button("Try again") {
                    Task { await app.session.load() }
                }
                .buttonStyle(.skarbPrimary)

                Button("Change server address") { showingServer = true }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
        } footer: {
            Text(app.server.baseURL.absoluteString)
        }
        .sheet(isPresented: $showingServer) { ServerSheet() }
    }
}
