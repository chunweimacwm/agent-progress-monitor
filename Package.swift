// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "agentmon", targets: ["agentmon"]),
        .executable(name: "AgentMonitor", targets: ["AgentMonitorApp"]),
    ],
    targets: [
        // 純邏輯：讀 Claude Code 狀態檔、解析 Codex 紀錄、估算進度
        .target(name: "AgentCore"),
        // 終端機輸出，驗證用
        .executableTarget(name: "agentmon", dependencies: ["AgentCore"]),
        // 浮動小窗＋選單列
        .executableTarget(name: "AgentMonitorApp", dependencies: ["AgentCore"]),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"]),
    ],
    swiftLanguageModes: [.v5]
)
