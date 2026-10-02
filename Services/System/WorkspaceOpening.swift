import AppKit

struct InstalledApp: Equatable {
    let name: String
    let url: URL
}

protocol AppListing {
    func installedApps() -> [InstalledApp]
}

protocol WorkspaceOpening {
    func open(_ url: URL) async throws
    func openApplication(at url: URL) async throws
}

struct InstalledAppDirectory: AppListing {
    func installedApps() -> [InstalledApp] {
        let fileManager = FileManager.default
        let directories = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities"]
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
            + [fileManager.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)]
        let finder = InstalledApp(name: "Finder", url: URL(filePath: "/System/Library/CoreServices/Finder.app"))
        return [finder] + directories.flatMap { directory in
            ((try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
                .map { InstalledApp(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
        }
    }
}

struct WorkspaceOpenError: Error {}

struct NSWorkspaceOpener: WorkspaceOpening {
    func open(_ url: URL) async throws {
        guard NSWorkspace.shared.open(url) else { throw WorkspaceOpenError() }
    }

    func openApplication(at url: URL) async throws {
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
