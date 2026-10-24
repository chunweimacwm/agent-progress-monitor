import Foundation
import Testing
@testable import AgentCore

private func session(_ status: SessionStatus, start: TimeInterval = 0, end: TimeInterval? = nil) -> AgentSession {
    AgentSession(
        tool: .codex, sessionId: "s1", project: "p", title: nil, status: status, plan: nil,
        turnStartedAt: Date(timeIntervalSince1970: start), finishedAt: end.map { Date(timeIntervalSince1970: $0) },
        updatedAt: Date(), jumpURL: nil
    )
}

@Test func 第一次不提示_之後轉換才提示() {
    var d = TransitionDetector()
    #expect(d.update([session(.done, end: 100)]).isEmpty)
    #expect(d.update([session(.working, start: 200)]).isEmpty)
    #expect(d.update([session(.done, start: 200, end: 260)]).map(\.kind) == [.done])
}

@Test func 太短的一輪不提示完成() {
    var d = TransitionDetector()
    _ = d.update([session(.working, start: 0)])
    #expect(d.update([session(.done, start: 0, end: 10)]).isEmpty)
}

@Test func 等你只提示一次() {
    var d = TransitionDetector()
    _ = d.update([session(.working, start: 0)])
    #expect(d.update([session(.waiting, start: 0)]).map(\.kind) == [.waiting])
    _ = d.update([session(.working, start: 0)])
    #expect(d.update([session(.waiting, start: 0)]).isEmpty)
}

@Test func 閒置轉完成不提示() {
    var d = TransitionDetector()
    _ = d.update([session(.idle, start: 0)])
    #expect(d.update([session(.done, start: 0, end: 100)]).isEmpty)
}
