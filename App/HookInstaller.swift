import Foundation

/// Copies `attention-hook.sh` to ~/.claude/attention/hook.sh and registers it
/// for the session events it needs in Claude Code's user settings.
enum HookInstaller {
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "Notification", "Stop", "SessionEnd",
    ]

    private static let claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude", isDirectory: true)
    static let scriptURL = claudeDir.appendingPathComponent("attention/hook.sh")
    static let settingsURL = claudeDir.appendingPathComponent("settings.json")

    enum InstallError: LocalizedError {
        case missingScript
        case unreadableSettings(Error)

        var errorDescription: String? {
            switch self {
            case .missingScript:
                "The hook script is missing from the app bundle."
            case .unreadableSettings(let error):
                "~/.claude/settings.json isn't valid JSON, so it was left alone (\(error.localizedDescription))."
            }
        }
    }

    static func isInstalled() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path),
              let hooks = (try? loadSettings())?["hooks"] as? [String: Any]
        else { return false }
        return events.allSatisfy { isRegistered(in: hooks[$0]) }
    }

    /// Safe to run repeatedly: it refreshes the script and only adds missing entries.
    static func install() throws {
        guard let bundled = Bundle.main.url(forResource: "attention-hook", withExtension: "sh") else {
            throw InstallError.missingScript
        }
        let fm = FileManager.default
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: scriptURL.path) {
            try fm.removeItem(at: scriptURL)
        }
        try fm.copyItem(at: bundled, to: scriptURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var settings: [String: Any]
        do {
            settings = try loadSettings()
        } catch {
            throw InstallError.unreadableSettings(error)
        }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let missing = events.filter { !isRegistered(in: hooks[$0]) }
        guard !missing.isEmpty else { return }

        for event in missing {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": "\"\(scriptURL.path)\"", "timeout": 10]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks

        if fm.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("attention-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    private static func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return settings
    }

    private static func isRegistered(in groups: Any?) -> Bool {
        (groups as? [[String: Any]] ?? []).contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains {
                ($0["command"] as? String)?.contains("attention/hook.sh") == true
            }
        }
    }
}
