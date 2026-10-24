import Foundation

/// 舊版 mod 寫的狀態檔沒有 title、hostSessionId 時的後備查詢，做法和 mod 的 pane 相同：
/// - 標題：對話紀錄裡最後一行 custom-title（只取標題，不讀其他內容）
/// - 桌面版內部 id：桌面版日誌的「Mapping internal session local_x to CLI session y」
public final class ClaudeMetaLookup {
    private let projects: URL
    private let logs: [URL]
    private var titles: [String: (title: String?, at: Date)] = [:]
    private var hostIds: [String: String] = [:]
    private var logsReadAt = Date.distantPast
    private static let ttl: TimeInterval = 60

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        projects = home.appendingPathComponent(".claude/projects")
        let logDir = home.appendingPathComponent("Library/Logs/Claude")
        logs = [logDir.appendingPathComponent("main1.log"), logDir.appendingPathComponent("main.log")]
    }

    public func title(for sessionId: String, now: Date) -> String? {
        if let hit = titles[sessionId], now.timeIntervalSince(hit.at) < Self.ttl { return hit.title }
        let found = transcript(for: sessionId).flatMap(Self.lastTitle)
        titles[sessionId] = (found, now)
        return found
    }

    public func hostSessionId(for sessionId: String, now: Date) -> String? {
        if let id = hostIds[sessionId] { return id }
        // 對應關係不會變；缺的時候才重讀日誌，最多一分鐘一次
        guard now.timeIntervalSince(logsReadAt) >= Self.ttl else { return nil }
        logsReadAt = now
        for log in logs {
            guard let data = try? Data(contentsOf: log) else { continue }
            for (cli, host) in Self.mappings(in: String(decoding: data, as: UTF8.self)) { hostIds[cli] = host }
        }
        return hostIds[sessionId]
    }

    private func transcript(for sessionId: String) -> URL? {
        guard sessionId.range(of: #"^[0-9a-f-]+$"#, options: .regularExpression) != nil else { return nil }
        let dirs = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return dirs.lazy.map { $0.appendingPathComponent("\(sessionId).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 先看檔尾 512KB（標題會重複寫入），找不到再讀整份
    static func lastTitle(in file: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let tailStart = size > 512_000 ? size - 512_000 : 0
        try? h.seek(toOffset: tailStart)
        if let tail = try? h.readToEnd(), let t = lastTitle(text: String(decoding: tail, as: UTF8.self)) { return t }
        guard tailStart > 0, let all = try? Data(contentsOf: file) else { return nil }
        return lastTitle(text: String(decoding: all, as: UTF8.self))
    }

    static func lastTitle(text: String) -> String? {
        for line in text.split(separator: "\n").reversed() where line.contains("\"custom-title\"") {
            if let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               o["type"] as? String == "custom-title",
               let t = (o["customTitle"] as? String)?.trimmingCharacters(in: .whitespaces), !t.isEmpty {
                return t
            }
        }
        return nil
    }

    private static let mapping = try! NSRegularExpression(
        pattern: #"Mapping internal session (local_[A-Za-z0-9-]{1,64}) to CLI session ([0-9a-f-]+)"#)

    static func mappings(in text: String) -> [(String, String)] {
        let ns = text as NSString
        return mapping.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            (ns.substring(with: $0.range(at: 2)), ns.substring(with: $0.range(at: 1)))
        }
    }
}
