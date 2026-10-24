import AgentCore
import AppKit
import SwiftUI

struct MonitorView: View {
    @ObservedObject var model: MonitorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.sessions.isEmpty {
                Text(L("目前沒有進行中的 agent", "No active agents"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: model.compact ? 4 : 10) {
                        ForEach(model.sessions) { s in
                            SessionRow(session: s, now: model.now, compact: model.compact)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        // 額度固定在最下方
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.showUsage, !model.usage.isEmpty {
                UsageSection(usage: model.usage, now: model.now, compact: model.compact)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
        .frame(minWidth: 240, minHeight: 120)
        // 底層玻璃由 PanelBackdrop 提供；清透段位在文字後面加陰影，背景花也讀得到
        .modifier(Readable(level: model.glass))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        let busy = model.sessions.filter { $0.status == .working || $0.status == .waiting }.count
        return HStack {
            Text(L("\(model.sessions.count) 個 session", "\(model.sessions.count) sessions") + (busy > 0 ? L(" · \(busy) 個進行中", " · \(busy) active") : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.compact.toggle()
            } label: {
                Image(systemName: model.compact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
            }
            .buttonStyle(.borderless)
            .help(model.compact ? L("展開", "Expand") : L("精簡", "Compact"))
        }
        // 讓出標題列的紅綠燈位置
        .padding(.top, 30)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

struct SessionRow: View {
    let session: AgentSession
    let now: Date
    let compact: Bool

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                ToolBadge(tool: session.tool)
                Text(session.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusLabel(status: session.status)
            }
            if !compact {
                progressLine
                HStack(spacing: 4) {
                    if session.title != nil { Text(session.project) }
                    Text(timeText)
                    if session.jumpURL != nil { Image(systemName: "arrow.up.right") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .contentShape(Rectangle())

        if let url = session.jumpURL {
            content
                .onTapGesture { NSWorkspace.shared.open(url) }
                .help(L("跳到這個對話串", "Jump to this thread"))
        } else {
            content
        }
    }

    @ViewBuilder private var progressLine: some View {
        if let p = session.progress {
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: Double(p.percent), total: 100)
                    .tint(session.status.color)
                Text(p.text + (p.current.map { "  → \($0)" } ?? ""))
                    .font(.caption)
                    .lineLimit(1)
            }
        } else if session.status == .working {
            // 沒有計畫：只顯示不確定進度，不給百分比
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L("進行中（沒有列計畫）", "Working (no plan)")).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text(L("沒有列計畫", "No plan")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var timeText: String {
        switch session.status {
        case .working, .waiting:
            session.turnStartedAt.map { L("已 ", "") + formatDuration(now.timeIntervalSince($0)) } ?? ""
        case .done, .idle:
            session.finishedAt.map { formatDuration(now.timeIntervalSince($0)) + L("前", " ago") } ?? ""
        }
    }
}

struct ToolBadge: View {
    let tool: AgentTool

    var body: some View {
        Text(tool.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(tool == .claudeCode ? Color.orange.opacity(0.25) : Color.blue.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
    }
}

struct StatusLabel: View {
    let status: SessionStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.medium))
            .foregroundStyle(status.color)
    }
}

extension SessionStatus {
    var color: Color {
        switch self {
        case .working: .orange
        case .waiting: .yellow
        case .done: .green
        // .secondary 當進度條顏色會變成近乎黑色
        case .idle: .gray
        }
    }
}

/// 清透玻璃上的文字可讀性：一層貼近的深色陰影描邊，加一層較散的陰影壓低背景雜訊
struct Readable: ViewModifier {
    let level: GlassLevel

    func body(content: Content) -> some View {
        switch level {
        case .clear:
            content
                .shadow(color: .black.opacity(0.7), radius: 1, y: 0.5)
                .shadow(color: .black.opacity(0.45), radius: 4)
        case .light:
            content
                .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
                .shadow(color: .black.opacity(0.25), radius: 3)
        default:
            content
        }
    }
}

/// 額度：每個工具一行，5 小時與每週各一條細進度條
struct UsageSection: View {
    let usage: [AgentUsage]
    let now: Date
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.5)
            ForEach(usage, id: \.tool) { u in
                HStack(alignment: .top, spacing: 6) {
                    ToolBadge(tool: u.tool)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(u.windows, id: \.kind) { w in
                            UsageBar(window: w, now: now, compact: compact)
                        }
                    }
                }
                .help(L("數字取自 ", "As of the last response at ") + DateFormatter.localizedString(from: u.observedAt, dateStyle: .none, timeStyle: .short))
            }
        }
    }
}

struct UsageBar: View {
    let window: UsageWindow
    let now: Date
    let compact: Bool

    private var color: Color {
        window.percentUsed >= 90 ? .red : window.percentUsed >= 70 ? .yellow : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(window.label).frame(width: compact ? nil : 40, alignment: .leading)
                Text(L("剩 ", "") + "\(Int(window.percentLeft.rounded()))%" + L("", " left")).foregroundStyle(color)
                Spacer(minLength: 4)
                if let r = window.resetsAt {
                    Text(formatCountdown(to: r, now: now))
                        .foregroundStyle(.secondary)
                        .layoutPriority(1)
                }
            }
            .font(.caption2)
            .lineLimit(1)
            if !compact {
                ProgressView(value: min(window.percentUsed, 100), total: 100)
                    .tint(color)
                    .controlSize(.mini)
            }
        }
    }
}
