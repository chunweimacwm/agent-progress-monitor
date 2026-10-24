import Foundation
import Testing
@testable import AgentCore

// 樣本照 2026-10-24 本機 Codex 紀錄的格式縮寫
private let meta = #"{"timestamp":"2026-10-24T06:06:18.896Z","type":"session_meta","payload":{"id":"01a1","cwd":"/Users/me/projects/demo","thread_source":"user"}}"#
private let started = #"{"timestamp":"2026-10-24T06:06:20.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"#
private let completed = #"{"timestamp":"2026-10-24T06:06:50.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1"}}"#
private let execPlan = #"{"timestamp":"2026-10-24T06:06:30.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"text(await tools.update_plan({plan:[{step:\"確認可用\",status:\"completed\"},{step:\"第二步 \\\"引號\\\"\",status:\"in_progress\"},{step:'第三步',status:'pending'}]}));\n"}}"#
private let jsonPlan = #"{"timestamp":"2026-07-24T08:00:00.000Z","type":"response_item","payload":{"type":"function_call","name":"update_plan","arguments":"{\"plan\":[{\"step\":\"A\",\"status\":\"completed\"},{\"step\":\"B\",\"status\":\"pending\"}]}"}}"#

private func parse(_ lines: [String]) -> CodexParser {
    var p = CodexParser()
    for l in lines { p.feed(line: Substring(l)) }
    return p
}

@Test func 程式碼模式的計畫() {
    AppLanguage.setting = .zh
    let p = parse([meta, started, execPlan])
    #expect(p.plan?.map(\.title) == ["確認可用", "第二步 \"引號\"", "第三步"])
    #expect(p.plan?.map(\.status) == [.completed, .inProgress, .pending])
    #expect(PlanProgress.estimate(p.plan, isDone: false) == PlanProgress(step: 2, total: 3, percent: 50, current: "第二步 \"引號\""))
}

@Test func 舊版function_call的計畫() {
    AppLanguage.setting = .zh
    let p = parse([meta, jsonPlan])
    #expect(p.plan?.map(\.status) == [.completed, .pending])
}

@Test func 一輪開始與結束() {
    AppLanguage.setting = .zh
    let start = CodexParser.parseDate("2026-10-24T06:06:20.000Z")!
    let working = parse([meta, started, execPlan])
    #expect(working.status(lastWrite: start, now: start.addingTimeInterval(5)) == .working)
    #expect(working.status(lastWrite: start, now: start.addingTimeInterval(11 * 60)) == .idle)

    let done = parse([meta, started, execPlan, completed])
    let end = CodexParser.parseDate("2026-10-24T06:06:50.000Z")!
    #expect(done.status(lastWrite: end, now: end.addingTimeInterval(5)) == .done)
    #expect(done.status(lastWrite: end, now: end.addingTimeInterval(11 * 60)) == .idle)
    #expect(done.turnCompleted)
    #expect(!working.turnCompleted)
}

@Test func 等你與子代理() {
    AppLanguage.setting = .zh
    let ask = #"{"timestamp":"2026-10-24T06:06:40.000Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input_async","call_id":"c1","arguments":"{}"}}"#
    let answer = #"{"timestamp":"2026-10-24T06:06:45.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"c1","output":"ok"}}"#
    let now = Date()
    #expect(parse([meta, started, ask]).status(lastWrite: now, now: now) == .waiting)
    #expect(parse([meta, started, ask, answer]).status(lastWrite: now, now: now) == .working)

    let guardian = meta.replacingOccurrences(of: #""thread_source":"user""#, with: #""thread_source":"guardian_review""#)
    #expect(parse([guardian, started]).status(lastWrite: now, now: now) == nil)
}

@Test func 新的一輪清掉已完成的計畫() {
    AppLanguage.setting = .zh
    let allDone = #"{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"tools.update_plan({plan:[{step:\"A\",status:\"completed\"}]})"}}"#
    #expect(parse([meta, started, allDone, completed, started]).plan == nil)
}

@Test func 額度取自token_count() {
    AppLanguage.setting = .zh
    let tc = #"{"timestamp":"2026-10-24T06:40:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"primary":{"used_percent":29.0,"window_minutes":300,"resets_at":1792835029},"secondary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1793394222}}}}"#
    let p = parse([meta, tc])
    #expect(p.rateLimits.map(\.label) == ["5 小時", "每週"])
    #expect(p.rateLimits.first?.percentUsed == 29)
    #expect(p.rateLimits.first?.percentLeft == 71)
    // 重置時間過了就歸零
    let w = p.rateLimits[0]
    #expect(w.current(now: w.resetsAt!.addingTimeInterval(1)).percentUsed == 0)
}

@Test func Claude用量檔() {
    AppLanguage.setting = .zh
    let json = #"{"v":1,"tool":"claude-code","updatedAt":1792820000000,"windows":[{"kind":"five_hour","percentUsed":23.5,"resetsAt":"2026-10-24T09:00:00.000Z"},{"kind":"seven_day","percentUsed":7,"resetsAt":null}]}"#
    let u = ClaudeUsageReader.parse(Data(json.utf8))
    #expect(u?.windows.map(\.label) == ["5 小時", "每週"])
    #expect(u?.windows.first?.resetsAt != nil)
    #expect(u?.windows.last?.resetsAt == nil)
}
