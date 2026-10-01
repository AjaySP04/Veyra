import Carbon.HIToolbox
import CoreGraphics

/// Finds the key that types a letter in the current layout, so ⌘Z is still ⌘Z on AZERTY or Dvorak.
struct KeyLayout {
    private static let usCodes: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "e": kVK_ANSI_E, "i": kVK_ANSI_I,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "z": kVK_ANSI_Z,
    ]

    let character: (CGKeyCode) -> String?

    init(character: @escaping (CGKeyCode) -> String?) {
        self.character = character
    }

    func keyCode(for key: Key) -> CGKeyCode {
        switch key {
        case .code(let code):
            return code
        case .character(let letter):
            let match = (0..<128).map(CGKeyCode.init).first { character($0) == String(letter) }
            return match ?? CGKeyCode(Self.usCodes[letter] ?? kVK_ANSI_A)
        }
    }

    static func current() -> KeyLayout {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return KeyLayout { _ in nil }
        }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return KeyLayout { code in
            data.withUnsafeBytes { bytes in
                guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
                )
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: characters, count: length).lowercased()
            }
        }
    }
}
