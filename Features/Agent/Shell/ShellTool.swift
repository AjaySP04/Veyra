import os

struct ShellTool: Tool {
    let definition = ToolDefinition(
        name: "shell",
        description: "Write a shell command into the user's terminal for them to check and run. Use for command-line tasks such as listing, finding, moving or deleting files, git, disk space and processes.",
        parameters: [
            ToolParameter(
                name: "command",
                description: "One zsh command line for macOS (BSD tools, e.g. find, du, sed -i ''), with no explanation or prompt sign",
                allowed: nil
            ),
        ]
    )
    let risk = ToolRisk.immediate

    private let inserter: TextInserting
    private let keystrokes: KeystrokeSending
    private let frontmostApp: () -> String?

    init(inserter: TextInserting, keystrokes: KeystrokeSending, frontmostApp: @escaping () -> String?) {
        self.inserter = inserter
        self.keystrokes = keystrokes
        self.frontmostApp = frontmostApp
    }

    func prepare(_ arguments: [String: String], in context: ToolContext) async throws -> PreparedAction {
        guard context.mode == .terminal else { throw AgentError.notTerminal }
        let expectedApp = context.bundleIdentifier
        guard frontmostApp() == expectedApp else { throw AgentError.appChanged }
        let command = try ShellCommand.clean(arguments["command"] ?? "")
        let risk = ShellRisk.of(command)
        Logger.agent.info("Shell command \(command.count) characters, risk \(risk?.rawValue ?? "none", privacy: .public)")

        return PreparedAction(
            done: risk.map { "Check carefully: \($0.reason)" } ?? "Command ready. Check it, then press Return",
            failure: "Couldn't write the command",
            insertion: LastInsertion(text: command, bundleIdentifier: expectedApp, ownsLine: true)
        ) { [keystrokes, inserter, frontmostApp] in
            guard frontmostApp() == expectedApp else { throw AgentError.appChanged }
            guard context.isUntouched() else { throw AgentError.interrupted }
            // ⌃E ⌃U empties the prompt line so the command can't merge with half-typed text. Return is never sent.
            keystrokes.send([.shellLineEnd, .shellDeleteLine])
            try await inserter.insert(command)
        }
    }
}
