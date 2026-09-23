import SwiftUI

@main
struct AttentionApp: App {
    @StateObject private var monitor: SessionMonitor

    init() {
        let monitor = SessionMonitor()
        monitor.start()
        _monitor = StateObject(wrappedValue: monitor)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
        } label: {
            if monitor.awaitingCount > 0 {
                Text("\(Image(systemName: "hand.raised.fill")) \(monitor.awaitingCount)")
            } else {
                Image(systemName: "sparkles")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
