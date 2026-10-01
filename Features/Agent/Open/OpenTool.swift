import Foundation

struct OpenTool: Tool {
    private enum Kind: String, CaseIterable {
        case app, website, folder, file
    }

    let definition = ToolDefinition(
        name: "open",
        description: "Open an installed app, a website, a standard user folder, or a file/folder found by name.",
        parameters: [
            ToolParameter(
                name: "kind",
                description: "app = installed application; website = a domain or well-known site; folder = Desktop/Documents/Downloads/Home/Pictures/Music/Movies; file = any other file or folder searched by name",
                allowed: Kind.allCases.map(\.rawValue)
            ),
            ToolParameter(
                name: "target",
                description: "App name, domain (e.g. github.com), folder name, or file search words, cleaned of filler",
                allowed: nil
            ),
        ]
    )
    let risk = ToolRisk.immediate

    private let apps: AppListing
    private let files: FileSearching
    private let workspace: WorkspaceOpening
    private let home: URL

    init(apps: AppListing, files: FileSearching, workspace: WorkspaceOpening, home: URL) {
        self.apps = apps
        self.files = files
        self.workspace = workspace
        self.home = home
    }

    func prepare(_ arguments: [String: String]) async throws -> PreparedAction {
        guard let kind = arguments["kind"].flatMap(Kind.init(rawValue:)),
              let target = arguments["target"]?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
            throw AgentError.invalidArguments
        }
        switch kind {
        case .app:
            let installed = apps.installedApps()
            guard let name = AppResolver.match(target, in: installed.map(\.name)),
                  let app = installed.first(where: { $0.name == name }) else {
                throw AgentError.noApp(target)
            }
            return action(app.name) { [workspace] in try await workspace.openApplication(at: app.url) }
        case .website:
            guard let url = WebsiteResolver.url(for: target), let host = url.host() else { throw AgentError.badAddress }
            return action(host) { [workspace] in try await workspace.open(url) }
        case .folder:
            if let folder = FolderResolver.folder(for: target) {
                let url = folder.url(in: home)
                return action(folder.name) { [workspace] in try await workspace.open(url) }
            }
            return try await search(target, foldersOnly: true)
        case .file:
            return try await search(target, foldersOnly: false)
        }
    }

    private func search(_ target: String, foldersOnly: Bool) async throws -> PreparedAction {
        let words = FileSearcher.words(in: target)
        let ranked = words.isEmpty ? [] : FileSearcher.rank(await files.search(words, foldersOnly: foldersOnly), for: words)
        guard let best = ranked.first else { throw AgentError.noFile(target) }
        let others = ranked.count - 1
        let suffix = others == 0 ? "" : " · \(others) other match\(others == 1 ? "" : "es")"
        return action(best.name, suffix: suffix) { [workspace] in try await workspace.open(best.url) }
    }

    private func action(_ name: String, suffix: String = "", perform: @escaping () async throws -> Void) -> PreparedAction {
        PreparedAction(done: "Opened \(name)\(suffix)", failure: "Couldn't open \(name)", perform: perform)
    }
}
