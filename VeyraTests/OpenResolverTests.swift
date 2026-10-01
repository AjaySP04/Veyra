import Foundation
import Testing
@testable import Veyra

@MainActor
struct OpenResolverTests {
    private let apps = ["Slack", "Visual Studio Code", "Google Chrome", "Safari", "Xcode", "Notes", "Spotify", "System Settings", "Messages", "Mail"]

    @Test(arguments: [
        ("Slack", "Slack"),
        ("slack", "Slack"),
        ("VS code", "Visual Studio Code"),
        ("V S code", "Visual Studio Code"),
        ("visual studio code", "Visual Studio Code"),
        ("chrome", "Google Chrome"),
        ("Slak", "Slack"),
        ("Spotfy", "Spotify"),
        ("system settings", "System Settings"),
    ])
    func matchesApp(query: String, expected: String) {
        #expect(AppResolver.match(query, in: apps) == expected)
    }

    @Test(arguments: ["Photoshop", "", "ma", "zz"])
    func noAppMatch(query: String) {
        #expect(AppResolver.match(query, in: apps) == nil)
    }

    @Test func tieGoesToShortestName() {
        #expect(AppResolver.match("mail", in: ["Mailspring", "Mail"]) == "Mail")
        #expect(AppResolver.match("code", in: ["Xcode", "Visual Studio Code"]) == "Xcode")
    }

    @Test(arguments: [
        ("github.com", "https://github.com"),
        ("github dot com", "https://github.com"),
        ("YouTube.com.", "https://youtube.com"),
        ("https://x.com/a", "https://x.com/a"),
        ("http://example.org", "http://example.org"),
        (" mail.google.com ", "https://mail.google.com"),
    ])
    func websiteURL(target: String, expected: String) {
        #expect(WebsiteResolver.url(for: target)?.absoluteString == expected)
    }

    @Test(arguments: ["file:///etc/hosts", "javascript:alert(1)", "not a site", "", "ftp://example.com", ".com"])
    func refusesWebsite(target: String) {
        #expect(WebsiteResolver.url(for: target) == nil)
    }

    @Test(arguments: [
        ("Downloads", StandardFolder.downloads),
        ("my downloads folder", .downloads),
        ("the Desktop", .desktop),
        ("Documents", .documents),
        ("home folder", .home),
        ("my Pictures", .pictures),
        ("Music", .music),
        ("movies", .movies),
    ])
    func standardFolder(target: String, expected: StandardFolder) {
        #expect(FolderResolver.folder(for: target) == expected)
    }

    @Test(arguments: ["Veyra project", "Downloads backup", ""])
    func nonStandardFolder(target: String) {
        #expect(FolderResolver.folder(for: target) == nil)
    }

    @Test func folderURLs() {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        #expect(StandardFolder.home.url(in: home) == home)
        #expect(StandardFolder.downloads.url(in: home).path() == "/Users/me/Downloads/")
        #expect(StandardFolder.home.name == "Home")
        #expect(StandardFolder.downloads.name == "Downloads")
    }

    @Test func searchWordsDropStopWords() {
        #expect(FileSearcher.words(in: "the PDF about tax returns") == ["pdf", "about", "tax", "returns"])
        #expect(FileSearcher.words(in: "my resume") == ["resume"])
        #expect(FileSearcher.words(in: "the file called notes") == ["notes"])
    }

    private func file(_ name: String, daysAgo: Double?) -> FileResult {
        FileResult(
            url: URL(filePath: "/Users/me/\(name)"),
            name: name,
            lastUsed: daysAgo.map { Date(timeIntervalSince1970: 1_000_000 - $0 * 86_400) }
        )
    }

    @Test func ranksByMatchedWordsThenRecency() {
        let old = file("Tax Return 2024.pdf", daysAgo: 300)
        let recent = file("Tax Notes.txt", daysAgo: 1)
        let both = file("Tax Returns Final.pdf", daysAgo: 30)
        #expect(FileSearcher.rank([recent, old, both], for: ["tax", "returns"]) == [both, recent, old])
    }

    @Test func missingDatesRankLastThenShorterName() {
        let undated = file("Resume.pdf", daysAgo: nil)
        let dated = file("Resume Final.pdf", daysAgo: 5)
        let undatedLong = file("Resume Old Copy.pdf", daysAgo: nil)
        #expect(FileSearcher.rank([undatedLong, undated, dated], for: ["resume"]) == [dated, undated, undatedLong])
    }

    @Test func requiresHalfTheWords() {
        let one = file("Invoice.pdf", daysAgo: 1)
        #expect(FileSearcher.rank([one], for: ["invoice", "september", "acme"]).isEmpty)
        #expect(FileSearcher.rank([one], for: ["invoice", "september"]) == [one])
    }

    @Test func matchingIgnoresCaseAndAccents() {
        let résumé = file("Résumé.pdf", daysAgo: 1)
        #expect(FileSearcher.rank([résumé], for: ["resume"]) == [résumé])
    }
}
