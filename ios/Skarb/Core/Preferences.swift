import SwiftUI

/// The choices that outlive a launch, kept in one place so the keys can't drift. Each is
/// per-device, like the web's localStorage — a phone and a laptop can disagree on purpose.
enum Prefs {
    /// Light, dark, or follow the system — the web's theme toggle.
    static let themeKey = "skarb.theme"
    /// The currency every report is read in. Empty means "whatever the server calls base".
    static let currencyKey = "skarb.displayCurrency"
    /// The window the overview reopens on.
    static let periodKey = "skarb.dashboardPeriod"
    /// The tab the app reopens on.
    static let tabKey = "skarb.tab"
    /// Whether balances are spelled out. Hidden by default, as on the web: opening the app should
    /// show how the window is going, not put the whole net worth on screen before you asked.
    static let showBalancesKey = "skarb.showBalances"
}

enum ThemeMode: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}
