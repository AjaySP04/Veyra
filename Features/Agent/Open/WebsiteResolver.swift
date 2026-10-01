import Foundation

enum WebsiteResolver {
    static func url(for target: String) -> URL? {
        var text = target.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(" dot ", with: ".")
            .replacing(#/\s+/#, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme),
              let host = url.host(), host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else {
            return nil
        }
        return url
    }
}
