import Foundation
import Testing
@testable import AgentCore

private func record(status: String, updatedAt: Double, finishedAt: Double? = nil, host: String? = "local_abc-1") -> Data {
    var o: [String: Any] = [
        "v": 1, "tool": "claude-code", "sessionId": "s1", "project": "p", "title": "MODs",
        "status": status, "updatedAt": updatedAt, "blocked": false,
        "plan": [["id": "1", "title": "A", "status": "completed"], ["id": "2", "title": "B", "status": "in_progress"]],
    ]
    if let finishedAt { o["finishedAt"] = finishedAt }
    if let host { o["hostSessionId"] = host }
    return try! JSONSerialization.data(withJSONObject: o)
}

@Test func 後備查詢的解析() {
    AppLanguage.setting = .zh
    let log = "2026-10-24 [info] Mapping internal session local_c452-bb to CLI session 6c1f-aa\nother\n"
    #expect(ClaudeMetaLookup.mappings(in: log).first?.0 == "6c1f-aa")
    #expect(ClaudeMetaLookup.mappings(in: log).first?.1 == "local_c452-bb")
    let transcript = #"{"type":"custom-title","customTitle":"舊標題"}"# + "\n" + #"{"type":"custom-title","customTitle":"實作計畫"}"# + "\n"
    #expect(ClaudeMetaLookup.lastTitle(text: transcript) == "實作計畫")
}

@Test func 狀態檔判斷與mod一致() {
    AppLanguage.setting = .zh
    let now = Date(timeIntervalSince1970: 1_000_000)
    let ms = now.timeIntervalSince1970 * 1000
    let s = ClaudeStatusReader.session(from: record(status: "working", updatedAt: ms - 1000), now: now)
    #expect(s?.status == .working)
    #expect(s?.displayName == "MODs")
    #expect(s?.progress?.text == "步驟 2/2 · 約 75%")
    #expect(s?.jumpURL?.absoluteString == "claude://code/continue?session=local_abc-1&source=spotlight")

    #expect(ClaudeStatusReader.session(from: record(status: "working", updatedAt: ms - 200_000), now: now)?.status == .idle)
    #expect(ClaudeStatusReader.session(from: record(status: "done", updatedAt: ms, finishedAt: ms - 11 * 60_000), now: now)?.status == .idle)
    #expect(ClaudeStatusReader.session(from: record(status: "ended", updatedAt: ms), now: now) == nil)
    #expect(ClaudeStatusReader.session(from: record(status: "done", updatedAt: ms, host: "bad id"), now: now)?.jumpURL == nil)
}

@Test func 英文介面字串() {
    AppLanguage.setting = .en
    defer { AppLanguage.setting = .zh }
    #expect(PlanProgress(step: 3, total: 5, percent: 50, current: nil).text == "Step 3/5 · ~50%")
    #expect(SessionStatus.waiting.label == "Needs you")
    #expect(UsageWindow(kind: "five_hour", percentUsed: 10, resetsAt: nil).label == "5-hour")
}
