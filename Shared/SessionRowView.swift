import SwiftUI

extension SessionStatus {
    var color: Color {
        switch self {
        case .needsInput: .orange
        case .yourTurn: .blue
        case .working: .green
        case .idle: .secondary
        }
    }
}

/// One session, used by both the menu bar window and the widget.
struct SessionRowView: View {
    let session: SessionSummary
    let now: Date
    var showsDetail = true
    /// When set, the project name is a link that calls this.
    var onOpen: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: session.status.symbolName)
                .foregroundStyle(session.status.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    title
                    Spacer(minLength: 4)
                    Text("\(session.status.label) · \(session.statusSince.shortAge(relativeTo: now))")
                        .font(.caption2)
                        .foregroundStyle(session.status.color)
                        .lineLimit(1)
                        .fixedSize()
                }
                if showsDetail, let detail = session.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var title: some View {
        let name = Text(session.project).font(.system(.callout, weight: .semibold))
        if let onOpen {
            Button(action: onOpen) {
                name.underline(isHovering).foregroundStyle(Color.accentColor).lineLimit(1)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help("Go to this session")
        } else {
            name.lineLimit(1)
        }
    }
}
