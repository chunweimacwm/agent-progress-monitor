// 產生 app 圖示：深灰玻璃底＋兩圈進度弧（橘＝Claude Code、藍＝Codex）
// 用法：swift scripts/make-icon.swift <輸出.png>（1024×1024），再由 build-app.sh 轉成 icns
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS 圖示的標準留白：內容約 824pt，圓角約 185pt
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// 陰影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
NSColor(white: 0.12, alpha: 1).setFill()
shape.fill()
ctx.restoreGState()

// 深灰漸層底
shape.addClip()
NSGradient(colors: [NSColor(white: 0.26, alpha: 1), NSColor(white: 0.09, alpha: 1)])!.draw(in: body, angle: -90)
// 上半部玻璃反光
let gloss = NSBezierPath(ovalIn: CGRect(x: body.minX - 200, y: body.midY + 40, width: body.width + 400, height: body.height))
NSColor.white.withAlphaComponent(0.045).setFill()
gloss.fill()
// 細邊框
NSColor.white.withAlphaComponent(0.14).setStroke()
shape.lineWidth = 6
shape.stroke()

let center = CGPoint(x: size / 2, y: size / 2 - 10)

func arc(radius: CGFloat, width: CGFloat, fraction: CGFloat, color: NSColor) {
    // 底軌
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = width
    NSColor.white.withAlphaComponent(0.08).setStroke()
    track.stroke()
    // 進度弧：從 12 點鐘方向順時針
    let p = NSBezierPath()
    p.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
    p.lineWidth = width
    p.lineCapStyle = .round
    color.setStroke()
    p.stroke()
}

arc(radius: 270, width: 64, fraction: 0.72, color: NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1))
arc(radius: 180, width: 64, fraction: 0.45, color: NSColor(red: 0.36, green: 0.56, blue: 0.98, alpha: 1))

// 中心點
NSColor(white: 0.92, alpha: 1).setFill()
NSBezierPath(ovalIn: CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68)).fill()

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("已輸出 \(out)")
