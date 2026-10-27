import Foundation

/// 監看 ~/.codex/sessions 下最近的 rollout 檔，只讀新增的部分。
/// 只碰 sessions/ 與 session_index.jsonl，不讀 auth.json 或任何設定檔。
public final class CodexScanner {
    private struct Tracked {
        var parser = CodexParser()
        var offset: UInt64 = 0
        var remainder = Data()
        var lastWrite = Date.distantPast
    }

    private let root: URL
    private let indexFile: URL
    private var tracked: [URL: Tracked] = [:]
    private var titles: [String: String] = [:]
    private var indexStamp: Date?
    private var lastDiscovery = Date.distantPast
    static let discoveryInterval: TimeInterval = 30

    public init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        root = codexHome.appendingPathComponent("sessions")
        indexFile = codexHome.appendingPathComponent("session_index.jsonl")
    }

    /// 追蹤中的檔案裡最新的一份額度
    public var latestUsage: AgentUsage? {
        tracked.values
            .compactMap { t -> AgentUsage? in
                guard let at = t.parser.rateLimitsAt, !t.parser.rateLimits.isEmpty else { return nil }
                return AgentUsage(tool: .codex, windows: t.parser.rateLimits, observedAt: at)
            }
            .max { $0.observedAt < $1.observedAt }
    }

    public func scan(now: Date = Date()) -> [AgentSession] {
        refreshTitles()
        let recent = recentFiles(now: now)
        // 太久沒動的檔案不再追蹤，釋放記憶體
        tracked = tracked.filter { recent[$0.key] != nil }
        for (url, mtime) in recent {
            var t = tracked[url] ?? Tracked()
            if mtime != t.lastWrite {
                readNew(url, into: &t)
                t.lastWrite = mtime
            }
            tracked[url] = t
        }
        return tracked.compactMap { _, t in
            let p = t.parser
            guard p.isUserThread == true, let id = p.sessionId, let status = p.status(lastWrite: t.lastWrite, now: now) else { return nil }
            return AgentSession(
                tool: .codex,
                sessionId: id,
                project: p.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Codex",
                title: titles[id],
                status: status,
                plan: p.plan,
                turnStartedAt: p.turnStartedAt,
                finishedAt: p.finishedAt,
                updatedAt: t.lastWrite,
                // Codex 桌面版（在 ChatGPT.app 裡）的深層連結
                jumpURL: URL(string: "codex://threads/\(id)"),
                turnCompleted: p.turnCompleted
            )
        }
    }

    /// 6 小時內寫過的檔案。
    /// Codex 把對話寫在「開始那天」的資料夾，之後接著聊也一直寫回那裡，所以不能只看今天和昨天：
    /// 每 30 秒掃一次全部日期資料夾找最近寫過的檔，其餘時間只看已知的檔和今天／昨天（新對話才會即時出現）。
    private func recentFiles(now: Date) -> [URL: Date] {
        let fm = FileManager.default
        var urls = Set(tracked.keys)
        if now.timeIntervalSince(lastDiscovery) >= Self.discoveryInterval {
            lastDiscovery = now
            let all = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            while let f = all?.nextObject() as? URL {
                if Self.isRollout(f) { urls.insert(f) }
            }
        } else {
            let cal = Calendar.current
            for back in 0...1 {
                guard let day = cal.date(byAdding: .day, value: -back, to: now) else { continue }
                let c = cal.dateComponents([.year, .month, .day], from: day)
                let dir = root.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
                for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where Self.isRollout(f) {
                    urls.insert(f)
                }
            }
        }
        var out: [URL: Date] = [:]
        for f in urls {
            guard let m = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(m) <= Thresholds.hideAfter else { continue }
            out[f] = m
        }
        return out
    }

    private static func isRollout(_ f: URL) -> Bool {
        f.lastPathComponent.hasPrefix("rollout-") && f.pathExtension == "jsonl"
    }

    /// 一次最多讀 4MB：紀錄檔可能上百 MB，整份讀進來會讓記憶體瞬間暴增
    static let chunkSize = 4 << 20

    private func readNew(_ url: URL, into t: inout Tracked) {
        guard let h = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? h.close() }
        guard let end = try? h.seekToEnd() else { return }
        if end < t.offset { t = Tracked() } // 檔案被截斷或換掉，重讀
        guard end > t.offset else { return }
        try? h.seek(toOffset: t.offset)
        while t.offset < end {
            let more = autoreleasepool { () -> Bool in
                guard let chunk = try? h.read(upToCount: min(Self.chunkSize, Int(end - t.offset))), !chunk.isEmpty else { return false }
                t.offset += UInt64(chunk.count)
                var buf = t.remainder + chunk
                // 最後一行可能還沒寫完，留到下一段
                guard let lastNewline = buf.lastIndex(of: 0x0A) else {
                    t.remainder = buf
                    return true
                }
                t.remainder = Data(buf[(lastNewline + 1)...])
                buf = buf[..<lastNewline]
                let text = String(decoding: buf, as: UTF8.self)
                for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                    t.parser.feed(line: line)
                }
                return true
            }
            if !more { break }
        }
    }

    /// session_index.jsonl：每行 {id, thread_name}，同一個 id 以最後一行為準
    private func refreshTitles() {
        guard let m = try? indexFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              m != indexStamp, let data = try? Data(contentsOf: indexFile) else { return }
        indexStamp = m
        var next: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = o["id"] as? String, let name = o["thread_name"] as? String, !name.isEmpty else { continue }
            next[id] = name
        }
        titles = next
    }
}
