import Foundation

public enum AgentTool: String, Sendable {
    case claudeCode = "CC"
    case codex = "Codex"
}

public enum SessionStatus: Int, Sendable, Comparable {
    // 排序：等你 → 工作中 → 完成 → 閒置
    case waiting = 0, working, done, idle

    public static func < (a: SessionStatus, b: SessionStatus) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .working: L("工作中", "Working")
        case .waiting: L("等你", "Needs you")
        case .done: L("完成", "Done")
        case .idle: L("閒置", "Idle")
        }
    }
}

public enum StepStatus: String, Sendable {
    case pending, inProgress = "in_progress", completed, deleted

    public init(raw: String?) {
        self = StepStatus(rawValue: raw ?? "") ?? .pending
    }
}

public struct PlanStep: Equatable, Sendable {
    public var title: String
    public var status: StepStatus

    public init(title: String, status: StepStatus) {
        self.title = title
        self.status = status
    }
}

public struct AgentSession: Identifiable, Equatable, Sendable {
    public var id: String { "\(tool.rawValue):\(sessionId)" }
    public var tool: AgentTool
    public var sessionId: String
    public var project: String
    public var title: String?
    public var status: SessionStatus
    public var plan: [PlanStep]?
    public var turnStartedAt: Date?
    public var finishedAt: Date?
    public var updatedAt: Date
    /// 點一下跳過去的連結；Claude Code 桌面版才有
    public var jumpURL: URL?
    /// 這一輪有收到完成訊號（中斷不算）；完成後轉成閒置仍算，進度才給 100%
    public var turnCompleted = false

    /// Codex 開新對話後要過一陣子才會寫入標題，這段時間顯示「新對話」而不是資料夾名稱
    public var displayName: String { title ?? (tool == .codex ? L("新對話", "New thread") : project) }
    public var progress: PlanProgress? { PlanProgress.estimate(plan, isDone: turnCompleted) }
}

/// 判斷門檻，和 agent-progress mod 一致
public enum Thresholds {
    public static let claudeStale: TimeInterval = 120
    /// Codex 沒有心跳；長指令時紀錄可能幾分鐘不動，放寬一點
    public static let codexStale: TimeInterval = 10 * 60
    public static let idleAfterDone: TimeInterval = 10 * 60
    public static let hideAfter: TimeInterval = 6 * 60 * 60
}
