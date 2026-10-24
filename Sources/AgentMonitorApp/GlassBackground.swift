import AgentCore
import AppKit
import SwiftUI

/// 浮窗的透明度。很淡～深用系統的 Liquid Glass（NSGlassEffectView），不透明維持 HUD 模糊＋深灰
enum GlassLevel: String, CaseIterable {
    case solid, dark, medium, light, clear

    var title: String {
        switch self {
        case .solid: L("不透明", "Solid")
        case .dark: L("深", "Dark")
        case .medium: L("中", "Medium")
        case .light: L("淡", "Light")
        case .clear: L("很淡（像 Dock）", "Clear (like the Dock)")
        }
    }

    /// 疊在玻璃上的深灰濃度
    var tint: CGFloat {
        switch self {
        case .solid: 0.92
        case .dark: 0.6
        case .medium: 0.38
        case .light: 0.18
        case .clear: 0
        }
    }

    /// 淡與很淡用清透款（Dock 那種），其餘用一般款
    var usesClearGlass: Bool { self == .clear || self == .light }
}

/// 依透明度換掉浮窗的底層 view，SwiftUI 內容放在上面
enum PanelBackdrop {
    static func apply(_ level: GlassLevel, to panel: NSPanel, content: NSView) {
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width, .height]

        let root: NSView
        if level != .solid, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = level.usesClearGlass ? .clear : .regular
            glass.cornerRadius = 18
            glass.tintColor = level.tint > 0 ? NSColor(white: 0.08, alpha: level.tint) : nil
            glass.contentView = content
            root = glass
        } else {
            // 不透明，或系統早於 macOS 26 時的替代做法
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            // 浮窗不搶焦點，永遠是「非作用中」；不設 active 的話模糊會消失變成灰底
            blur.state = .active
            let shade = NSView()
            shade.wantsLayer = true
            shade.layer?.backgroundColor = NSColor(white: 0.09, alpha: level == .solid ? level.tint : max(level.tint, 0.3)).cgColor
            shade.autoresizingMask = [.width, .height]
            blur.addSubview(shade)
            blur.addSubview(content)
            root = blur
        }
        let frame = panel.contentView?.frame ?? panel.contentLayoutRect
        panel.contentView = root
        root.frame = frame
        for sub in root.subviews { sub.frame = root.bounds }
    }
}
