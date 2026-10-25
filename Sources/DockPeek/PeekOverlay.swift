import AppKit

/// Approximates Windows' "Aero Peek": dims the screen and shows the hovered window
/// (captured at full size) at its own position, above whatever covers it.
/// Click-through, and sits below the Dock so the Dock and preview panel stay usable.
final class PeekOverlay: NSPanel {
    private final class PeekView: NSView {
        var image: CGImage?
        var windowRect: NSRect = .zero
        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.5).setFill()
            bounds.fill()
            guard let image else { return }
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.shadowBlurRadius = 20
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.set()
            NSImage(cgImage: image, size: windowRect.size).draw(in: windowRect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: 19)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    /// `cgFrame` is the window frame in CoreGraphics global coordinates.
    func show(image: CGImage, cgFrame: CGRect) {
        let primaryH = NSScreen.screens[0].frame.height
        let rect = NSRect(x: cgFrame.minX, y: primaryH - cgFrame.maxY, width: cgFrame.width, height: cgFrame.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main ?? NSScreen.screens[0]
        setFrame(screen.frame, display: false)
        let v = PeekView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.image = image
        v.windowRect = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        contentView = v
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; animator().alphaValue = 1 }
        } else {
            orderFrontRegardless()
        }
    }

    func hide() {
        orderOut(nil)
        contentView = nil
    }
}
