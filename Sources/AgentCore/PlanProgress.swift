import Foundation

public struct PlanProgress: Equatable, Sendable {
    public var step: Int
    public var total: Int
    public var percent: Int
    public var current: String?

    /// 完成步驟 ÷ 總步驟，進行中算半步；只有完成訊號才給 100%，否則最多 95%。
    /// 沒有計畫回傳 nil（介面不顯示百分比）。
    public static func estimate(_ plan: [PlanStep]?, isDone: Bool) -> PlanProgress? {
        guard let steps = plan?.filter({ $0.status != .deleted }), !steps.isEmpty else { return nil }
        let done = steps.filter { $0.status == .completed }.count
        let current = steps.first { $0.status == .inProgress }
        let raw = Int((Double(done) + (current == nil ? 0 : 0.5)) / Double(steps.count) * 100 + 0.5)
        return PlanProgress(
            step: min(steps.count, done + (current == nil ? 0 : 1)),
            total: steps.count,
            percent: isDone ? 100 : min(95, raw),
            current: current?.title
        )
    }

    public var text: String { L("步驟 \(step)/\(total) · 約 \(percent)%", "Step \(step)/\(total) · ~\(percent)%") }
}

extension Array where Element == PlanStep {
    var isFinished: Bool {
        let live = filter { $0.status != .deleted }
        return !live.isEmpty && live.allSatisfy { $0.status == .completed }
    }
}

public func formatDuration(_ interval: TimeInterval) -> String {
    let min = Int(max(0, interval) / 60)
    if min < 1 { return L("不到 1 分", "<1m") }
    if min < 60 { return L("\(min) 分", "\(min)m") }
    return L("\(min / 60) 時 \(min % 60) 分", "\(min / 60)h \(min % 60)m")
}
