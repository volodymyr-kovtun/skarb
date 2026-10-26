import Foundation

/// The Telegram bot low-balance alerts travel through.
@MainActor
protocol NotificationService {
    func telegramSettings() async throws -> TelegramSettings
    /// An empty token disconnects the bot.
    func saveTelegram(botToken: String) async throws -> TelegramSettings
    /// Chats that messaged the bot recently — Telegram only remembers about a day of them.
    func telegramChats() async throws -> [TelegramChat]
    /// Sends a test message. Answers with the chat it actually went to.
    func telegramTest(chatId: String) async throws -> String
}

struct LiveNotificationService: NotificationService {
    let http: any HTTPClient

    func telegramSettings() async throws -> TelegramSettings {
        try await http.send(.get("/api/notifications/telegram"))
    }

    func saveTelegram(botToken: String) async throws -> TelegramSettings {
        try await http.send(.patch("/api/notifications/telegram", body: TelegramBody(botToken: botToken)))
    }

    func telegramChats() async throws -> [TelegramChat] {
        try await http.send(.get("/api/notifications/telegram/chats"))
    }

    func telegramTest(chatId: String) async throws -> String {
        let result: SentTo = try await http.send(.post(
            "/api/notifications/telegram/test", body: ChatBody(chatId: chatId)))
        return result.sentTo
    }
}

private nonisolated struct TelegramBody: Encodable, Sendable { var botToken: String }
private nonisolated struct ChatBody: Encodable, Sendable { var chatId: String }
private nonisolated struct SentTo: Decodable, Sendable { var sentTo: String }
