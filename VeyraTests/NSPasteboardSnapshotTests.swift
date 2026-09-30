import AppKit
import Testing
@testable import Veyra

@MainActor
struct NSPasteboardSnapshotTests {
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("VeyraTests.\(UUID().uuidString)"))

    @Test func restoresMultipleItemsWithEveryType() {
        let original = PasteboardSnapshot(items: [
            ["public.png": Data([1, 2, 3]), "public.tiff": Data([4])],
            ["public.utf8-plain-text": Data("second".utf8)],
        ])
        pasteboard.restore(original)
        pasteboard.write("dictated")
        pasteboard.restore(original)
        #expect(pasteboard.snapshot() == original)
    }

    @Test func restoresEmptyPasteboard() {
        pasteboard.write("dictated")
        pasteboard.restore(PasteboardSnapshot(items: []))
        #expect(pasteboard.snapshot().items.isEmpty)
    }

    @Test func writeReplacesContentsWithText() {
        pasteboard.restore(PasteboardSnapshot(items: [["public.png": Data([1])]]))
        pasteboard.write("dictated")
        #expect(pasteboard.string(forType: .string) == "dictated")
        #expect(pasteboard.data(forType: .png) == nil)
    }
}
