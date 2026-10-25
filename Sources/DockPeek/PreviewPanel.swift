import AppKit

private let thumbMaxW: CGFloat = 220
private let thumbMaxH: CGFloat = 140
private let headerH: CGFloat = 26
private let pad: CGFloat = 10
private let rowW: CGFloat = 300
private let rowH: CGFloat = 32

// MARK: - Close button

final class CloseButton: NSView {
    var onClick: (() -> Void)?
    override init(frame: NSRect) { super.init(frame: NSRect(x: 0, y: 0, width: 18, height: 18)) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        NSColor.white.setStroke()
        let x = NSBezierPath()
        x.lineWidth = 1.6
        x.move(to: NSPoint(x: 6, y: 6)); x.line(to: NSPoint(x: 12, y: 12))
        x.move(to: NSPoint(x: 12, y: 6)); x.line(to: NSPoint(x: 6, y: 12))
        x.stroke()
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Items

class ItemView: NSView {
    var preview: WindowPreview
    var onClick: ((WindowPreview) -> Void)?
    var onClose: ((WindowPreview) -> Void)?
    var onHover: ((WindowPreview, Bool) -> Void)?
    let closeButton = CloseButton()

    var hovering = false { didSet { updateChrome() } }
    var selected = false { didSet { updateChrome() } }

    private func updateChrome() {
        needsDisplay = true
        closeButton.isHidden = !(hovering || selected)
    }

    init(preview: WindowPreview, size: NSSize) {
        self.preview = preview
        super.init(frame: NSRect(origin: .zero, size: size))
        closeButton.isHidden = true
        closeButton.onClick = { [weak self] in
            guard let self else { return }
            self.onClose?(self.preview)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Subclasses call this after adding their own subviews so the button sits on top.
    func finishLayout() { addSubview(closeButton, positioned: .above, relativeTo: nil) }
    func setImage(_ image: CGImage?) {}
    /// Re-applies title / minimized state after `preview` changed.
    func applyState() {}

    override func draw(_ dirtyRect: NSRect) {
        if hovering || selected {
            NSColor.white.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        }
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; onHover?(preview, true) }
    override func mouseExited(with event: NSEvent) { hovering = false; onHover?(preview, false) }
    override func mouseDown(with event: NSEvent) { onClick?(preview) }
    override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { onClose?(preview) } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class CardView: ItemView {
    private let iv = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "Minimized")
    private let icon: NSImage?

    static func size(for p: WindowPreview) -> (card: NSSize, image: NSSize) {
        var img = NSSize(width: thumbMaxW, height: thumbMaxH)
        if let i = p.image {
            let s = min(thumbMaxW / CGFloat(i.width), thumbMaxH / CGFloat(i.height))
            img = NSSize(width: CGFloat(i.width) * s, height: CGFloat(i.height) * s)
        }
        return (NSSize(width: max(img.width, 140) + pad * 2, height: headerH + img.height + pad * 2), img)
    }

    init(preview: WindowPreview, icon: NSImage?) {
        self.icon = icon
        let (card, imgSize) = CardView.size(for: preview)
        super.init(preview: preview, size: card)
        let w = card.width, h = card.height

        let iconView = NSImageView(frame: NSRect(x: pad, y: h - pad - 18, width: 18, height: 18))
        iconView.image = icon
        addSubview(iconView)

        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: pad + 24, y: h - pad - 18, width: w - pad * 2 - 24 - 22, height: 18)
        addSubview(label)

        iv.frame = NSRect(x: w / 2 - imgSize.width / 2, y: pad, width: imgSize.width, height: imgSize.height)
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 6
        iv.layer?.masksToBounds = true
        iv.layer?.borderWidth = 0.5
        iv.layer?.borderColor = NSColor.separatorColor.cgColor
        addSubview(iv)
        setImage(preview.image)

        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        badge.layer?.cornerRadius = 4
        badge.sizeToFit()
        badge.frame = NSRect(x: iv.frame.minX + 6, y: iv.frame.minY + 6, width: badge.frame.width + 10, height: 15)
        addSubview(badge)

        closeButton.frame.origin = NSPoint(x: w - pad - 18, y: h - pad - 18)
        finishLayout()
        applyState()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func applyState() {
        label.stringValue = preview.title
        badge.isHidden = !preview.minimized
        iv.alphaValue = preview.minimized ? 0.55 : 1
    }

    override func setImage(_ image: CGImage?) {
        if let image {
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.image = NSImage(cgImage: image, size: iv.frame.size)
        } else {
            iv.imageScaling = .scaleProportionallyDown
            iv.image = icon
        }
    }
}

final class RowView: ItemView {
    private let label = NSTextField(labelWithString: "")

    init(preview: WindowPreview, icon: NSImage?) {
        super.init(preview: preview, size: NSSize(width: rowW, height: rowH))
        let iconView = NSImageView(frame: NSRect(x: 8, y: (rowH - 18) / 2, width: 18, height: 18))
        iconView.image = icon
        addSubview(iconView)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 34, y: (rowH - 18) / 2, width: rowW - 34 - 34, height: 18)
        addSubview(label)
        closeButton.frame.origin = NSPoint(x: rowW - 26, y: (rowH - 18) / 2)
        finishLayout()
        applyState()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func applyState() {
        label.stringValue = preview.title + (preview.minimized ? "  —  Minimized" : "")
    }
}

// MARK: - Panel

final class PreviewPanel: NSPanel {
    var onSelect: ((WindowPreview) -> Void)?
    var onClose: ((WindowPreview) -> Void)?
    var onHover: ((WindowPreview, Bool) -> Void)?

    private var items: [ItemView] = []
    private var currentIDs: [CGWindowID] = []
    private var app: NSRunningApplication?
    private var anchor: CGRect = .zero

    private(set) var selectedIndex: Int?
    private var selectedID: CGWindowID?
    private var selectedByKeyboard = false

    var selectedPreview: WindowPreview? {
        guard let i = selectedIndex, items.indices.contains(i) else { return nil }
        return items[i].preview
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true          // resets the level, so set the level afterwards
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { false }

    /// `anchor` is the Dock icon's frame in AppKit screen coordinates.
    func present(_ previews: [WindowPreview], app: NSRunningApplication, anchor: CGRect) {
        self.app = app
        self.anchor = anchor
        build(previews)
    }

    /// Refreshes thumbnails in place; rebuilds only when the set of windows changed.
    /// Returns true if the layout was rebuilt.
    @discardableResult
    func update(_ previews: [WindowPreview]) -> Bool {
        if previews.map(\.id) == currentIDs {
            for (item, p) in zip(items, previews) {
                item.preview = p
                item.setImage(p.image)
                item.applyState()
            }
            return false
        }
        build(previews)
        return true
    }

    /// Moves the keyboard selection (wrapping); notifies like a hover so peek follows.
    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let next: Int
        if let i = selectedIndex { next = (i + delta + items.count) % items.count }
        else { next = delta > 0 ? 0 : items.count - 1 }
        items.forEach { $0.hovering = false }
        setSelection(next, notify: true, keyboard: true)
    }

    private func setSelection(_ idx: Int?, notify: Bool, keyboard: Bool) {
        let old = selectedIndex
        if let old, items.indices.contains(old) { items[old].selected = false }
        selectedIndex = idx
        selectedID = idx.map { currentIDs[$0] }
        selectedByKeyboard = keyboard
        if let idx { items[idx].selected = true }
        guard notify, old != idx else { return }
        if let old, items.indices.contains(old) { onHover?(items[old].preview, false) }
        if let idx { onHover?(items[idx].preview, true) }
    }

    /// Mouse hover and keyboard selection share one highlight.
    private func hoverChanged(_ p: WindowPreview, _ entered: Bool) {
        if entered, let i = currentIDs.firstIndex(of: p.id) {
            setSelection(i, notify: false, keyboard: false)
        } else if !entered, selectedID == p.id {
            setSelection(nil, notify: false, keyboard: false)
        }
        onHover?(p, entered)
    }

    private func build(_ previews: [WindowPreview]) {
        guard let app else { return }
        let oldIndex = selectedIndex
        let wasVisible = isVisible
        let icon = app.icon
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.frame

        let cardsW = previews.reduce(pad) { $0 + CardView.size(for: $1).card.width + pad }
        let listMode = cardsW > sf.width - 40 || previews.count > 8

        let views: [ItemView] = previews.map { listMode ? RowView(preview: $0, icon: icon) : CardView(preview: $0, icon: icon) }
        for v in views {
            v.onClick = { [weak self] p in self?.onSelect?(p) }
            v.onClose = { [weak self] p in self?.onClose?(p) }
            v.onHover = { [weak self] p, e in self?.hoverChanged(p, e) }
        }
        items = views
        currentIDs = previews.map(\.id)

        // Keep the selection across a rebuild (e.g. after closing a window).
        if let id = selectedID, let i = currentIDs.firstIndex(of: id) {
            selectedIndex = i
            views[i].selected = true
        } else if selectedByKeyboard, let old = oldIndex, !views.isEmpty {
            setSelection(min(old, views.count - 1), notify: false, keyboard: true)
        } else {
            selectedIndex = nil
            selectedID = nil
        }

        let size: NSSize
        let bg: NSVisualEffectView
        if listMode {
            size = NSSize(width: rowW + pad * 2, height: CGFloat(views.count) * (rowH + 2) - 2 + pad * 2)
            bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            var y = size.height - pad - rowH
            for v in views { v.frame.origin = NSPoint(x: pad, y: y); bg.addSubview(v); y -= rowH + 2 }
        } else {
            let maxH = views.map { $0.frame.height }.max() ?? 100
            size = NSSize(width: cardsW, height: maxH + pad * 2)
            bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            var x = pad
            for v in views {
                v.frame.origin = NSPoint(x: x, y: pad + (maxH - v.frame.height) / 2)
                bg.addSubview(v)
                x += v.frame.width + pad
            }
        }
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true
        contentView = bg

        let gap: CGFloat = 8
        var origin: NSPoint
        // The Dock sits on whichever screen edge is closest to the icon.
        let dLeft = anchor.midX - sf.minX, dRight = sf.maxX - anchor.midX, dBottom = anchor.midY - sf.minY
        if dLeft < dRight && dLeft < dBottom {
            origin = NSPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        } else if dRight < dBottom {
            origin = NSPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
        } else {
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        }
        origin.x = min(max(origin.x, sf.minX + 6), sf.maxX - size.width - 6)
        origin.y = min(max(origin.y, sf.minY + 6), sf.maxY - size.height - 6)
        setFrame(NSRect(origin: origin, size: size), display: true)

        if !wasVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; animator().alphaValue = 1 }
        } else {
            orderFrontRegardless()
        }
    }

    func dismiss() {
        orderOut(nil)
        contentView = nil
        items = []
        currentIDs = []
        selectedIndex = nil
        selectedID = nil
        selectedByKeyboard = false
    }
}
