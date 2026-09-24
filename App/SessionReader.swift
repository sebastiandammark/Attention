import Foundation

/// Turns the per-session event files written by `attention-hook.sh` into summaries.
struct SessionReader {
    var root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/attention/sessions", isDirectory: true)
    /// Sessions with no hook activity for this long are treated as gone, e.g. a
    /// terminal that was closed without Claude Code sending `SessionEnd`.
    var maxAge: TimeInterval = 12 * 60 * 60

    func read(now: Date = Date()) -> [SessionSummary] {
        let dirs = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return dirs.compactMap { summarize($0, now: now) }.sorted { a, b in
            if a.status.priority != b.status.priority { return a.status.priority < b.status.priority }
            return a.statusSince > b.statusSince
        }
    }

    /// Forgets a session. If it is still running, its next hook event brings it back.
    func remove(sessionID: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(sessionID, isDirectory: true))
    }

    private struct Event {
        let name: String
        let receivedAt: Date
        let payload: [String: Any]

        func string(_ key: String) -> String? {
            guard let value = payload[key] as? String, !value.isEmpty else { return nil }
            return value
        }
    }

    private func summarize(_ dir: URL, now: Date) -> SessionSummary? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        var events: [String: Event] = [:]
        for event in files.filter({ $0.lastPathComponent != "host.json" }).compactMap(loadEvent) {
            events[event.name] = event
        }
        // A login confirmation says nothing about whether Claude needs you.
        if events["Notification"]?.string("notification_type") == "auth_success" {
            events["Notification"] = nil
        }
        guard let latest = events.values.max(by: { $0.receivedAt < $1.receivedAt }),
              now.timeIntervalSince(latest.receivedAt) < maxAge
        else { return nil }

        let prompt = events["UserPromptSubmit"]?.string("prompt")
        var status: SessionStatus
        var since = latest.receivedAt
        var detail = prompt

        switch latest.name {
        case "Notification":
            if latest.string("notification_type") == "idle_prompt" {
                status = .yourTurn
                since = events["Stop"]?.receivedAt ?? latest.receivedAt
            } else {
                status = .needsInput
                detail = latest.string("message") ?? prompt
            }
        case "Stop":
            status = .yourTurn
        case "PreToolUse" where latest.string("tool_name") == "AskUserQuestion":
            status = .needsInput
            detail = "Claude has a question for you"
        case "PreToolUse" where latest.string("tool_name") == "ExitPlanMode":
            status = .needsInput
            detail = "Plan ready for your review"
        case "UserPromptSubmit", "PreToolUse", "PostToolUse":
            status = .working
            since = events["UserPromptSubmit"]?.receivedAt ?? latest.receivedAt
        default:
            status = .idle
        }

        // Pressing Esc stops Claude without a `Stop` event, so check the transcript.
        if status == .working,
           let interruptedAt = interruption(transcriptPath: latest.string("transcript_path"), after: latest.receivedAt) {
            status = .yourTurn
            since = interruptedAt
        }

        return SessionSummary(
            id: dir.lastPathComponent,
            cwd: latest.string("cwd") ?? events.values.lazy.compactMap { $0.string("cwd") }.first ?? "",
            status: status,
            statusSince: since,
            detail: detail.map(Self.oneLine),
            host: loadHost(dir.appendingPathComponent("host.json"))
        )
    }

    private func loadHost(_ url: URL) -> SessionHost? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return nil }
        let host = SessionHost(bundleID: object["bundle_id"].flatMap { $0.isEmpty ? nil : $0 },
                               tty: object["tty"].flatMap { $0.isEmpty ? nil : $0 })
        return host.bundleID == nil ? nil : host
    }

    private func loadEvent(_ url: URL) -> Event? {
        guard url.pathExtension == "json",
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let receivedAt = object["received_at"] as? Double,
              let payload = object["event"] as? [String: Any]
        else { return nil }
        return Event(name: url.deletingPathExtension().lastPathComponent,
                     receivedAt: Date(timeIntervalSince1970: receivedAt),
                     payload: payload)
    }

    /// Returns when the transcript was interrupted, if its last entry since `date` is an interruption.
    private func interruption(transcriptPath: String?, after date: Date) -> Date? {
        guard let path = transcriptPath,
              let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
              modified > date,
              let handle = FileHandle(forReadingAtPath: path)
        else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 8192 ? size - 8192 : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        let lastLine = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).last ?? ""
        return lastLine.contains("[Request interrupted by user") ? modified : nil
    }

    private static func oneLine(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 200 ? String(collapsed.prefix(200)) + "…" : collapsed
    }
}
