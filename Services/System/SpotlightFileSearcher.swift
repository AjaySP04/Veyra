import Foundation

protocol FileSearching {
    func search(_ words: [String], foldersOnly: Bool) async -> [FileResult]
}

final class SpotlightFileSearcher: FileSearching {
    private static let timeout: Duration = .seconds(2)

    /// NSMetadataQuery throws if an AND or OR group holds a single condition, so one condition stays bare.
    static func predicate(for words: [String], foldersOnly: Bool) -> NSPredicate {
        let names = words.map { NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, $0) }
        let name = names.count == 1 ? names[0] : NSCompoundPredicate(orPredicateWithSubpredicates: names)
        guard foldersOnly else { return name }
        let folder = NSPredicate(format: "%K == %@", NSMetadataItemContentTypeKey, "public.folder")
        return NSCompoundPredicate(andPredicateWithSubpredicates: [name, folder])
    }

    func search(_ words: [String], foldersOnly: Bool) async -> [FileResult] {
        guard !words.isEmpty else { return [] }
        let query = NSMetadataQuery()
        query.predicate = Self.predicate(for: words, foldersOnly: foldersOnly)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library", directoryHint: .isDirectory).path()

        return await withCheckedContinuation { continuation in
            var isFinished = false
            var observer: NSObjectProtocol?
            let finish = {
                guard !isFinished else { return }
                isFinished = true
                query.stop()
                observer.map(NotificationCenter.default.removeObserver)
                let items = query.results as? [NSMetadataItem] ?? []
                let results = items.compactMap { item -> FileResult? in
                    guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                          !path.hasPrefix(library), !path.contains("/.") else { return nil }
                    let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String ?? URL(filePath: path).lastPathComponent
                    return FileResult(url: URL(filePath: path), name: name, lastUsed: item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date)
                }
                continuation.resume(returning: results)
            }
            observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { _ in
                MainActor.assumeIsolated { finish() }
            }
            guard query.start() else { return finish() }
            Task {
                try? await Task.sleep(for: Self.timeout)
                finish()
            }
        }
    }
}
