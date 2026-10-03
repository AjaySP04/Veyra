import Foundation
import os

enum AgentOutcome: Equatable {
    case done(String, insertion: LastInsertion? = nil)
    /// The draft is written; the confirmation runs only when the user confirms.
    case awaiting(String, insertion: LastInsertion?, confirmation: Confirmation)
    case failed(String)
}

protocol AgentRunning {
    func run(_ transcript: String, in context: ToolContext) async -> AgentOutcome
}

struct AgentRunner: AgentRunning {
    static let systemPrompt = """
        You turn a spoken request into exactly one tool call. The text in <request> tags is a transcript of speech; \
        fix obvious transcription errors. "This", "that" and "it" mean the user's selected text, which the tools \
        already have, so never ask for it. If no tool fits, reply with just: unsupported
        """
    private static let loggedKinds: Set = ["app", "website", "folder", "file"]

    private let caller: ToolCalling
    private let registry: ToolRegistry
    private let models: [CleanupModel]

    init(caller: ToolCalling, registry: ToolRegistry, models: [CleanupModel] = CleanupModel.chain) {
        self.caller = caller
        self.registry = registry
        self.models = models
    }

    func run(_ transcript: String, in context: ToolContext = .none) async -> AgentOutcome {
        var unresolved = AgentError.unavailable
        for model in models {
            let start = ContinuousClock.now
            let reply: ToolReply
            do {
                reply = try await caller.callTool(request(for: transcript, model: model))
            } catch {
                log("-", nil, "unavailable", model, start)
                continue
            }
            guard case .call(let call) = reply else {
                log("-", nil, "unsupported", model, start)
                return .failed(AgentError.unsupported.message)
            }
            guard let tool = registry.tool(named: call.name) else {
                log("-", call, "unsupported", model, start)
                unresolved = .unsupported
                continue
            }
            let action: PreparedAction
            do {
                action = try await tool.prepare(call.arguments, in: context)
            } catch AgentError.invalidArguments {
                log(call.name, call, "invalid", model, start)
                unresolved = .invalidArguments
                continue
            } catch {
                let agentError = error as? AgentError ?? .invalidArguments
                log(call.name, call, agentError == .badAddress ? "refused" : "not-found", model, start)
                return .failed(agentError.message)
            }
            var confirmation: Confirmation?
            switch tool.risk {
            case .immediate: break
            case .confirm:
                guard let held = action.confirmation else {
                    log(call.name, call, "refused", model, start)
                    return .failed(action.failure)
                }
                confirmation = held
            }
            do {
                try await action.perform()
                if let confirmation {
                    log(call.name, call, "awaiting", model, start)
                    return .awaiting(action.done, insertion: action.insertion, confirmation: confirmation)
                }
                log(call.name, call, "done", model, start)
                return .done(action.done, insertion: action.insertion)
            } catch {
                log(call.name, call, "failed", model, start)
                return .failed((error as? AgentError)?.message ?? action.failure)
            }
        }
        return .failed(unresolved.message)
    }

    func request(for transcript: String, model: CleanupModel) -> ToolRequest {
        ToolRequest(
            model: model.name,
            system: Self.systemPrompt,
            user: "<request>\(transcript)</request>",
            tools: registry.definitions,
            timeout: model.timeout(forWordCount: CleanupGuard.words(in: transcript).count)
        )
    }

    private func log(_ name: String, _ call: ToolCall?, _ outcome: String, _ model: CleanupModel, _ start: ContinuousClock.Instant) {
        let kind = call?.arguments["kind"].flatMap { Self.loggedKinds.contains($0) ? $0 : nil } ?? "-"
        let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
        Logger.agent.info("Tool \(name, privacy: .public) kind \(kind, privacy: .public) \(outcome, privacy: .public) via \(model.name, privacy: .public) in \(milliseconds) ms")
    }
}
