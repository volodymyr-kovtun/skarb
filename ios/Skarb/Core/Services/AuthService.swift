import Foundation

/// Signing in, claiming an instance, and the owner's own credentials.
@MainActor
protocol AuthService {
    func session() async throws -> Session
    func login(email: String, password: String, code: String?, recoveryCode: String?) async throws
    func logout() async throws
    /// Step one of claiming an unclaimed instance: the setup token from the server log, plus the
    /// owner's email and password. Answers with the authenticator secret to enroll.
    func beginSetup(token: String, email: String, password: String) async throws -> SetupChallenge
    /// Step two: a code from the freshly enrolled authenticator. Signs in, and answers with the
    /// recovery codes — the only time they are ever shown.
    func confirmSetup(token: String, code: String) async throws -> [String]
    func changePassword(current: String, new: String) async throws
    func newRecoveryCodes(currentPassword: String) async throws -> [String]
    func recoveryCodesLeft() async throws -> Int
}

struct LiveAuthService: AuthService {
    let http: any HTTPClient

    func session() async throws -> Session { try await http.send(.get("/api/auth/session")) }

    func login(email: String, password: String, code: String?, recoveryCode: String?) async throws {
        let _: NoContent = try await http.send(.post("/api/auth/login", body: LoginBody(
            email: email, password: password, code: code, recoveryCode: recoveryCode)))
    }

    func logout() async throws {
        let _: NoContent = try await http.send(.post("/api/auth/logout"))
    }

    func beginSetup(token: String, email: String, password: String) async throws -> SetupChallenge {
        try await http.send(.post("/api/auth/setup", body: SetupBody(
            setupToken: token, email: email, password: password)))
    }

    func confirmSetup(token: String, code: String) async throws -> [String] {
        let codes: RecoveryCodes = try await http.send(.post(
            "/api/auth/setup/confirm", body: SetupConfirmBody(setupToken: token, code: code)))
        return codes.recoveryCodes
    }

    func changePassword(current: String, new: String) async throws {
        let _: NoContent = try await http.send(.post("/api/auth/password", body: ChangePasswordBody(
            currentPassword: current, newPassword: new)))
    }

    func newRecoveryCodes(currentPassword: String) async throws -> [String] {
        let codes: RecoveryCodes = try await http.send(.post(
            "/api/auth/recovery-codes", body: CurrentPasswordBody(currentPassword: currentPassword)))
        return codes.recoveryCodes
    }

    func recoveryCodesLeft() async throws -> Int {
        let result: Remaining = try await http.send(.get("/api/auth/recovery-codes/remaining"))
        return result.remaining
    }
}

private nonisolated struct LoginBody: Encodable, Sendable {
    var email: String
    var password: String
    var code: String?
    var recoveryCode: String?
}

private nonisolated struct SetupBody: Encodable, Sendable {
    var setupToken: String
    var email: String
    var password: String
}

private nonisolated struct SetupConfirmBody: Encodable, Sendable {
    var setupToken: String
    var code: String
}

private nonisolated struct ChangePasswordBody: Encodable, Sendable {
    var currentPassword: String
    var newPassword: String
}

private nonisolated struct CurrentPasswordBody: Encodable, Sendable { var currentPassword: String }
private nonisolated struct Remaining: Decodable, Sendable { var remaining: Int }
