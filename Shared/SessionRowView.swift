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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: session.status.symbolName)
                .foregroundStyle(session.status.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(session.project)
                        .font(.system(.callout, weight: .semibold))
                        .lineLimit(1)
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
}
