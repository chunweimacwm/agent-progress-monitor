import AgentCore
import Combine
import Foundation

final class MonitorModel: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var now = Date()
    @Published private(set) var usage: [AgentUsage] = []
    @Published var compact = false
    /// 是否顯示額度區，選單可切換，記在 UserDefaults
    @Published var showUsage: Bool = UserDefaults.standard.object(forKey: "showUsage") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showUsage, forKey: "showUsage") }
    }
    /// 浮窗透明度，記在 UserDefaults
    @Published var glass: GlassLevel = UserDefaults.standard.string(forKey: "glassLevel").flatMap(GlassLevel.init) ?? .light {
        didSet { UserDefaults.standard.set(glass.rawValue, forKey: "glassLevel") }
    }

    var onChange: (() -> Void)?
    var onAlerts: (([Alert]) -> Void)?

    private let monitor = Monitor()
    private let queue = DispatchQueue(label: "agent-monitor.poll", qos: .utility)
    private var timer: Timer?
    private var detector = TransitionDetector()

    /// 換語言後重畫（字串都在畫的時候取）
    func languageChanged() {
        objectWillChange.send()
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
    }

    // 讀檔放背景佇列，結果回主執行緒更新畫面
    private func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            let next = self.monitor.poll(now: now)
            let usage = self.monitor.usage(now: now)
            DispatchQueue.main.async {
                self.now = now
                if usage != self.usage { self.usage = usage }
                let alerts = self.detector.update(next)
                if !alerts.isEmpty { self.onAlerts?(alerts) }
                if next != self.sessions {
                    self.sessions = next
                    self.onChange?()
                }
            }
        }
    }
}
