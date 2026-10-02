import Foundation
import os

struct RewriteTool: Tool {
    private static let limit = 4_000

    let definition = ToolDefinition(
        name: "rewrite",
        description: "Rewrite, translate, shorten, summarize or fix the user's selected text or their last dictation, following an instruction.",
        parameters: [
            ToolParameter(
                name: "instruction",
                description: "What to change, in a few words, e.g. more formal, translate to Hindi, shorter, fix grammar",
                allowed: nil
            ),
        ]
    )
    let risk = ToolRisk.immediate

    private enum Source: String {
        case lastInsertion = "last-insertion"
        case selection
        case clipboard
    }

    private let selection: SelectionReading
    private let copier: SelectionCopying
    private let rewriter: TextRewriting
    private let inserter: TextInserting
    private let keystrokes: KeystrokeSending
    private let frontmostApp: () -> String?
    private let settle: (Int) async -> Void

    init(
        selection: SelectionReading, copier: SelectionCopying, rewriter: TextRewriting,
        inserter: TextInserting, keystrokes: KeystrokeSending, frontmostApp: @escaping () -> String?,
        settle: @escaping (Int) async -> Void = RewriteTool.waitForKeys
    ) {
        self.settle = settle
        self.selection = selection
        self.copier = copier
        self.rewriter = rewriter
        self.inserter = inserter
        self.keystrokes = keystrokes
        self.frontmostApp = frontmostApp
    }

    func prepare(_ arguments: [String: String], in context: ToolContext) async throws -> PreparedAction {
        guard let instruction = arguments["instruction"]?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty else {
            throw AgentError.invalidArguments
        }
        let (source, original) = try await sourceText(in: context)
        guard original.count <= Self.limit else { throw AgentError.tooLong }
        let isTerminal = context.mode == .terminal
        let reply = try await rewriter.rewrite(original, instruction: instruction)
        var rewritten = context.mode.finalize(isTerminal ? ShellCommand.unwrap(reply) : reply)
        guard !rewritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentError.rewriteFailed }
        // Anything pasted at a prompt is a command, so it gets the shell tool's checks and warning.
        if isTerminal { rewritten = try ShellCommand.clean(rewritten) }
        let risk = isTerminal ? ShellRisk.of(rewritten) : nil
        Logger.agent.info("Rewrite source \(source.rawValue, privacy: .public) \(original.count) → \(rewritten.count) characters")

        let ownsLine = isTerminal && source == .lastInsertion && context.lastInsertion?.ownsLine == true
        let removal: [KeyChord] = switch (source, isTerminal) {
        case (.lastInsertion, true) where ownsLine: [.shellLineEnd, .shellDeleteLine]
        case (.lastInsertion, true): Array(repeating: .deleteBackward, count: original.count)
        case (.lastInsertion, false): Array(repeating: .selectCharacterBackward, count: original.count)
        default: []
        }
        let expectedApp = context.bundleIdentifier
        return PreparedAction(
            done: risk.map { "Check carefully: \($0.reason)" }
                ?? (source == .lastInsertion ? "Rewrote your last dictation" : "Rewrote the selection"),
            failure: "Couldn't replace the text",
            insertion: LastInsertion(text: rewritten, bundleIdentifier: expectedApp, ownsLine: ownsLine)
        ) { [keystrokes, inserter, frontmostApp, settle] in
            guard frontmostApp() == expectedApp else { throw AgentError.appChanged }
            guard context.isUntouched() else { throw AgentError.interrupted }
            if !removal.isEmpty {
                keystrokes.send(removal)
                await settle(removal.count)
            }
            try await inserter.insert(rewritten)
        }
    }

    /// Lets a slow app work through the selection keys before ⌘V, so the paste's clipboard restore doesn't win the race.
    static func waitForKeys(_ count: Int) async {
        try? await Task.sleep(for: .milliseconds(min(2 * count, 2_000)))
    }

    private func sourceText(in context: ToolContext) async throws -> (Source, String) {
        guard frontmostApp() == context.bundleIdentifier else { throw AgentError.appChanged }
        if let last = context.lastInsertion, last.bundleIdentifier == context.bundleIdentifier, !last.text.isEmpty {
            return (.lastInsertion, last.text)
        }
        guard selection.isFocusedElementEditable() != false else { throw AgentError.readOnly }
        if case .text(let text) = selection.selectedText() {
            return (.selection, text)
        }
        if let copied = await copier.copySelection() {
            return (.clipboard, copied)
        }
        throw AgentError.noSelection
    }
}
