import Foundation

enum AppResolver {
    static func match(_ query: String, in names: [String]) -> String? {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return nil }
        let queryWords = mergedLetters(words(query))
        let tiers: [(String) -> Bool] = [
            { normalized($0) == normalizedQuery },
            { consumes(queryWords[...], words($0)[...]) },
            { normalizedQuery.count >= 3 && normalized($0).contains(normalizedQuery) },
            { isNearMiss(normalizedQuery, normalized($0)) },
        ]
        for tier in tiers {
            if let best = names.filter(tier).min(by: { ($0.count, $0) < ($1.count, $1) }) { return best }
        }
        return nil
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func mergedLetters(_ words: [String]) -> [String] {
        var merged: [String] = []
        var run = ""
        for word in words {
            if word.count == 1 {
                run += word
            } else {
                if !run.isEmpty { merged.append(run); run = "" }
                merged.append(word)
            }
        }
        if !run.isEmpty { merged.append(run) }
        return merged
    }

    private static func consumes(_ query: ArraySlice<String>, _ name: ArraySlice<String>) -> Bool {
        guard let word = query.first else { return name.isEmpty }
        if name.first == word, consumes(query.dropFirst(), name.dropFirst()) { return true }
        guard word.count >= 2, name.count >= word.count else { return false }
        let initials = String(name.prefix(word.count).compactMap(\.first))
        return initials == word && consumes(query.dropFirst(), name.dropFirst(word.count))
    }

    private static func isNearMiss(_ query: String, _ name: String) -> Bool {
        let limit = query.count >= 5 ? 2 : query.count == 4 ? 1 : 0
        return limit > 0 && distance(query, name) <= limit
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
