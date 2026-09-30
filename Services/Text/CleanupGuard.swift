import Foundation

enum CleanupGuard {
    private static let fillers: Set = ["um", "uh", "er", "ah", "hmm", "like", "basically", "so", "actually", "you", "know"]
    private static let sequencing: Set = ["first", "second", "third", "fourth", "fifth", "then", "next", "finally", "lastly", "and", "also"]

    static func accepts(original: String, cleaned: String) -> Bool {
        let originalWords = words(in: original)
        let cleanedWords = words(in: cleaned)
        guard !cleanedWords.isEmpty else { return false }

        let spoken = Set(originalWords)
        let added = cleanedWords.count(where: { !spoken.contains($0) })
        let kept = Set(cleanedWords)
        let meaningful = originalWords.filter { !fillers.contains($0) && !sequencing.contains($0) }
        let retained = meaningful.count(where: { kept.contains($0) })

        return added <= max(2, cleanedWords.count / 5) && retained * 5 >= meaningful.count * 4
    }

    static func words(in text: String) -> [String] {
        text.lowercased()
            .replacing("’", with: "'")
            .matches(of: #/[\w']+/#)
            .map { $0.output == "okay" ? "ok" : String($0.output) }
    }
}
