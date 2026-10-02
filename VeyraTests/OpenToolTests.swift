import Foundation
import Testing
@testable import Veyra

@MainActor
struct OpenToolTests {
    private let slack = InstalledApp(name: "Slack", url: URL(filePath: "/Applications/Slack.app"))
    private let files = FakeFileSearching()
    private let workspace = FakeWorkspace()
    private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)

    private var tool: OpenTool {
        OpenTool(apps: FakeAppListing(apps: [slack]), files: files, workspace: workspace, home: home)
    }

    private func result(_ name: String, daysAgo: Double) -> FileResult {
        FileResult(url: URL(filePath: "/Users/me/\(name)"), name: name, lastUsed: Date(timeIntervalSince1970: 1_000_000 - daysAgo * 86_400))
    }

    @Test func definitionMatchesTheSpec() {
        #expect(tool.definition.name == "open")
        #expect(tool.definition.parameters.map(\.name) == ["kind", "target"])
        #expect(tool.definition.parameters[0].allowed == ["app", "website", "folder", "file"])
        #expect(tool.risk == .immediate)
    }

    @Test func opensAppOnlyOnPerform() async throws {
        let action = try await tool.prepare(["kind": "app", "target": "slak"])
        #expect(workspace.launched.isEmpty)
        #expect(action.done == "Opened Slack")
        #expect(action.failure == "Couldn't open Slack")
        try await action.perform()
        #expect(workspace.launched == [slack.url])
    }

    @Test func unknownAppIsNotFound() async {
        await #expect(throws: AgentError.noApp("Photoshop")) { try await tool.prepare(["kind": "app", "target": "Photoshop"]) }
    }

    @Test func opensWebsite() async throws {
        let action = try await tool.prepare(["kind": "website", "target": "github dot com"])
        #expect(action.done == "Opened github.com")
        try await action.perform()
        #expect(workspace.opened == [URL(string: "https://github.com")!])
    }

    @Test func refusesBadAddress() async {
        await #expect(throws: AgentError.badAddress) { try await tool.prepare(["kind": "website", "target": "file:///etc/hosts"]) }
    }

    @Test func opensStandardFolderWithoutSearching() async throws {
        let action = try await tool.prepare(["kind": "folder", "target": "my downloads"])
        #expect(action.done == "Opened Downloads")
        try await action.perform()
        #expect(workspace.opened == [StandardFolder.downloads.url(in: home)])
        #expect(files.searches.isEmpty)
    }

    @Test func nonStandardFolderSearchesFoldersOnly() async throws {
        files.results = [result("Veyra", daysAgo: 1)]
        let action = try await tool.prepare(["kind": "folder", "target": "Veyra project"])
        #expect(files.searches.map(\.foldersOnly) == [true])
        #expect(files.searches.map(\.words) == [["veyra", "project"]])
        #expect(action.done == "Opened Veyra")
    }

    @Test func opensBestFileAndCountsOthers() async throws {
        files.results = [result("Resume Old.pdf", daysAgo: 200), result("Resume.pdf", daysAgo: 2), result("Resume Draft.pdf", daysAgo: 90)]
        let action = try await tool.prepare(["kind": "file", "target": "my resume"])
        #expect(files.searches.map(\.foldersOnly) == [false])
        #expect(action.done == "Opened Resume.pdf · 2 other matches")
        try await action.perform()
        #expect(workspace.opened == [URL(filePath: "/Users/me/Resume.pdf")])
    }

    @Test func oneOtherMatchIsSingular() async throws {
        files.results = [result("Resume.pdf", daysAgo: 2), result("Resume Draft.pdf", daysAgo: 90)]
        let action = try await tool.prepare(["kind": "file", "target": "resume"])
        #expect(action.done == "Opened Resume.pdf · 1 other match")
    }

    @Test func noFileIsNotFound() async {
        await #expect(throws: AgentError.noFile("resume")) { try await tool.prepare(["kind": "file", "target": "resume"]) }
    }

    @Test(arguments: [
        ["target": "Slack"],
        ["kind": "app"],
        ["kind": "app", "target": "  "],
        ["kind": "program", "target": "Slack"],
    ])
    func invalidArguments(arguments: [String: String]) async {
        await #expect(throws: AgentError.invalidArguments) { try await tool.prepare(arguments) }
    }

    @Test func performFailurePropagates() async throws {
        workspace.error = TestError()
        let action = try await tool.prepare(["kind": "app", "target": "Slack"])
        await #expect(throws: TestError.self) { try await action.perform() }
    }
}
