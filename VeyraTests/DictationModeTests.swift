import Testing
@testable import Veyra

@MainActor
struct DictationModeTests {
    @Test(arguments: [
        ("com.apple.mail", DictationMode.email),
        ("com.microsoft.Outlook", .email),
        ("com.readdle.SparkDesktop", .email),
        ("com.readdle.smartemail-Mac", .email),
        ("com.tinyspeck.slackmacgap", .chat),
        ("com.microsoft.teams2", .chat),
        ("com.microsoft.teams", .chat),
        ("net.whatsapp.WhatsApp", .chat),
        ("com.apple.MobileSMS", .chat),
        ("com.hnc.Discord", .chat),
        ("ru.keepcoder.Telegram", .chat),
        ("com.microsoft.VSCode", .editor),
        ("com.apple.dt.Xcode", .editor),
        ("com.todesktop.230313mzl4w4u92", .editor),
        ("dev.zed.Zed", .editor),
        ("com.sublimetext.4", .editor),
        ("com.apple.TextEdit", .editor),
        ("com.apple.Notes", .editor),
        ("com.jetbrains.intellij", .editor),
        ("com.apple.Terminal", .terminal),
        ("com.mitchellh.ghostty", .terminal),
        ("com.googlecode.iterm2", .terminal),
        ("dev.warp.Warp-Stable", .terminal),
        ("com.example.App", .standard),
    ])
    func resolvesApp(bundleIdentifier: String, expected: DictationMode) {
        #expect(DictationMode(AppContext(bundleIdentifier: bundleIdentifier, windowTitle: nil)) == expected)
    }

    @Test(arguments: [
        ("Inbox (3) - me@example.com - Gmail", DictationMode.email),
        ("Mail - Ajay - Outlook", .email),
        ("Google Chat", .chat),
        ("general (Channel) - Veyra - Slack", .chat),
        ("(3) WhatsApp", .chat),
        ("Slack invite - me@example.com - Gmail", .email),
        ("Slack - Gmail", .email),
        ("Weekly plan – Google Docs", .standard),
    ])
    func resolvesBrowserTitle(title: String, expected: DictationMode) {
        #expect(DictationMode(AppContext(bundleIdentifier: "com.google.Chrome", windowTitle: title)) == expected)
    }

    @Test func chromeWebAppResolvesByTitle() {
        let context = AppContext(bundleIdentifier: "com.google.Chrome.app.mdpkiolbdkhdjpekfbkbmhigcaggjagi", windowTitle: "Google Chat")
        #expect(DictationMode(context) == .chat)
    }

    @Test func mappedAppWinsOverTitle() {
        #expect(DictationMode(AppContext(bundleIdentifier: "com.mitchellh.ghostty", windowTitle: "Gmail")) == .terminal)
    }

    @Test func missingContextIsStandard() {
        #expect(DictationMode(AppContext(bundleIdentifier: nil, windowTitle: nil)) == .standard)
    }

    @Test func terminalFlattensLinesAndBullets() {
        let reply = "A few things:\n- The icon is final.\n* The readme is updated.\n\n• The tests  pass."
        #expect(DictationMode.terminal.finalize(reply) == "A few things: The icon is final. The readme is updated. The tests pass.")
    }

    @Test(arguments: [DictationMode.email, .chat, .editor, .standard])
    func otherModesKeepLines(mode: DictationMode) {
        let reply = "Hi John,\n\n- One\n- Two"
        #expect(mode.finalize(reply) == reply)
    }
}
