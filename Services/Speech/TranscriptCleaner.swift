import Foundation

enum TranscriptCleaner {
    static func clean(_ raw: String) -> String {
        let text = raw
            .replacing(#/\[[^\]]*\]|♪/#, with: "")
            .replacing(#/\s+/#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isAnnotation(text) ? "" : text
    }

    private static func isAnnotation(_ text: String) -> Bool {
        text.wholeMatch(of: #/\(.*\)|\*.*\*/#) != nil
    }
}
