import AgentCore
import AppKit
import SwiftUI

/// 浮窗不搶焦點；第一下點擊就要生效，不用先點一下啟用視窗
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MonitorModel()
    private let notifier = Notifier()
    private var alertsItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var usageItem: NSMenuItem!
    private var claudeSoundItem: NSMenuItem!
    private var glassMenu: NSMenu!
    private var hosting: NSView!
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = makePanel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: L("Agent 進度", "Agent Monitor"))
        statusItem.menu = makeMenu()
        model.onChange = { [weak self] in self?.updateStatusTitle() }
        model.onAlerts = { [weak self] in self?.notifier.post($0) }
        notifier.start()
        LoginItem.enableOnFirstInstalledLaunch()
        refreshMenuState()
        model.start()
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 360),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = L("Agent 進度", "Agent Monitor")
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        // 透明底，讓玻璃材質透出桌面
        p.isOpaque = false
        p.backgroundColor = .clear
        p.appearance = NSAppearance(named: .darkAqua)
        hosting = ClickThroughHostingView(rootView: MonitorView(model: model))
        p.contentView = NSView(frame: p.contentLayoutRect)
        PanelBackdrop.apply(model.glass, to: p, content: hosting)
        // 記住位置與大小；第一次放在右上角
        if !p.setFrameUsingName("AgentMonitorPanel"), let screen = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: screen.maxX - 340, y: screen.maxY - 380))
        }
        p.setFrameAutosaveName("AgentMonitorPanel")
        return p
    }

    /// 語言切換時整個選單重建，所以標題都在這裡用 L() 取
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: L("顯示／隱藏浮窗", "Show / Hide Panel"), action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("精簡模式", "Compact Mode"), action: #selector(toggleCompact), keyEquivalent: "").target = self
        let glass = NSMenu()
        for level in GlassLevel.allCases {
            let item = glass.addItem(withTitle: level.title, action: #selector(setGlass(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = level.rawValue
        }
        glassMenu = glass
        menu.addItem(withTitle: L("透明度", "Transparency"), action: nil, keyEquivalent: "").submenu = glass
        let lang = NSMenu()
        for language in AppLanguage.allCases {
            let item = lang.addItem(withTitle: language.title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = AppLanguage.setting == language ? .on : .off
        }
        menu.addItem(withTitle: L("語言", "Language"), action: nil, keyEquivalent: "").submenu = lang
        menu.addItem(.separator())
        usageItem = menu.addItem(withTitle: L("顯示額度", "Show Usage Limits"), action: #selector(toggleUsage), keyEquivalent: "")
        usageItem.target = self
        alertsItem = menu.addItem(withTitle: L("完成／等你提示", "Done / Needs-you Alerts"), action: #selector(toggleAlerts), keyEquivalent: "")
        alertsItem.target = self
        claudeSoundItem = menu.addItem(withTitle: L("Claude Code 完成也響", "Sound for Claude Code Done"), action: #selector(toggleClaudeSound), keyEquivalent: "")
        claudeSoundItem.target = self
        claudeSoundItem.toolTip = L("已有其他完成提示音（例如 Claude Code hook）時可關掉，避免重複", "Turn off if another tool already chimes when Claude Code finishes")
        loginItem = menu.addItem(withTitle: L("開機自動啟動", "Launch at Login"), action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("結束 Agent 進度", "Quit Agent Monitor"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        AppLanguage.setting = language
        statusItem.menu = makeMenu()
        refreshMenuState()
        panel.title = L("Agent 進度", "Agent Monitor")
        updateStatusTitle()
        model.languageChanged()
    }

    @objc private func toggleClaudeSound() {
        notifier.claudeDoneSound.toggle()
        refreshMenuState()
    }

    @objc private func togglePanel() {
        panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }

    @objc private func toggleCompact() {
        model.compact.toggle()
    }

    @objc private func setGlass(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let level = GlassLevel(rawValue: raw) else { return }
        model.glass = level
        PanelBackdrop.apply(level, to: panel, content: hosting)
        refreshMenuState()
    }

    @objc private func toggleUsage() {
        model.showUsage.toggle()
        refreshMenuState()
    }

    @objc private func toggleAlerts() {
        notifier.isEnabled.toggle()
        refreshMenuState()
    }

    @objc private func toggleLoginItem() {
        LoginItem.set(!LoginItem.isEnabled)
        refreshMenuState()
    }

    private func refreshMenuState() {
        for item in glassMenu.items {
            item.state = (item.representedObject as? String) == model.glass.rawValue ? .on : .off
        }
        usageItem.state = model.showUsage ? .on : .off
        alertsItem.state = notifier.isEnabled ? .on : .off
        claudeSoundItem.state = notifier.claudeDoneSound ? .on : .off
        claudeSoundItem.isEnabled = notifier.isEnabled
        loginItem.state = LoginItem.isEnabled ? .on : .off
        // 從 dist/ 或 .build/ 執行時不讓它註冊登入項目
        loginItem.isEnabled = LoginItem.isInstalled
        loginItem.toolTip = LoginItem.isInstalled ? nil : L("安裝到 /Applications 後才能設定", "Install to /Applications first")
    }

    /// 選單列顯示進行中與等你的數量
    private func updateStatusTitle() {
        let busy = model.sessions.filter { $0.status == .working }.count
        let waiting = model.sessions.filter { $0.status == .waiting }.count
        var parts: [String] = []
        if busy > 0 { parts.append("\(busy)") }
        if waiting > 0 { parts.append(L("等", "wait ") + "\(waiting)") }
        statusItem.button?.title = parts.isEmpty ? "" : " " + parts.joined(separator: " · ")
    }
}
