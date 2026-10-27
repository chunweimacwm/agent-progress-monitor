import Foundation

/// 逐行解析一個 Codex rollout-*.jsonl，累積這個 session 的狀態。
/// 只取需要的欄位：cwd、一輪的開始／結束、計畫、提問；不保留對話內容。
public struct CodexParser {
    public private(set) var sessionId: String?
    public private(set) var cwd: String?
    /// nil：還沒讀到 session_meta；false：guardian 等子代理，不顯示
    public private(set) var isUserThread: Bool?
    public private(set) var plan: [PlanStep]?
    public private(set) var turnActive = false
    public private(set) var turnStartedAt: Date?
    public private(set) var finishedAt: Date?
    public private(set) var turnCompleted = false
    private var pendingQuestions: Set<String> = []
    /// 最近一次 token_count 裡的額度（5 小時＝primary、每週＝secondary）
    public private(set) var rateLimits: [UsageWindow] = []
    public private(set) var rateLimitsAt: Date?

    public var isWaiting: Bool { !pendingQuestions.isEmpty }

    public init() {}

    /// 需要完整解析的事件類型
    private static let wanted: Set<Substring> = ["task_started", "task_complete", "turn_aborted", "function_call", "custom_tool_call", "token_count"]

    /// 行首的 "payload":{"type":"…"}；session_meta 等沒有這個結構的回傳 nil
    static func payloadType(in head: Substring) -> Substring? {
        guard let r = head.range(of: #""payload":{"type":""#) else { return nil }
        let rest = head[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return rest[..<end]
    }

    static func callId(in head: Substring) -> String? {
        guard let r = head.range(of: #""call_id":""#) else { return nil }
        let rest = head[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    public mutating func feed(line: Substring) {
        // 先看行首的事件類型，大部分行（尤其是很大的工具輸出）不必 JSON 解析
        let head = line.prefix(400)
        if let type = Self.payloadType(in: head) {
            if type == "function_call_output" || type == "custom_tool_call_output" {
                // 只需要 call_id 來結束「等你回覆」，不解析整行
                if !pendingQuestions.isEmpty, let id = Self.callId(in: head) { pendingQuestions.remove(id) }
                return
            }
            guard Self.wanted.contains(type) else { return }
        } else if !head.contains("\"session_meta\"") {
            return
        }
        guard let data = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let p = o["payload"] as? [String: Any] else { return }
        let kind = o["type"] as? String
        let ptype = p["type"] as? String
        let at = (o["timestamp"] as? String).flatMap(Self.parseDate)

        switch (kind, ptype) {
        case ("session_meta", _):
            sessionId = (p["id"] as? String) ?? (p["session_id"] as? String)
            cwd = p["cwd"] as? String
            // 主對話 thread_source 是 "user"；自動審查是 "guardian_review"
            isUserThread = (p["thread_source"] as? String).map { $0 == "user" } ?? true
        case ("event_msg", "task_started"):
            turnActive = true
            turnStartedAt = at
            finishedAt = nil
            turnCompleted = false
            pendingQuestions = []
            if plan?.isFinished == true { plan = nil }
        case ("event_msg", "task_complete"), ("event_msg", "turn_aborted"):
            turnActive = false
            finishedAt = at
            turnCompleted = ptype == "task_complete"
            pendingQuestions = []
        case ("response_item", "function_call"):
            let name = p["name"] as? String
            if name == "update_plan", let args = p["arguments"] as? String {
                plan = Self.planFromJSON(args) ?? plan
            } else if name == "request_user_input_async", let id = p["call_id"] as? String {
                pendingQuestions.insert(id)
            }
        case ("event_msg", "token_count"):
            if let limits = p["rate_limits"] as? [String: Any] {
                let windows = ["primary", "secondary"].compactMap { key -> UsageWindow? in
                    guard let w = limits[key] as? [String: Any], let used = w["used_percent"] as? Double else { return nil }
                    let reset = (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                    return UsageWindow(kind: key, percentUsed: used, resetsAt: reset)
                }
                if !windows.isEmpty {
                    rateLimits = windows
                    rateLimitsAt = at
                }
            }
        case ("response_item", "function_call_output"):
            if let id = p["call_id"] as? String { pendingQuestions.remove(id) }
        case ("response_item", "custom_tool_call"):
            // 程式碼模式：exec 的 JavaScript 裡呼叫 tools.update_plan({plan:[...]})
            if let input = p["input"] as? String, input.contains("update_plan") {
                plan = Self.planFromScript(input) ?? plan
            }
        default:
            break
        }
    }

    /// 狀態判斷；回傳 nil 表示不顯示
    public func status(lastWrite: Date, now: Date) -> SessionStatus? {
        guard isUserThread == true else { return nil }
        let age = now.timeIntervalSince(lastWrite)
        if age > Thresholds.hideAfter { return nil }
        if turnActive {
            if age > Thresholds.codexStale { return .idle }
            return isWaiting ? .waiting : .working
        }
        if let f = finishedAt, now.timeIntervalSince(f) <= Thresholds.idleAfterDone { return .done }
        return .idle
    }

    // MARK: - 計畫解析

    static func planFromJSON(_ text: String) -> [PlanStep]? {
        guard let data = text.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = o["plan"] as? [[String: Any]] else { return nil }
        let steps = items.map { PlanStep(title: ($0["step"] as? String) ?? "", status: StepStatus(raw: $0["status"] as? String)) }
        return steps.isEmpty ? nil : steps
    }

    // key 可能沒加引號，字串可能用單或雙引號
    private static let stepFirst = try! NSRegularExpression(
        pattern: #"["']?step["']?\s*:\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')\s*,\s*["']?status["']?\s*:\s*["'](\w+)["']"#)
    private static let statusFirst = try! NSRegularExpression(
        pattern: #"["']?status["']?\s*:\s*["'](\w+)["']\s*,\s*["']?step["']?\s*:\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')"#)

    /// 從 exec 的 JavaScript 抽出最後一次 update_plan 的步驟
    static func planFromScript(_ script: String) -> [PlanStep]? {
        guard let r = script.range(of: "update_plan(", options: .backwards) else { return nil }
        let tail = String(script[r.upperBound...])
        let ns = tail as NSString
        let all = NSRange(location: 0, length: ns.length)
        var steps = stepFirst.matches(in: tail, range: all).map {
            PlanStep(title: unquote(ns.substring(with: $0.range(at: 1))), status: StepStatus(raw: ns.substring(with: $0.range(at: 2))))
        }
        if steps.isEmpty {
            steps = statusFirst.matches(in: tail, range: all).map {
                PlanStep(title: unquote(ns.substring(with: $0.range(at: 2))), status: StepStatus(raw: ns.substring(with: $0.range(at: 1))))
            }
        }
        return steps.isEmpty ? nil : steps
    }

    static func unquote(_ literal: String) -> String {
        if literal.hasPrefix("\""), let data = literal.data(using: .utf8),
           let s = try? JSONDecoder().decode(String.self, from: data) {
            return s
        }
        return String(literal.dropFirst().dropLast())
            .replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
