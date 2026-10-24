// 產生示意圖（示範資料，非真實紀錄）：浮窗同時有五個任務、四種狀態，下方是額度
// 用法：swift scripts/make-promo.swift <zh|en> <輸出.png> [icon.png]
import AppKit
import SwiftUI

let args = CommandLine.arguments
let zh = args.count > 1 ? args[1] != "en" : true
let out = args.count > 2 ? args[2] : "promo.png"
let iconPath = args.count > 3 ? args[3] : nil

func T(_ a: String, _ b: String) -> String { zh ? a : b }

enum S { case working, waiting, done, idle }

struct Row {
    var tool: String
    var title: String
    var status: S
    var step: (Int, Int)?
    var percent: Int?
    var current: String?
    var meta: String
}

let rows: [Row] = [
    Row(tool: "CC", title: T("KPI 追蹤", "KPI tracker"), status: .waiting, step: (2, 4), percent: 38,
        current: T("確認本月指標定義", "Confirm this month's metrics"), meta: T("dashboard · 已 6 分", "dashboard · 6m")),
    Row(tool: "CC", title: T("遊戲開發", "Game dev"), status: .working, step: (3, 5), percent: 50,
        current: T("實作關卡碰撞判定", "Implement level collisions"), meta: T("space-game · 已 12 分", "space-game · 12m")),
    Row(tool: "Codex", title: T("IG 管理", "IG manager"), status: .working, step: (1, 3), percent: 17,
        current: T("整理本週貼文排程", "Plan this week's posts"), meta: T("social · 已 3 分", "social · 3m")),
    Row(tool: "Codex", title: T("業績追蹤", "Sales report"), status: .done, step: (4, 4), percent: 100,
        current: nil, meta: T("sales · 2 分前", "sales · 2m ago")),
    Row(tool: "CC", title: "Debug", status: .idle, step: nil, percent: nil,
        current: nil, meta: T("api-server · 25 分前", "api-server · 25m ago")),
]

extension S {
    var label: String {
        switch self {
        case .working: T("工作中", "Working")
        case .waiting: T("等你", "Needs you")
        case .done: T("完成", "Done")
        case .idle: T("閒置", "Idle")
        }
    }

    var color: Color {
        switch self {
        case .working: .orange
        case .waiting: .yellow
        case .done: .green
        case .idle: .gray
        }
    }
}

struct Badge: View {
    let tool: String
    var body: some View {
        Text(tool)
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tool == "CC" ? Color.orange.opacity(0.3) : Color.blue.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// 額度區的標籤欄固定寬度，兩行的進度條才會對齊
struct UsageBadge: View {
    let tool: String
    var body: some View {
        Badge(tool: tool).frame(width: 60, alignment: .leading)
    }
}

struct Bar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 7
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(color).frame(width: g.size.width * value)
            }
        }
        .frame(height: height)
    }
}

struct RowView: View {
    let r: Row
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Badge(tool: r.tool)
                Text(r.title).font(.system(size: 19, weight: .semibold))
                Spacer()
                Text(r.status.label).font(.system(size: 15, weight: .medium)).foregroundStyle(r.status.color)
            }
            if let step = r.step, let p = r.percent {
                Bar(value: Double(p) / 100, color: r.status.color)
                Text((p == 100 ? T("步驟 \(step.0)/\(step.1) · 100%", "Step \(step.0)/\(step.1) · 100%") : T("步驟 \(step.0)/\(step.1) · 約 \(p)%", "Step \(step.0)/\(step.1) · ~\(p)%")) + (r.current.map { "  → \($0)" } ?? ""))
                    .font(.system(size: 14))
                    .lineLimit(1)
            } else {
                Text(T("沒有列計畫", "No plan")).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                Text(r.meta)
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
        }
    }
}

struct UsageLine: View {
    let label: String
    let left: Int
    let reset: String
    var body: some View {
        let color: Color = left <= 10 ? .red : left <= 30 ? .yellow : .green
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label).frame(width: 62, alignment: .leading)
                Text(T("剩 \(left)%", "\(left)% left")).foregroundStyle(color)
                Spacer()
                Text(reset).foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5))
            Bar(value: Double(100 - left) / 100, color: color, height: 4)
        }
    }
}

struct Panel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12)
                Spacer()
                Text(T("Agent 進度", "Agent Monitor")).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }
            .padding(.bottom, 16)
            Text(T("5 個 session · 3 個進行中", "5 sessions · 3 active"))
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .padding(.bottom, 14)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(rows.indices, id: \.self) { RowView(r: rows[$0]) }
            }
            Divider().overlay(Color.white.opacity(0.2)).padding(.vertical, 14)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    UsageBadge(tool: "CC")
                    VStack(spacing: 7) {
                        UsageLine(label: T("5 小時", "5-hour"), left: 72, reset: T("2時10分後重置", "resets in 2h 10m"))
                        UsageLine(label: T("每週", "Weekly"), left: 85, reset: T("5天3時後重置", "resets in 5d 3h"))
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    UsageBadge(tool: "Codex")
                    VStack(spacing: 7) {
                        UsageLine(label: T("5 小時", "5-hour"), left: 64, reset: T("1時42分後重置", "resets in 1h 42m"))
                        UsageLine(label: T("每週", "Weekly"), left: 88, reset: T("6天13時後重置", "resets in 6d 13h"))
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 470)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(white: 0.11).opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        }
        .environment(\.colorScheme, .dark)
    }
}

struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.28), Color(red: 0.28, green: 0.10, blue: 0.30), Color(red: 0.05, green: 0.06, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.orange.opacity(0.35)).frame(width: 520).blur(radius: 120).offset(x: 280, y: -260)
            Circle().fill(Color.blue.opacity(0.45)).frame(width: 600).blur(radius: 140).offset(x: -300, y: 330)
        }
    }
}

struct Poster: View {
    let icon: NSImage?
    var body: some View {
        ZStack {
            Wallpaper()
            VStack(spacing: 26) {
                HStack(spacing: 16) {
                    if let icon { Image(nsImage: icon).resizable().frame(width: 88, height: 88) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("Agent 進度", "Agent Monitor")).font(.system(size: 44, weight: .bold))
                        Text(T("Claude Code ＋ Codex 同時跑，一眼看進度", "Claude Code + Codex side by side, at a glance"))
                            .font(.system(size: 21, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                Panel()
                Text(T("macOS 浮窗 · 開源免費", "Floating macOS panel · free & open source"))
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            // 讓內容填滿 4:5 版面
            .scaleEffect(1.3)
        }
        .frame(width: 1080, height: 1350)
    }
}

let icon = iconPath.flatMap { NSImage(contentsOfFile: $0) }
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Poster(icon: icon))
    renderer.scale = 1
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("render failed"); exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: out))
    print("已輸出 \(out)")
}
