import Foundation

enum CleanupGuard {
    static func accepts(original: String, cleaned: String) -> Bool {
        let originalWords = words(in: original)
        let cleanedWords = words(in: cleaned)
        guard !cleanedWords.isEmpty else { return false }

        let spoken = Set(originalWords)
        let added = cleanedWords.count(where: { !spoken.contains($0) })
        let kept = Set(cleanedWords)
        let retained = originalWords.count(where: { kept.contains($0) })

        return added <= max(2, cleanedWords.count / 5) && retained * 2 >= originalWords.count
    }

    static func words(in text: String) -> [String] {
        text.lowercased()
            .replacing("’", with: "'")
            .matches(of: #/[\w']+/#)
            .map { String($0.output) }
    }
}
