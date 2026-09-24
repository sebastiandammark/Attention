import SwiftUI

@main
struct AttentionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: appDelegate.monitor)
        } label: {
            MenuBarLabel(monitor: appDelegate.monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the monitor, so the widget's session links can reach it even when the
/// menu bar window has never been opened.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = SessionMonitor()

    override init() {
        super.init()
        monitor.start()
    }

    /// Handles dammark-attention://session/<id> from the widget.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == SessionSummary.urlScheme && url.host == "session" {
            monitor.refresh()
            if let session = monitor.sessions.first(where: { $0.id == url.lastPathComponent }) {
                SessionOpener.open(session)
            }
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var monitor: SessionMonitor

    var body: some View {
        if monitor.awaitingCount > 0 {
            Text("\(Image(systemName: "hand.raised.fill")) \(monitor.awaitingCount)")
        } else {
            Image(systemName: "sparkles")
        }
    }
}
