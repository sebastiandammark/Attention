import Foundation

/// Where a Claude Code session stands, from your point of view.
enum SessionStatus: String, Codable, CaseIterable {
    /// Claude is blocked on you: a permission prompt, a question or a plan to approve.
    case needsInput
    /// Claude finished its turn and is waiting for your next prompt.
    case yourTurn
    /// Claude is working on a prompt.
    case working
    /// The session is open but hasn't been given a prompt yet.
    case idle

    var awaitsUser: Bool { self == .needsInput || self == .yourTurn }

    /// Lower sorts first, so the sessions that need you come to the top.
    var priority: Int {
        switch self {
        case .needsInput: 0
        case .yourTurn: 1
        case .working: 2
        case .idle: 3
        }
    }

    var label: String {
        switch self {
        case .needsInput: "Needs you"
        case .yourTurn: "Your turn"
        case .working: "Working"
        case .idle: "Idle"
        }
    }

    var symbolName: String {
        switch self {
        case .needsInput: "hand.raised.fill"
        case .yourTurn: "arrowshape.turn.up.left.fill"
        case .working: "ellipsis.circle.fill"
        case .idle: "moon.zzz.fill"
        }
    }
}

struct SessionSummary: Codable, Hashable, Identifiable {
    var id: String
    var cwd: String
    var status: SessionStatus
    /// When the session entered its current status.
    var statusSince: Date
    /// What Claude is asking for, or the prompt it is working on.
    var detail: String?
    /// The app and terminal the session runs in, if the hook could tell.
    var host: SessionHost?
    /// The title Claude gave the session, as shown in the Claude app's sidebar.
    var title: String?

    var project: String {
        cwd.isEmpty ? "Claude Code" : (cwd as NSString).lastPathComponent
    }

    /// Opens the Attention app, which brings this session to the front. The widget
    /// links rows to this; it's `nil` when the app wouldn't know where to go.
    var openURL: URL? {
        host == nil && title == nil ? nil : URL(string: "\(Self.urlScheme)://session/\(id)")
    }

    static let urlScheme = "dammark-attention"
}

struct SessionHost: Codable, Hashable {
    /// The bundle ID of the app the session runs in, such as com.apple.Terminal.
    var bundleID: String?
    /// The terminal device, such as /dev/ttys003, which identifies the tab.
    var tty: String?
}

/// What the app hands to the widget through the shared App Group container.
struct AttentionSnapshot: Codable, Equatable {
    var sessions: [SessionSummary]
    var generatedAt: Date

    var awaitingCount: Int { sessions.filter { $0.status.awaitsUser }.count }
    var workingCount: Int { sessions.filter { $0.status == .working }.count }
}

extension AttentionSnapshot {
    static let preview = AttentionSnapshot(
        sessions: [
            SessionSummary(id: "1", cwd: "/Users/me/web-shop", status: .needsInput,
                           statusSince: Date().addingTimeInterval(-240),
                           detail: "Claude needs your permission to use Bash"),
            SessionSummary(id: "2", cwd: "/Users/me/api", status: .yourTurn,
                           statusSince: Date().addingTimeInterval(-900),
                           detail: "Add pagination to the orders endpoint"),
            SessionSummary(id: "3", cwd: "/Users/me/design-system", status: .working,
                           statusSince: Date().addingTimeInterval(-60),
                           detail: "Migrate the button styles to tokens"),
        ],
        generatedAt: Date()
    )
}

extension Date {
    /// A compact age such as "now", "4m", "2h" or "3d".
    func shortAge(relativeTo now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(self))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86400))d"
        }
    }
}
