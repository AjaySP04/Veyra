import Carbon.HIToolbox
import CoreGraphics

struct KeyChord: Equatable {
    let key: CGKeyCode
    let flags: CGEventFlags

    init(_ key: Int, _ flags: CGEventFlags = []) {
        self.key = CGKeyCode(key)
        self.flags = flags
    }

    static let paste = KeyChord(kVK_ANSI_V, .maskCommand)
    static let undo = KeyChord(kVK_ANSI_Z, .maskCommand)
    static let redo = KeyChord(kVK_ANSI_Z, [.maskCommand, .maskShift])
    static let deleteBackward = KeyChord(kVK_Delete)
    static let deleteWord = KeyChord(kVK_Delete, .maskAlternate)
    static let deleteLine = KeyChord(kVK_Delete, .maskCommand)
    static let shellDeleteWord = KeyChord(kVK_ANSI_W, .maskControl)
    static let shellDeleteLine = KeyChord(kVK_ANSI_U, .maskControl)
    static let bold = KeyChord(kVK_ANSI_B, .maskCommand)
    static let italic = KeyChord(kVK_ANSI_I, .maskCommand)
    static let underline = KeyChord(kVK_ANSI_U, .maskCommand)
    static let selectAll = KeyChord(kVK_ANSI_A, .maskCommand)
    static let selectWordBackward = KeyChord(kVK_LeftArrow, [.maskAlternate, .maskShift])
    static let lineStart = KeyChord(kVK_LeftArrow, .maskCommand)
    static let lineEnd = KeyChord(kVK_RightArrow, .maskCommand)
    static let shellLineStart = KeyChord(kVK_ANSI_A, .maskControl)
    static let shellLineEnd = KeyChord(kVK_ANSI_E, .maskControl)
    static let documentStart = KeyChord(kVK_UpArrow, .maskCommand)
    static let documentEnd = KeyChord(kVK_DownArrow, .maskCommand)
    static let returnKey = KeyChord(kVK_Return)
    static let softReturn = KeyChord(kVK_Return, .maskShift)
}
