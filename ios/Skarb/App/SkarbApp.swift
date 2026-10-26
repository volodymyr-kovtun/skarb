import SwiftUI

@main
struct SkarbApp: App {
    @State private var app = AppContainer()
    @AppStorage(Prefs.themeKey) private var theme: ThemeMode = .system
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.session)
                .environment(app.ledger)
                .environment(app.sync)
                .environment(app.toasts)
                .environment(app.router)
                .preferredColorScheme(theme.colorScheme)
                .tint(Palette.accent)
                .onOpenURL { app.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: app.becameActive()
            case .background: app.movedToBackground()
            default: break
            }
        }
    }
}
