import AppKit

struct PasteboardSnapshot: Equatable {
    var items: [[String: Data]]
}

protocol Pasteboard: AnyObject {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    func restore(_ snapshot: PasteboardSnapshot)
    func write(_ text: String)
    func readText() -> String?
}

extension NSPasteboard: Pasteboard {
    private static let transientType = PasteboardType("org.nspasteboard.TransientType")

    func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: (pasteboardItems ?? []).map { item in
            item.types.reduce(into: [:]) { contents, type in
                contents[type.rawValue] = item.data(forType: type)
            }
        })
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        clearContents()
        writeObjects(snapshot.items.map { contents in
            let item = NSPasteboardItem()
            contents.forEach { type, data in item.setData(data, forType: PasteboardType(type)) }
            return item
        })
    }

    func readText() -> String? {
        string(forType: .string)
    }

    func write(_ text: String) {
        clearContents()
        setString(text, forType: .string)
        setData(Data(), forType: Self.transientType)
    }
}
