import Foundation

struct ModelFolderCache {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    var folder: URL? {
        guard let path = defaults.string(forKey: key), FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    func store(_ folder: URL) {
        defaults.set(folder.path, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
