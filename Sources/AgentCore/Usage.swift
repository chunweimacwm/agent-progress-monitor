import Foundation

/// 一個用量視窗（5 小時、每週）。兩邊都只公布百分比，不公布實際 token 額度。
public struct UsageWindow: Equatable, Sendable {
    public var kind: String
    public var percentUsed: Double
    public var resetsAt: Date?

    public init(kind: String, percentUsed: Double, resetsAt: Date?) {
        self.kind = kind
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
    }

    public var label: String {
        switch kind {
        case "five_hour", "primary": L("5 小時", "5-hour")
        case "seven_day", "secondary": L("每週", "Weekly")
        case "seven_day_opus": L("每週 Opus", "Weekly Opus")
        case "seven_day_sonnet": L("每週 Sonnet", "Weekly Sonnet")
        case "spend_limit": L("額度", "Spend")
        default: kind
        }
    }

    /// 紀錄是上一次 API 回應時的數字；重置時間已過就代表已歸零
    public func current(now: Date) -> UsageWindow {
        guard let r = resetsAt, r <= now else { return self }
        return UsageWindow(kind: kind, percentUsed: 0, resetsAt: nil)
    }

    public var percentLeft: Double { max(0, 100 - percentUsed) }
}

public struct AgentUsage: Equatable, Sendable {
    public var tool: AgentTool
    public var windows: [UsageWindow]
    /// 這份數字是什麼時候的
    public var observedAt: Date
}

/// 讀 agent-progress mod 寫的 ~/.agent-progress/usage/claude-code.json
public struct ClaudeUsageReader {
    public var file: URL

    public init(file: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".agent-progress/usage/claude-code.json")) {
        self.file = file
    }

    struct Record: Decodable {
        struct Window: Decodable {
            var kind: String
            var percentUsed: Double
            var resetsAt: String?
        }

        var v: Int
        var updatedAt: Double
        var windows: [Window]
    }

    public func read() -> AgentUsage? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return Self.parse(data)
    }

    static func parse(_ data: Data) -> AgentUsage? {
        guard let r = try? JSONDecoder().decode(Record.self, from: data), r.v == 1, !r.windows.isEmpty else { return nil }
        return AgentUsage(
            tool: .claudeCode,
            windows: r.windows.map { UsageWindow(kind: $0.kind, percentUsed: $0.percentUsed, resetsAt: $0.resetsAt.flatMap(CodexParser.parseDate)) },
            observedAt: Date(timeIntervalSince1970: r.updatedAt / 1000)
        )
    }
}

public func formatCountdown(to date: Date, now: Date) -> String {
    let min = Int(max(0, date.timeIntervalSince(now)) / 60)
    // 浮窗很窄，不留空格
    if min < 60 { return L("\(min)分後重置", "resets in \(min)m") }
    let h = min / 60
    if h < 24 { return L("\(h)時\(min % 60)分後重置", "resets in \(h)h \(min % 60)m") }
    return L("\(h / 24)天\(h % 24)時後重置", "resets in \(h / 24)d \(h % 24)h")
}
