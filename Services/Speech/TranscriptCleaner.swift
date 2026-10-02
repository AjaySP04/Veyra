import Foundation

enum TranscriptCleaner {
    static func clean(_ raw: String) -> String {
        let text = raw
            .replacing(#/\[[^\]]*\]|♪/#, with: "")
            .replacing(#/\s+/#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isAnnotation(text) || !hasWords(text) ? "" : text
    }

    /// Whisper sometimes hears a lone "-" or "." in a near-silent tap; nobody dictates punctuation on its own.
    private static func hasWords(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private static func isAnnotation(_ text: String) -> Bool {
        text.wholeMatch(of: #/\([^()]*\)|\*[^*]*\*/#) != nil
    }
}
