import AgentCore
import AppKit
import UserNotifications

/// 完成／等你的提示。
/// 完成與「等你」的提示。Claude Code 完成的聲音可另外關掉（已有其他提示音時避免重複）。
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let enabledKey = "alertsEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    static let claudeSoundKey = "claudeDoneSound"

    var claudeDoneSound: Bool {
        get { UserDefaults.standard.object(forKey: Self.claudeSoundKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.claudeSoundKey) }
    }

    private let center = UNUserNotificationCenter.current()

    func start() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ alerts: [Alert]) {
        guard isEnabled else { return }
        for alert in alerts {
            let s = alert.session
            let content = UNMutableNotificationContent()
            content.title = alert.kind == .done ? L("\(s.tool.rawValue) 完成", "\(s.tool.rawValue) done") : L("\(s.tool.rawValue) 等你回覆", "\(s.tool.rawValue) needs you")
            content.body = s.displayName + (s.progress.map { " · \($0.text)" } ?? "")
            if let url = s.jumpURL { content.userInfo = ["url": url.absoluteString] }
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))

            let silent = alert.kind == .done && s.tool == .claudeCode && !claudeDoneSound
            if !silent { NSSound(named: alert.kind == .done ? "Glass" : "Ping")?.play() }
        }
    }

    // 浮窗在前景時也顯示橫幅（聲音由上面的 NSSound 負責，避免重複）
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    // 點通知直接跳到該對話串
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
