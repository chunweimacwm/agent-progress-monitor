import Foundation

/// 合併 Claude Code 狀態檔與 Codex 紀錄，回傳要顯示的 session
public final class Monitor {
    private let claude: ClaudeStatusReader
    private let codex: CodexScanner
    private let claudeUsage = ClaudeUsageReader()
    private var lastCodexUsage: AgentUsage?

    public init(claude: ClaudeStatusReader = ClaudeStatusReader(), codex: CodexScanner = CodexScanner()) {
        self.claude = claude
        self.codex = codex
    }

    public func poll(now: Date = Date()) -> [AgentSession] {
        (claude.read(now: now) + codex.scan(now: now)).sorted {
            $0.status != $1.status ? $0.status < $1.status : $0.updatedAt > $1.updatedAt
        }
    }

    /// 兩邊的額度；要在 poll 之後呼叫（Codex 的數字來自 poll 讀到的紀錄）
    public func usage(now: Date = Date()) -> [AgentUsage] {
        // Codex 紀錄超過 6 小時就不追蹤了，保留最後看到的那份
        if let u = codex.latestUsage, u.observedAt >= (lastCodexUsage?.observedAt ?? .distantPast) { lastCodexUsage = u }
        return [claudeUsage.read(), lastCodexUsage].compactMap { $0 }.map { u in
            AgentUsage(tool: u.tool, windows: u.windows.map { $0.current(now: now) }, observedAt: u.observedAt)
        }
    }
}
