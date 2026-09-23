import Foundation

/// Reads and writes the snapshot shared between the app and the widget.
///
/// The widget is sandboxed and can't see ~/.claude, so the app mirrors what it
/// finds there into the App Group container named by `AttentionAppGroup` in
/// each target's Info.plist.
enum SnapshotStore {
    static var fileURL: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AttentionAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return container.appendingPathComponent("snapshot.json")
    }

    static func load() -> AttentionSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AttentionSnapshot.self, from: data)
    }

    static func save(_ snapshot: AttentionSnapshot) throws {
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}
