import Carbon.HIToolbox
import CoreGraphics

enum Key: Equatable {
    case code(CGKeyCode)
    case character(Character)
}

struct KeyChord: Equatable {
    let key: Key
    let flags: CGEventFlags

    init(_ code: Int, _ flags: CGEventFlags = []) {
        key = .code(CGKeyCode(code))
        self.flags = flags
    }

    init(_ character: Character, _ flags: CGEventFlags = []) {
        key = .character(character)
        self.flags = flags
    }

    static let paste = KeyChord("v", .maskCommand)
    static let undo = KeyChord("z", .maskCommand)
    static let redo = KeyChord("z", [.maskCommand, .maskShift])
    static let deleteBackward = KeyChord(kVK_Delete)
    static let deleteWord = KeyChord(kVK_Delete, .maskAlternate)
    static let deleteLine = KeyChord(kVK_Delete, .maskCommand)
    static let shellDeleteWord = KeyChord("w", .maskControl)
    static let shellDeleteLine = KeyChord("u", .maskControl)
    static let bold = KeyChord("b", .maskCommand)
    static let italic = KeyChord("i", .maskCommand)
    static let underline = KeyChord("u", .maskCommand)
    static let selectAll = KeyChord("a", .maskCommand)
    static let selectWordBackward = KeyChord(kVK_LeftArrow, [.maskAlternate, .maskShift])
    static let lineStart = KeyChord(kVK_LeftArrow, .maskCommand)
    static let lineEnd = KeyChord(kVK_RightArrow, .maskCommand)
    static let shellLineStart = KeyChord("a", .maskControl)
    static let shellLineEnd = KeyChord("e", .maskControl)
    static let documentStart = KeyChord(kVK_UpArrow, .maskCommand)
    static let documentEnd = KeyChord(kVK_DownArrow, .maskCommand)
    static let returnKey = KeyChord(kVK_Return)
    static let softReturn = KeyChord(kVK_Return, .maskShift)
}
