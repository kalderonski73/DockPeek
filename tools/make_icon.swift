import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let body = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let bg = NSBezierPath(roundedRect: body, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1),
                        NSColor(red: 0.45, green: 0.25, blue: 0.85, alpha: 1)])!.draw(in: bg, angle: -60)
    // Back window
    NSColor.white.withAlphaComponent(0.45).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.30, y: s * 0.42, width: s * 0.46, height: s * 0.32),
                 xRadius: s * 0.04, yRadius: s * 0.04).fill()
    // Front window
    let front = NSRect(x: s * 0.20, y: s * 0.28, width: s * 0.46, height: s * 0.32)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: front, xRadius: s * 0.04, yRadius: s * 0.04).fill()
    NSColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: front.minX, y: front.maxY - s * 0.07, width: front.width, height: s * 0.07),
                 xRadius: s * 0.035, yRadius: s * 0.035).fill()
    // Dock bar
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.22, y: s * 0.14, width: s * 0.56, height: s * 0.07),
                 xRadius: s * 0.035, yRadius: s * 0.035).fill()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
for (name, px) in [("16", 16), ("16@2x", 32), ("32", 32), ("32@2x", 64), ("128", 128), ("128@2x", 256),
                   ("256", 256), ("256@2x", 512), ("512", 512), ("512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name.replacingOccurrences(of: "@2x", with: ""))x\(name.replacingOccurrences(of: "@2x", with: ""))\(name.hasSuffix("@2x") ? "@2x" : "").png"))
}
