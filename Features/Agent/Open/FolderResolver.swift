import Foundation

enum StandardFolder: String, CaseIterable {
    case desktop, documents, downloads, home, pictures, music, movies

    var name: String { rawValue.capitalized }

    func url(in home: URL) -> URL {
        self == .home ? home : home.appending(path: name, directoryHint: .isDirectory)
    }
}

enum FolderResolver {
    private static let ignored: Set = ["my", "the", "folder"]

    static func folder(for target: String) -> StandardFolder? {
        let words = target.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { !ignored.contains($0) }
        return StandardFolder(rawValue: words.joined(separator: " "))
    }
}
