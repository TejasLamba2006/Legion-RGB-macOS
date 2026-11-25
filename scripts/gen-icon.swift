import AppKit
import Foundation

let iconset = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/LegionRGB.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func renderIcon(px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let pad = s * 0.08
    let rounded = NSBezierPath(roundedRect: rect.insetBy(dx: pad, dy: pad), xRadius: s * 0.22, yRadius: s * 0.22)
    let grad = NSGradient(colors: [
        NSColor(calibratedRed: 0.0, green: 0.83, blue: 1.0, alpha: 1.0),
        NSColor(calibratedRed: 0.30, green: 0.45, blue: 1.0, alpha: 1.0),
        NSColor(calibratedRed: 0.66, green: 0.33, blue: 0.97, alpha: 1.0),
        NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.58, alpha: 1.0)
    ])!
    grad.draw(in: rounded, angle: -35)

    let inner = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.15, dy: s * 0.15), xRadius: s * 0.16, yRadius: s * 0.16)
    NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.86).setFill()
    inner.fill()

    let barColors: [NSColor] = [
        NSColor(calibratedRed: 0.0, green: 0.94, blue: 1.0, alpha: 1.0),
        NSColor(calibratedRed: 0.30, green: 0.50, blue: 1.0, alpha: 1.0),
        NSColor(calibratedRed: 0.72, green: 0.30, blue: 1.0, alpha: 1.0),
        NSColor(calibratedRed: 1.0, green: 0.16, blue: 0.56, alpha: 1.0)
    ]
    let totalW = s * 0.56
    let gap = s * 0.025
    let barW = (totalW - gap * 3) / 4.0
    let startX = (s - totalW) / 2.0
    for row in 0..<3 {
        let y = s * (0.31 + CGFloat(row) * 0.15)
        let h = s * 0.105
        for z in 0..<4 {
            let x = startX + CGFloat(z) * (barW + gap)
            let kp = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: h), xRadius: s * 0.025, yRadius: s * 0.025)
            barColors[z].withAlphaComponent(row == 1 ? 0.95 : 0.72).setFill()
            kp.fill()
        }
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for px in [16, 32, 128, 256, 512] {
    try! renderIcon(px: px).write(to: iconset.appendingPathComponent("icon_\(px)x\(px).png"))
    try! renderIcon(px: px * 2).write(to: iconset.appendingPathComponent("icon_\(px)x\(px)@2x.png"))
}
