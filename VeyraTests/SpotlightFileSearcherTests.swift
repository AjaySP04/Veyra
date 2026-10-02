import Foundation
import Testing
@testable import Veyra

@MainActor
@Suite(.serialized)
struct SpotlightFileSearcherTests {
    @Test(.timeLimit(.minutes(1)), arguments: [
        (["vision"], false),
        (["vision"], true),
        (["vision", "readme"], false),
        (["vision", "readme"], true),
    ])
    func searchCompletes(words: [String], foldersOnly: Bool) async {
        let results = await SpotlightFileSearcher().search(words, foldersOnly: foldersOnly)
        #expect(results.allSatisfy { !$0.url.path().contains("/.") })
    }

    @Test func predicateNeverWrapsASingleCondition() {
        #expect(!(SpotlightFileSearcher.predicate(for: ["vision"], foldersOnly: false) is NSCompoundPredicate))
        let folders = SpotlightFileSearcher.predicate(for: ["vision"], foldersOnly: true) as? NSCompoundPredicate
        #expect(folders?.compoundPredicateType == .and)
        #expect(folders?.subpredicates.count == 2)
        let words = SpotlightFileSearcher.predicate(for: ["tax", "return"], foldersOnly: false) as? NSCompoundPredicate
        #expect(words?.compoundPredicateType == .or)
        #expect(words?.subpredicates.count == 2)
    }
}
