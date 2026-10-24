import Foundation

/// 讀 agent-progress mod 寫的狀態檔：~/.agent-progress/claude-code/<session>.json（格式見 mod 的 types/index.d.ts）
public struct ClaudeStatusReader {
    public var directory: URL
    /// 舊狀態檔缺標題或桌面版 id 時補查；nil 表示不補
    public var lookup: ClaudeMetaLookup?

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".agent-progress/claude-code"), lookup: ClaudeMetaLookup? = ClaudeMetaLookup()) {
        self.directory = directory
        self.lookup = lookup
    }

    struct Record: Decodable {
        struct Step: Decodable {
            var title: String
            var status: String
        }

        var v: Int
        var tool: String
        var sessionId: String
        var project: String
        var title: String?
        var hostSessionId: String?
        var status: String
        var plan: [Step]?
        var turnStartedAt: Double?
        var finishedAt: Double?
        var updatedAt: Double
    }

    public func read(now: Date = Date()) -> [AgentSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { Self.session(from: $0, now: now) }
            .map { fillMissing($0, now: now) }
    }

    private func fillMissing(_ s: AgentSession, now: Date) -> AgentSession {
        guard let lookup else { return s }
        var s = s
        if s.title == nil { s.title = lookup.title(for: s.sessionId, now: now) }
        if s.jumpURL == nil { s.jumpURL = Self.jumpURL(host: lookup.hostSessionId(for: s.sessionId, now: now)) }
        return s
    }

    /// 桌面版深層連結只收內部 id（local_…）
    static func jumpURL(host: String?) -> URL? {
        guard let host, host.range(of: #"^local_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "claude://code/continue?session=\(host)&source=spotlight")
    }

    static func date(_ ms: Double?) -> Date? { ms.map { Date(timeIntervalSince1970: $0 / 1000) } }

    /// 和 mod 的 shownStatus 同一套規則；回傳 nil 表示不顯示
    static func session(from data: Data, now: Date) -> AgentSession? {
        guard let r = try? JSONDecoder().decode(Record.self, from: data),
              r.v == 1, r.tool == "claude-code" else { return nil }
        let updated = Date(timeIntervalSince1970: r.updatedAt / 1000)
        let finished = date(r.finishedAt)
        let age = now.timeIntervalSince(updated)
        if r.status == "ended" || age > Thresholds.hideAfter { return nil }

        let status: SessionStatus
        switch r.status {
        case "working", "waiting":
            status = age > Thresholds.claudeStale ? .idle : (r.status == "working" ? .working : .waiting)
        case "done":
            status = finished.map { now.timeIntervalSince($0) > Thresholds.idleAfterDone } == true ? .idle : .done
        default:
            status = .idle
        }

        return AgentSession(
            tool: .claudeCode,
            sessionId: r.sessionId,
            project: r.project,
            title: r.title,
            status: status,
            plan: r.plan?.map { PlanStep(title: $0.title, status: StepStatus(raw: $0.status)) },
            turnStartedAt: date(r.turnStartedAt),
            finishedAt: finished,
            updatedAt: updated,
            jumpURL: jumpURL(host: r.hostSessionId),
            turnCompleted: r.status == "done"
        )
    }
}
