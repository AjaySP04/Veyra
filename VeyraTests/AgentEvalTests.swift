import Foundation
import Testing
@testable import Veyra

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["VEYRA_EVAL"] != nil))
struct AgentEvalTests {
    enum Expect {
        case app(String)
        case website(Set<String>)
        case folder(StandardFolder)
        case file(String)
        case rewrite(String)
        case unsupported
    }

    private static let apps = ["Slack", "Visual Studio Code", "Google Chrome", "Safari", "Xcode", "Notes", "Spotify", "System Settings", "Ghostty", "Finder"]

    private static let cases: [(String, Expect)] = [
        ("Open Slack.", .app("Slack")),
        ("open visual studio code", .app("Visual Studio Code")),
        ("Open V S code.", .app("Visual Studio Code")),
        ("Um, can you open Spotify?", .app("Spotify")),
        ("open google chrome", .app("Google Chrome")),
        ("Open Safari please.", .app("Safari")),
        ("launch xcode", .app("Xcode")),
        ("open system settings", .app("System Settings")),
        ("Open notes.", .app("Notes")),
        ("open github dot com", .website(["github.com"])),
        ("Open YouTube.", .website(["youtube.com", "www.youtube.com"])),
        ("Open Gmail.", .website(["gmail.com", "mail.google.com"])),
        ("open wikipedia", .website(["wikipedia.org", "www.wikipedia.org", "en.wikipedia.org", "wikipedia.com"])),
        ("go to apple dot com", .website(["apple.com", "www.apple.com"])),
        ("open my downloads folder", .folder(.downloads)),
        ("Open the desktop.", .folder(.desktop)),
        ("show me my documents", .folder(.documents)),
        ("open my home folder", .folder(.home)),
        ("open pictures", .folder(.pictures)),
        ("Open my resume.", .file("resume")),
        ("open the Veyra project folder", .file("veyra")),
        ("open the pdf about tax returns from last year", .file("tax")),
        ("open the invoice for september", .file("invoice")),
        ("What's the weather tomorrow?", .unsupported),
        ("send a message to John", .unsupported),
        ("tell me a joke", .unsupported),
        ("make this more formal", .rewrite("formal")),
        ("translate this to Hindi", .rewrite("hindi")),
        ("summarize this", .rewrite("summar")),
        ("fix the grammar", .rewrite("grammar")),
        ("make it shorter", .rewrite("short")),
        ("Make that sound friendlier.", .rewrite("friendl")),
    ]

    private let runner = AgentRunner(
        caller: OllamaClient(),
        registry: ToolRegistry([
            OpenTool(apps: FakeAppListing(), files: FakeFileSearching(), workspace: FakeWorkspace(), home: URL(filePath: "/")),
            RewriteTool(
                selection: FakeSelectionReader(), copier: FakeCopier(), rewriter: FakeRewriter(),
                inserter: FakeInserter(), keystrokes: FakeKeystrokes(), frontmostApp: { nil }
            ),
        ])
    )

    @Test(arguments: ["gemma4:latest", "gemma4:cloud"])
    func accuracy(modelName: String) async throws {
        let model = CleanupModel(name: modelName, baseTimeout: .seconds(60), timeoutPerWord: .zero)
        var failures: [String] = []
        for (transcript, expect) in Self.cases {
            let reply = try? await OllamaClient().callTool(runner.request(for: transcript, model: model))
            if !Self.passes(reply, expect) { failures.append("\(transcript) → \(String(describing: reply))") }
        }
        let passed = Self.cases.count - failures.count
        let report = "[eval] \(model.name): \(passed)/\(Self.cases.count)\n" + failures.map { "  ✗ \($0)\n" }.joined()
        print(report)
        Self.append(report)
        #expect(passed * 10 >= Self.cases.count * 9, "\(model.name) scored \(passed)/\(Self.cases.count)")
    }

    @Test(arguments: ["gemma4:latest", "gemma4:cloud"])
    func rewriteQuality(modelName: String) async throws {
        let rewriter = OllamaTextRewriter(client: OllamaClient(), models: [CleanupModel(name: modelName, baseTimeout: .seconds(60), timeoutPerWord: .zero)])
        let long = "So basically what happened was that the build failed on Tuesday because somebody pushed a change to the config file without running the tests first, and then we spent most of the afternoon trying to figure out which commit broke it before we finally found it."
        let checks: [(String, String, (String) -> Bool)] = [
            ("hey can u send me the report by tmrw", "more formal", { !$0.isEmpty && !$0.contains("<") && $0.lowercased() != "hey can u send me the report by tmrw" }),
            ("I will be late to the meeting today", "translate to Hindi", { $0.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) } }),
            (long, "shorter", { $0.count < long.count }),
            ("their going to the store tomorow", "fix grammar", { $0.lowercased().contains("tomorrow") }),
        ]
        var failures: [String] = []
        for (text, instruction, isGood) in checks {
            let result = (try? await rewriter.rewrite(text, instruction: instruction)) ?? ""
            if !isGood(result) { failures.append("\(instruction): \(result)") }
        }
        let report = "[eval] rewrite \(modelName): \(checks.count - failures.count)/\(checks.count)\n" + failures.map { "  ✗ \($0)\n" }.joined()
        print(report)
        Self.append(report)
        #expect(checks.count - failures.count >= 3, "\(modelName) rewrite quality \(checks.count - failures.count)/\(checks.count)")
    }

    private static func append(_ report: String) {
        guard let path = ProcessInfo.processInfo.environment["VEYRA_EVAL_REPORT"],
              let handle = FileHandle(forWritingAtPath: path) ?? (FileManager.default.createFile(atPath: path, contents: nil) ? FileHandle(forWritingAtPath: path) : nil) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(report.utf8))
        try? handle.close()
    }

    private static func passes(_ reply: ToolReply?, _ expect: Expect) -> Bool {
        switch (reply, expect) {
        case (.text?, .unsupported):
            return true
        case (.call(let call)?, .rewrite(let fragment)):
            return call.name == "rewrite" && call.arguments["instruction"]?.lowercased().contains(fragment) == true
        case (.call(let call)?, _):
            guard call.name == "open", let kind = call.arguments["kind"], let target = call.arguments["target"] else { return false }
            switch expect {
            case .app(let name): return kind == "app" && AppResolver.match(target, in: apps) == name
            case .website(let hosts): return kind == "website" && WebsiteResolver.url(for: target)?.host().map(hosts.contains) == true
            case .folder(let folder): return kind == "folder" && FolderResolver.folder(for: target) == folder
            case .file(let word): return ["file", "folder"].contains(kind) && FileSearcher.words(in: target).contains(word)
            case .rewrite, .unsupported: return false
            }
        default:
            return false
        }
    }
}
