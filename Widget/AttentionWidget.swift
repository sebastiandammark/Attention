import SwiftUI
import WidgetKit

struct AttentionEntry: TimelineEntry {
    let date: Date
    /// `nil` until the Attention app has run and written its first snapshot.
    let snapshot: AttentionSnapshot?
}

struct AttentionProvider: TimelineProvider {
    func placeholder(in context: Context) -> AttentionEntry {
        AttentionEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (AttentionEntry) -> Void) {
        let snapshot = context.isPreview ? AttentionSnapshot.preview : SnapshotStore.load()
        completion(AttentionEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AttentionEntry>) -> Void) {
        // The app reloads the widget whenever a session changes status. Between
        // reloads, one entry a minute keeps the "4m" ages current.
        let snapshot = SnapshotStore.load()
        let start = Date()
        let entries = (0..<60).map {
            AttentionEntry(date: start.addingTimeInterval(Double($0) * 60), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct AttentionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AttentionEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: small(snapshot)
                default: list(snapshot)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    title
                    Spacer()
                    Text("Open the Attention app and install its hooks to see your sessions here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var title: some View {
        Label("Claude", systemImage: "sparkles")
            .font(.headline)
    }

    private func small(_ snapshot: AttentionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
            Spacer(minLength: 0)
            Text("\(snapshot.awaitingCount)")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(snapshot.awaitingCount > 0 ? Color.orange : Color.secondary)
            Text("waiting on you")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ForEach(snapshot.sessions.prefix(2)) { session in
                Label(session.project, systemImage: session.status.symbolName)
                    .font(.caption2)
                    .foregroundStyle(session.status.color)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A small widget is a single tap target, so it goes to the session most
        // likely to need you.
        .widgetURL(snapshot.sessions.first(where: { $0.status.awaitsUser })?.openURL)
    }

    private func list(_ snapshot: AttentionSnapshot) -> some View {
        let limit = family == .systemLarge ? 7 : 3
        let shown = snapshot.sessions.prefix(limit)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                title
                Spacer()
                if snapshot.awaitingCount > 0 {
                    Label("\(snapshot.awaitingCount)", systemImage: "hand.raised.fill")
                        .foregroundStyle(.orange)
                }
                if snapshot.workingCount > 0 {
                    Label("\(snapshot.workingCount)", systemImage: "ellipsis.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption.weight(.semibold))

            if shown.isEmpty {
                Spacer()
                Text("No active Claude Code sessions")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(shown) { session in
                    if let url = session.openURL {
                        Link(destination: url) {
                            SessionRowView(session: session, now: entry.date)
                        }
                    } else {
                        SessionRowView(session: session, now: entry.date)
                    }
                }
                Spacer(minLength: 0)
                if snapshot.sessions.count > shown.count {
                    Text("+\(snapshot.sessions.count - shown.count) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@main
struct AttentionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AttentionWidget", provider: AttentionProvider()) { entry in
            AttentionWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Sessions")
        .description("Your active Claude Code sessions, with the ones waiting on you first.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    AttentionWidget()
} timeline: {
    AttentionEntry(date: .now, snapshot: .preview)
    AttentionEntry(date: .now, snapshot: AttentionSnapshot(sessions: [], generatedAt: .now))
}
