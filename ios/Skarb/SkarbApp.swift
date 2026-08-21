import SwiftUI

@main
struct SkarbApp: App {
    @State private var model = AppModel()
    @AppStorage(Prefs.themeKey) private var theme: ThemeMode = .system
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(theme.colorScheme)
                .tint(Palette.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            // Nothing should be polling a server while the app is in someone's pocket.
            switch phase {
            case .active:
                if case .signedIn = model.phase {
                    model.startSyncPolling()
                    Task { await model.invalidate() }
                }
            case .background, .inactive:
                model.stopSyncPolling()
            @unknown default:
                break
            }
        }
    }
}
