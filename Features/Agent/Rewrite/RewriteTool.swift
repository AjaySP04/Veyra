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
        let rewritten = context.mode.finalize(try await rewriter.rewrite(original, instruction: instruction))
        guard !rewritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentError.rewriteFailed }
        Logger.agent.info("Rewrite source \(source.rawValue, privacy: .public) \(original.count) → \(rewritten.count) characters")

        let replacedCount = source == .lastInsertion ? original.count : 0
        let removal: KeyChord = context.mode == .terminal ? .deleteBackward : .selectCharacterBackward
        let expectedApp = context.bundleIdentifier
        return PreparedAction(
            done: source == .lastInsertion ? "Rewrote your last dictation" : "Rewrote the selection",
            failure: "Couldn't replace the text",
            insertion: LastInsertion(text: rewritten, bundleIdentifier: expectedApp)
        ) { [keystrokes, inserter, frontmostApp, settle] in
            guard frontmostApp() == expectedApp else { throw AgentError.appChanged }
            guard context.isUntouched() else { throw AgentError.interrupted }
            if replacedCount > 0 {
                keystrokes.send(Array(repeating: removal, count: replacedCount))
                await settle(replacedCount)
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
