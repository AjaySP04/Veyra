import Foundation
import os

struct SendTool: Tool {
    static let limit = 4_000

    let definition = ToolDefinition(
        name: "send",
        description: "Write a message into the chat or email the user has open, for them to confirm before it is sent. Use when the user asks to reply, send, answer, tell or message someone in the open conversation and says what to write. If they don't say what the message is, don't use this tool.",
        parameters: [
            ToolParameter(
                name: "message",
                description: "The message the user asked to send, written as the user in the first person, with no quotes or explanation. Never make one up",
                allowed: nil
            ),
        ]
    )
    let risk = ToolRisk.confirm

    private let inserter: TextInserting
    private let keystrokes: KeystrokeSending
    private let frontmostApp: () -> String?

    init(inserter: TextInserting, keystrokes: KeystrokeSending, frontmostApp: @escaping () -> String?) {
        self.inserter = inserter
        self.keystrokes = keystrokes
        self.frontmostApp = frontmostApp
    }

    func prepare(_ arguments: [String: String], in context: ToolContext) async throws -> PreparedAction {
        guard let sendKey = SendKey.for(mode: context.mode, bundleIdentifier: context.bundleIdentifier) else {
            throw AgentError.notMessaging
        }
        let expectedApp = context.bundleIdentifier
        guard frontmostApp() == expectedApp else { throw AgentError.appChanged }
        let message = Self.unwrap(arguments["message"] ?? "")
        guard !message.isEmpty else { throw AgentError.invalidArguments }
        guard message.count <= Self.limit else { throw AgentError.messageTooLong }
        Logger.agent.info("Send draft \(message.count) characters")

        let checks = { [frontmostApp] in
            guard frontmostApp() == expectedApp else { throw AgentError.appChanged }
            guard context.isUntouched() else { throw AgentError.interrupted }
        }
        // Pasting never sends: only the confirmation presses the send key.
        let confirmation = Confirmation(done: "Sent", failure: "Couldn't send") { [keystrokes] in
            try checks()
            keystrokes.send([sendKey])
        }
        return PreparedAction(
            done: context.mode == .email ? "Say “send it” to send the email" : "Say “send it” to send",
            failure: "Couldn't write the message",
            insertion: LastInsertion(text: message, bundleIdentifier: expectedApp),
            confirmation: confirmation
        ) { [inserter] in
            try checks()
            try await inserter.insert(message)
        }
    }

    /// Trims the model's message and strips quotes wrapped around the whole of it.
    static func unwrap(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”")]
        for (open, close) in pairs where text.count >= 2 && text.first == open && text.last == close {
            let inner = text.dropFirst().dropLast()
            guard !inner.contains(open), !inner.contains(close) else { break }
            return inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
