import AppKit

/// 0.1.1 以前的 bundle ID 是 com.willis.agentmonitor。通知中心在第一則通知時記住了「沒有圖示」，
/// 換 bundle ID 才能重新登記，這裡把舊設定搬過來。
enum LegacyMigration {
    static let legacyID = "com.willis.agentmonitor"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromLegacy") else { return }
        defaults.set(true, forKey: "migratedFromLegacy")
        guard let old = defaults.persistentDomain(forName: legacyID) else { return }
        for (key, value) in old where key != "loginItemInitialized" && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}

/// 同一個 app 只跑一份（換 bundle ID 後，舊的登入項目也可能再開一次）
enum SingleInstance {
    static func isAnotherRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { $0.processIdentifier != me }
    }
}
