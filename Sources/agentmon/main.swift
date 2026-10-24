import AgentCore
import Foundation

// 用法：agentmon（印一次）／agentmon --watch（每 2 秒重印）
let monitor = Monitor()
let watch = CommandLine.arguments.contains("--watch")

func render() {
    let now = Date()
    let sessions = monitor.poll(now: now)
    var out = L("\(sessions.count) 個 session  ", "\(sessions.count) sessions  ") + "\(DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .medium))\n"
    for s in sessions {
        let time: String
        switch s.status {
        case .working, .waiting: time = s.turnStartedAt.map { L("已 ", "") + formatDuration(now.timeIntervalSince($0)) } ?? ""
        default: time = s.finishedAt.map { formatDuration(now.timeIntervalSince($0)) + L("前", " ago") } ?? ""
        }
        let progress = s.progress.map { $0.text + ($0.current.map { "  → \($0)" } ?? "") } ?? L("（沒有計畫）", "(no plan)")
        out += "[\(s.tool.rawValue)] \(s.status.label)  \(s.displayName)  ·  \(s.project)  ·  \(time)\n      \(progress)\n"
    }
    for u in monitor.usage(now: now) {
        let parts = u.windows.map { w in
            "\(w.label) " + L("用 \(Int(w.percentUsed))%／剩 \(Int(w.percentLeft))%", "\(Int(w.percentUsed))% used / \(Int(w.percentLeft))% left") + (w.resetsAt.map { " · " + formatCountdown(to: $0, now: now) } ?? "")
        }
        out += L("額度", "Usage") + " [\(u.tool.rawValue)] " + parts.joined(separator: "  |  ") + "\n"
    }
    print(watch ? "\u{1B}[2J\u{1B}[H" + out : out, terminator: "")
}

render()
while watch {
    Thread.sleep(forTimeInterval: 2)
    render()
}
