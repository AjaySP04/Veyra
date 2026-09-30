import Foundation
import Testing
@testable import Veyra

@MainActor
struct ModelFolderCacheTests {
    private let defaults = UserDefaults(suiteName: "ModelFolderCacheTests.\(UUID().uuidString)")!
    private var cache: ModelFolderCache { ModelFolderCache(defaults: defaults, key: "folder") }

    @Test func returnsStoredExistingFolder() {
        let folder = FileManager.default.temporaryDirectory
        cache.store(folder)
        #expect(cache.folder?.standardizedFileURL == folder.standardizedFileURL)
    }

    @Test func ignoresFolderThatNoLongerExists() {
        cache.store(URL(filePath: "/nonexistent/\(UUID().uuidString)"))
        #expect(cache.folder == nil)
    }

    @Test func clearForgetsFolder() {
        cache.store(FileManager.default.temporaryDirectory)
        cache.clear()
        #expect(cache.folder == nil)
    }
}
