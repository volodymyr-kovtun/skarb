import Foundation

nonisolated struct Session: Codable, Sendable {
    var authenticated: Bool
    var email: String?
    var setupRequired: Bool
}

/// What claiming an instance hands back after the password: the TOTP secret to enroll, both
/// raw (for typing in) and as an `otpauth://` URI (for an authenticator to open or scan).
nonisolated struct SetupChallenge: Codable, Sendable, Equatable {
    var secret: String
    var provisioningUri: String
}

nonisolated struct RecoveryCodes: Codable, Sendable {
    var recoveryCodes: [String]
}
