import AppKit

/// Brings a session's app to the front, and in Terminal or iTerm, the tab it runs in.
enum SessionOpener {
    /// Editors that focus the window showing a folder when asked to open it again.
    private static let editors: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
    ]

    static func canOpen(_ session: SessionSummary) -> Bool {
        appURL(for: session) != nil
    }

    static func open(_ session: SessionSummary) {
        guard let bundleID = session.host?.bundleID, let appURL = appURL(for: session) else { return }
        if let tty = session.host?.tty, selectTab(tty: tty, bundleID: bundleID) { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if editors.contains(bundleID), !session.cwd.isEmpty {
            NSWorkspace.shared.open([URL(fileURLWithPath: session.cwd, isDirectory: true)],
                                    withApplicationAt: appURL, configuration: configuration)
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }

    private static func appURL(for session: SessionSummary) -> URL? {
        session.host?.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    /// Asks Terminal or iTerm to select the tab using `tty`. Returns false if it
    /// isn't one of those, the tab is gone, or you denied Automation access.
    private static func selectTab(tty: String, bundleID: String) -> Bool {
        guard tty.range(of: #"^/dev/tty[A-Za-z0-9]+$"#, options: .regularExpression) != nil else { return false }
        let source: String
        switch bundleID {
        case "com.apple.Terminal":
            source = """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            source = """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            return false
        }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil && result?.booleanValue == true
    }
}
