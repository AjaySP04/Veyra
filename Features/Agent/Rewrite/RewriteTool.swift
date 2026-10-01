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

    init(
        selection: SelectionReading, copier: SelectionCopying, rewriter: TextRewriting,
        inserter: TextInserting, keystrokes: KeystrokeSending, frontmostApp: @escaping () -> String?
    ) {
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
        Logger.agent.info("Rewrite source \(source.rawValue, privacy: .public) \(original.count) → \(rewritten.count) characters")

        let replacedCount = source == .lastInsertion ? original.count : 0
        let removal: KeyChord = context.mode == .terminal ? .deleteBackward : .selectCharacterBackward
        let expectedApp = context.bundleIdentifier
        return PreparedAction(
            done: source == .lastInsertion ? "Rewrote your last dictation" : "Rewrote the selection",
            failure: "Couldn't replace the text",
            insertion: LastInsertion(text: rewritten, bundleIdentifier: expectedApp)
        ) { [keystrokes, inserter, frontmostApp] in
            guard frontmostApp() == expectedApp else { throw AgentError.appChanged }
            if replacedCount > 0 { keystrokes.send(Array(repeating: removal, count: replacedCount)) }
            try await inserter.insert(rewritten)
        }
    }

    private func sourceText(in context: ToolContext) async throws -> (Source, String) {
        if let last = context.lastInsertion, last.bundleIdentifier == context.bundleIdentifier, !last.text.isEmpty {
            return (.lastInsertion, last.text)
        }
        if case .text(let text) = selection.selectedText() {
            return (.selection, text)
        }
        if let copied = await copier.copySelection() {
            return (.clipboard, copied)
        }
        throw AgentError.noSelection
    }
}
