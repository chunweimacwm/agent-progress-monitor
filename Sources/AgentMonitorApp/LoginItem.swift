import Foundation
import ServiceManagement

/// 開機自動啟動：用系統的登入項目（系統設定 › 一般 › 登入項目 看得到、也能在那裡關）
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// 只有從 /Applications 執行時才註冊，避免把 dist/ 或 .build/ 裡的暫時版本登記成登入項目
    static var isInstalled: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            NSLog("AgentMonitor login item: \(error)")
            return false
        }
    }

    /// 第一次從 /Applications 啟動時預設打開；之後尊重使用者在選單或系統設定的選擇
    static func enableOnFirstInstalledLaunch() {
        let key = "loginItemInitialized"
        guard isInstalled, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if !isEnabled { set(true) }
    }
}
