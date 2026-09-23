import Foundation
import WidgetKit

/// Polls the hook state, publishes it to the menu bar and mirrors it to the widget.
/// Everything runs on the main run loop.
final class SessionMonitor: ObservableObject {
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var hooksInstalled = HookInstaller.isInstalled()
    @Published private(set) var lastError: String?

    private let reader = SessionReader()
    private var timer: Timer?
    private var hasPublished = false

    var awaitingCount: Int { sessions.filter { $0.status.awaitsUser }.count }

    func start() {
        guard timer == nil else { return }
        refresh()
        // The state is a handful of tiny files, so polling is cheaper than it sounds
        // and, unlike a directory watcher, sees changes inside each session folder.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let current = reader.read()
        // Only status changes reach the widget, so it isn't reloaded on every tool call.
        guard !hasPublished || current != sessions else { return }
        hasPublished = true
        sessions = current
        do {
            try SnapshotStore.save(AttentionSnapshot(sessions: current, generatedAt: Date()))
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = "Couldn't update the widget: \(error.localizedDescription)"
        }
    }

    func dismiss(_ session: SessionSummary) {
        reader.remove(sessionID: session.id)
        refresh()
    }

    func installHooks() {
        do {
            try HookInstaller.install()
            hooksInstalled = true
            lastError = nil
        } catch {
            lastError = "Couldn't install hooks: \(error.localizedDescription)"
        }
    }
}
