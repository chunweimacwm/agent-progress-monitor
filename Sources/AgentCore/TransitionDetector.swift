import Foundation

public enum AlertKind: Sendable, Equatable {
    case done, waiting
}

public struct Alert: Sendable, Equatable {
    public var session: AgentSession
    public var kind: AlertKind
}

/// 比對前後兩次的狀態，找出「剛完成」與「剛開始等你」。
/// 第一次只記錄現況不提示；同一輪同一種提示只發一次。
public struct TransitionDetector {
    /// 太短的一輪完成不提示（30 秒）
    public var minTurnDuration: TimeInterval = 30

    private var last: [String: SessionStatus]?
    private var fired: Set<String> = []

    public init() {}

    public mutating func update(_ sessions: [AgentSession]) -> [Alert] {
        defer { last = Dictionary(sessions.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a }) }
        guard let last else { return [] }
        var alerts: [Alert] = []
        for s in sessions {
            let before = last[s.id]
            guard before != s.status else { continue }
            let kind: AlertKind
            switch s.status {
            case .done where before == .working || before == .waiting:
                guard let start = s.turnStartedAt, let end = s.finishedAt,
                      end.timeIntervalSince(start) >= minTurnDuration else { continue }
                kind = .done
            case .waiting:
                kind = .waiting
            default:
                continue
            }
            // 同一輪（以開始時間區分）同一種提示只發一次
            let key = "\(s.id)|\(s.turnStartedAt?.timeIntervalSince1970 ?? 0)|\(kind)"
            guard fired.insert(key).inserted else { continue }
            alerts.append(Alert(session: s, kind: kind))
        }
        if fired.count > 500 { fired.removeAll() }
        return alerts
    }
}
