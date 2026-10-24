import AppKit

// 選單列常駐、不出現在 Dock
if SingleInstance.isAnotherRunning() { exit(0) }
LegacyMigration.run()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
