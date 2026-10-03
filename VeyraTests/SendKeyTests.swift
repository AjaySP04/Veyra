import Carbon.HIToolbox
import Testing
@testable import Veyra

struct SendKeyTests {
    @Test(arguments: [
        (DictationMode.chat, "com.tinyspeck.slackmacgap", KeyChord.returnKey),
        (.chat, "com.apple.MobileSMS", .returnKey),
        (.chat, "com.google.Chrome", .returnKey),
        (.email, "com.apple.mail", .sendMail),
        (.email, "com.microsoft.Outlook", .commandReturn),
        (.email, "com.readdle.SparkDesktop", .commandReturn),
        (.email, "com.google.Chrome", .commandReturn),
    ])
    func picksTheAppsSendKey(mode: DictationMode, app: String, key: KeyChord) {
        #expect(SendKey.for(mode: mode, bundleIdentifier: app) == key)
    }

    @Test(arguments: [DictationMode.standard, .editor, .terminal])
    func nothingSendsOutsideChatAndEmail(mode: DictationMode) {
        #expect(SendKey.for(mode: mode, bundleIdentifier: "com.apple.mail") == nil)
    }

    @Test func mailSendsWithCommandShiftD() {
        #expect(KeyChord.sendMail == KeyChord("d", [.maskCommand, .maskShift]))
        #expect(KeyChord.commandReturn == KeyChord(kVK_Return, .maskCommand))
    }
}
