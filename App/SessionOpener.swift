import AppKit
import ApplicationServices

/// Brings a session's app to the front, and in Terminal or iTerm, the tab it runs in.
/// In the Claude desktop app it clicks the session in the sidebar.
enum SessionOpener {
    /// Editors that focus the window showing a folder when asked to open it again.
    private static let editors: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
    ]

    static func canOpen(_ session: SessionSummary) -> Bool {
        claudeApp(for: session) != nil || appURL(for: session) != nil
    }

    static func open(_ session: SessionSummary) {
        if let claude = claudeApp(for: session) {
            claude.activate()
            if let title = session.title { ClaudeSidebar.select(title: title, in: claude.processIdentifier) }
            return
        }
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

    /// The running Claude desktop app, if the session runs in it. A session with a
    /// title but no host info (it hasn't fired a hook since the update) is assumed to.
    private static func claudeApp(for session: SessionSummary) -> NSRunningApplication? {
        if let bundleID = session.host?.bundleID {
            guard bundleID.hasPrefix("com.anthropic.") else { return nil }
        } else if session.title == nil {
            return nil
        }
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && $0.bundleIdentifier?.hasPrefix("com.anthropic.") == true
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

/// Finds a session in the Claude app's sidebar by its title and clicks it, through
/// the Accessibility API. The Claude app has no link to a session, so this is the
/// only way in. It needs Accessibility permission, and it does nothing if the title
/// isn't on screen.
private enum ClaudeSidebar {
    static func select(title: String, in pid: pid_t) {
        // Shows the system prompt to grant permission the first time.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let app = AXUIElementCreateApplication(pid)
            // Electron apps only build their accessibility tree once asked to.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            // The tree can take a moment to appear, and the window to come to the front.
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 0.2)
                if let element = findText(title, in: app) {
                    press(element)
                    return
                }
            }
        }
    }

    /// The left-most static text whose value is `title`, which is the sidebar entry
    /// rather than, say, the header of the session that's open.
    private static func findText(_ title: String, in root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var visited = 0
        var best: (element: AXUIElement, x: CGFloat)?
        while !queue.isEmpty, visited < 20_000 {
            let element = queue.removeFirst()
            visited += 1
            if attribute(element, kAXRoleAttribute) as? String == kAXStaticTextRole as String,
               attribute(element, kAXValueAttribute) as? String == title,
               let frame = frame(of: element), frame.width > 0 {
                if best == nil || frame.minX < best!.x { best = (element, frame.minX) }
                continue
            }
            queue += attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return best?.element
    }

    /// Presses the nearest ancestor that can be pressed, or else clicks the text.
    private static func press(_ element: AXUIElement) {
        AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let candidate = current else { break }
            var names: CFArray?
            if AXUIElementCopyActionNames(candidate, &names) == .success,
               ((names as NSArray?) as? [String])?.contains(kAXPressAction as String) == true {
                AXUIElementPerformAction(candidate, kAXPressAction as CFString)
                return
            }
            current = attribute(candidate, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        guard let frame = frame(of: element) else { return }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}
