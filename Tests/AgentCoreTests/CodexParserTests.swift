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

@Test func 接續舊對話也追蹤得到() throws {
    AppLanguage.setting = .zh
    // 對話三天前開始，今天又接著聊：檔案在舊日期資料夾，但最近才寫入
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-scan-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let dir = home.appendingPathComponent("sessions/2026/10/10")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("rollout-2026-10-10T12-45-45-01a1.jsonl")
    try (meta + "\n" + started + "\n").write(to: file, atomically: true, encoding: .utf8)
    let sessions = CodexScanner(codexHome: home).scan(now: Date())
    #expect(sessions.map(\.sessionId) == ["01a1"])
    #expect(sessions.first?.status == .working)
}

@Test func 大檔分段讀取結果不變() throws {
    AppLanguage.setting = .zh
    // 中間塞超過一段（4MB）的雜訊行，確認跨段的行與結尾狀態仍正確
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-big-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let dir = home.appendingPathComponent("sessions/2026/10/10")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let filler = #"{"type":"response_item","payload":{"type":"message","content":""# + String(repeating: "x", count: 1_000) + #""}}"#
    let body = [meta, started, execPlan] + Array(repeating: filler, count: 6_000) + [completed]
    try (body.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("rollout-big.jsonl"), atomically: true, encoding: .utf8)
    let s = CodexScanner(codexHome: home).scan(now: Date()).first
    #expect(s?.plan?.count == 3)
    #expect(s?.turnCompleted == true)
}

@Test func 檔案後續寫入的完成也讀得到() throws {
    AppLanguage.setting = .zh
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-append-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let dir = home.appendingPathComponent("sessions/2026/10/10")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("rollout-append.jsonl")
    try (meta + "\n" + started + "\n" + execPlan + "\n").write(to: file, atomically: true, encoding: .utf8)
    let scanner = CodexScanner(codexHome: home)
    #expect(scanner.scan(now: Date()).first?.status == .working)

    // 先寫半行、再補完（模擬讀到一半的行）
    let h = try FileHandle(forWritingTo: file)
    try h.seekToEnd()
    let line = Data((completed + "\n").utf8)
    try h.write(contentsOf: line.prefix(20))
    _ = scanner.scan(now: Date())
    try h.write(contentsOf: line.dropFirst(20))
    try h.close()
    let s = scanner.scan(now: Date()).first
    #expect(s?.turnCompleted == true)
}

@Test func 之後才寫入的標題也讀得到() throws {
    AppLanguage.setting = .zh
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-title-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let dir = home.appendingPathComponent("sessions/2026/10/10")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try (meta + "\n" + started + "\n").write(to: dir.appendingPathComponent("rollout-t.jsonl"), atomically: true, encoding: .utf8)
    let index = home.appendingPathComponent("session_index.jsonl")
    try "".write(to: index, atomically: true, encoding: .utf8)
    let scanner = CodexScanner(codexHome: home)
    #expect(scanner.scan(now: Date()).first?.title == nil)
    Thread.sleep(forTimeInterval: 0.05)
    try #"{"id":"01a1","thread_name":"規劃下一步"}"#.appending("\n").write(to: index, atomically: false, encoding: .utf8)
    #expect(scanner.scan(now: Date()).first?.title == "規劃下一步")
}
