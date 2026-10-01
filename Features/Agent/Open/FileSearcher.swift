import Foundation

struct FileResult: Equatable {
    let url: URL
    let name: String
    let lastUsed: Date?
}

enum FileSearcher {
    private static let stopWords: Set = ["the", "my", "a", "an", "file", "folder", "document", "called", "named"]

    static func words(in target: String) -> [String] {
        target.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !stopWords.contains($0) }
    }

    static func rank(_ results: [FileResult], for words: [String]) -> [FileResult] {
        let minimum = max(1, (words.count + 1) / 2)
        return results
            .map { ($0, matchCount(of: words, in: $0.name)) }
            .filter { $0.1 >= minimum }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                switch (a.0.lastUsed, b.0.lastUsed) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.0.name.count < b.0.name.count
                }
            }
            .map(\.0)
    }

    private static func matchCount(of words: [String], in name: String) -> Int {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return words.count { folded.contains($0) }
    }
}
