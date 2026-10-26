import Foundation
import Observation

/// Where the ledger lives. Defaults to the hosted instance; a self-hoster points it elsewhere
/// from the sign-in screen or Settings. Observable, because the address is printed in several
/// places and every one of them should follow a switch.
@Observable
final class ServerAddress {
    static let defaultURL = URL(string: "https://skarb.subero.app")!
    private static let key = "skarb.serverURL"

    private let defaults: UserDefaults

    var baseURL: URL {
        didSet { defaults.set(baseURL.absoluteString, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baseURL = defaults.string(forKey: Self.key).flatMap(URL.init(string:)) ?? Self.defaultURL
    }

    /// The host on its own, for the places a whole URL would wrap — "skarb.subero.app".
    var host: String { baseURL.host() ?? baseURL.absoluteString }

    /// Where Enable Banking sends an authorization back to. It has to be the very URL the web app
    /// uses, because that is the one the owner registered with Enable Banking — see
    /// `EnableBankingHandoff` for how it finds its way from there back into the app.
    var bankRedirectURL: URL { baseURL.appending(path: "settings") }
}
