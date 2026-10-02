import Foundation

enum ShellCommand {
    static let limit = 1_000

    /// The model's command as one line that's safe to paste: nothing in it can press Return or hide characters.
    static func clean(_ raw: String) throws -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.count >= 2, text.hasPrefix("`"), text.hasSuffix("`") {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text.replacing(#/^[$%](\s+|$)/#, with: "")
        guard !text.isEmpty else { throw AgentError.invalidArguments }
        let hidden = CharacterSet.controlCharacters.union(.newlines)
        guard !text.unicodeScalars.contains(where: hidden.contains), text.count <= limit else {
            throw AgentError.badCommand
        }
        return text
    }
}

/// Commands worth a second look before Return, most serious first. `sudo` comes last so a specific reason wins.
enum ShellRisk: String, CaseIterable {
    case disk, download, delete, git, permissions, processes, admin

    var reason: String {
        switch self {
        case .disk: "this can erase a disk"
        case .download: "this runs downloaded code"
        case .delete: "this deletes files"
        case .admin: "this runs as administrator"
        case .git: "this can discard git work"
        case .permissions: "this changes many permissions"
        case .processes: "this stops processes"
        }
    }

    static func of(_ command: String) -> ShellRisk? {
        allCases.first { command.contains($0.pattern.wordBoundaryKind(.simple)) }
    }

    private var pattern: Regex<Substring> {
        switch self {
        case .disk:
            #/\bdd\b[^;&|]*\bof=|\bmkfs\b|\bdiskutil\s+(?:erase\w*|zeroDisk|secureErase|partitionDisk|reformat)\b/#
        case .download:
            #/\b(?:curl|wget)\b[^;&]*\|\s*(?:sudo\s+)?(?:sh|bash|zsh|fish|python3?|ruby|perl)\b|\b(?:sh|bash|zsh)\s+<\(\s*(?:curl|wget)\b/#
        case .delete:
            #/\brm\b[^;&|]*\s(?:-[a-zA-Z]*[rRf][a-zA-Z]*|--recursive|--force)\b|\bfind\b[^;&|]*\s-delete\b|\b(?:shred|srm)\b/#
        case .admin:
            #/\bsudo\b/#
        case .git:
            #/\bgit\b[^;&|]*\b(?:push\b[^;&|]*\s(?:--force|-f)\b|reset\b[^;&|]*\s--hard\b|clean\b[^;&|]*\s-[a-zA-Z]*f|branch\b[^;&|]*\s-D\b)/#
        case .permissions:
            #/\b(?:chmod|chown|chgrp)\b[^;&|]*\s-[a-zA-Z]*R/#
        case .processes:
            #/\bkill\b[^;&|]*\s-(?:9|KILL|SIGKILL)\b|\b(?:killall|pkill)\b/#
        }
    }
}
