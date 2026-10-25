import AppKit
import ServiceManagement

func debugLog(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DockPeek.log")
    let line = "\(Date()) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panel = PreviewPanel()
    private let overlay = PeekOverlay()
    private let keyTap = KeyboardTap()
    private var keyboardAnchor: NSPoint?   // mouse position when keyboard navigation started
    private var suppressPID: pid_t?        // app dismissed with Esc; don't reopen until the mouse leaves its icon
    private var refreshTimer: Timer?
    private var refreshing = false
    private var peekTimer: Timer?
    private var peekToken = 0
    private var lastPeekEnd = Date.distantPast
    private var statusItem: NSStatusItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var wakeTimer: Timer?
    private var trailingTimer: Timer?
    private var lastEval = Date.distantPast
    private var loginItem: NSMenuItem!

    private var hoveredPID: pid_t?          // Dock item under the mouse (or currently shown)
    private var hoverStart = Date()
    private var shownPID: pid_t?
    private var loadingPID: pid_t?
    private var leftAt: Date?

    private let dwell: TimeInterval = 0.35
    private let grace: TimeInterval = 0.30

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        requestPermissions()
        debugLog("launch: AX trusted=\(AXIsProcessTrusted()) screen=\(CGPreflightScreenCaptureAccess())")
        panel.onSelect = { [weak self] w in
            WindowProvider.raise(w)
            self?.hide()
        }
        panel.onClose = { [weak self] w in
            WindowProvider.close(w)
            self?.cancelPeek()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refreshNow() }
        }
        keyTap.handler = { [weak self] code, flags in self?.handleKey(code, flags) ?? false }
        panel.onHover = { [weak self] w, entered in self?.hoverCard(w, entered: entered) }
        startMouseMonitoring()
    }

    // MARK: Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "DockPeek")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Accessibility Settings", action: #selector(openAX), keyEquivalent: "")
        menu.addItem(withTitle: "Open Screen Recording Settings", action: #selector(openSR), keyEquivalent: "")
        menu.addItem(.separator())
        loginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DockPeek", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? NSApp : self }
        statusItem.menu = menu
    }

    private func requestPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { debugLog("login item error: \(error)") }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openAX() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func openSR() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    // MARK: Hover handling (event-driven, no polling)

    private func startMouseMonitoring() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.mouseMoved() }
        // Global monitors don't see events delivered to our own panel.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.mouseMoved(); return e
        }
    }

    /// Cheap filter + throttle; the expensive Dock hit-test only runs near a screen edge
    /// or while a preview is open.
    private func mouseMoved() {
        let mouse = NSEvent.mouseLocation
        guard panel.isVisible || loadingPID != nil || hoveredPID != nil || nearEdge(mouse) else { return }
        let now = Date()
        if now.timeIntervalSince(lastEval) < 0.03 {
            if trailingTimer == nil {
                trailingTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: false) { [weak self] _ in
                    self?.trailingTimer = nil; self?.evaluate()
                }
            }
            return
        }
        evaluate()
    }

    private func wake(after delay: TimeInterval) {
        wakeTimer?.invalidate()
        wakeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.evaluate() }
    }

    private func evaluate() {
        lastEval = Date()
        guard AXIsProcessTrusted() else { return }
        let mouse = NSEvent.mouseLocation

        if panel.isVisible, panel.frame.insetBy(dx: -4, dy: -4).contains(mouse) {
            leftAt = nil
            wakeTimer?.invalidate()
            return
        }

        // After keyboard navigation, keep the panel until the mouse really moves away.
        if let a = keyboardAnchor {
            if hypot(mouse.x - a.x, mouse.y - a.y) < 12 { return }
            keyboardAnchor = nil
        }

        let item = nearEdge(mouse) ? dockItem(at: mouse) : nil

        if let item {
            leftAt = nil
            let pid = item.app.processIdentifier
            if pid != hoveredPID {
                hoveredPID = pid
                hoverStart = Date()
                if shownPID != pid { hide() }
            }
            if pid == suppressPID || shownPID == pid || loadingPID == pid { wakeTimer?.invalidate(); return }
            let remaining = dwell - Date().timeIntervalSince(hoverStart)
            if remaining <= 0 || panel.isVisible {
                wakeTimer?.invalidate()
                show(item.app, anchor: item.frame)
            } else {
                wake(after: remaining + 0.01)   // mouse may rest on the icon with no further events
            }
        } else {
            hoveredPID = nil
            suppressPID = nil
            guard panel.isVisible || loadingPID != nil else { wakeTimer?.invalidate(); return }
            if leftAt == nil {
                leftAt = Date()
                wake(after: grace + 0.02)
            } else if Date().timeIntervalSince(leftAt!) > grace {
                wakeTimer?.invalidate()
                hide()
            } else {
                wake(after: grace + 0.02 - Date().timeIntervalSince(leftAt!))
            }
        }
    }

    private func show(_ app: NSRunningApplication, anchor: CGRect) {
        let pid = app.processIdentifier
        loadingPID = pid
        Task { @MainActor in
            let previews = await WindowProvider.previews(for: app)
            guard loadingPID == pid, hoveredPID == pid || panel.isVisible else { return }
            loadingPID = nil
            guard !previews.isEmpty else { return }
            panel.present(previews, app: app, anchor: anchor)
            shownPID = pid
            if !keyTap.start() { debugLog("keyboard tap unavailable") }
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshNow() }
        }
    }

    // MARK: Live refresh and peek

    private func refreshNow() {
        guard !refreshing, let pid = shownPID,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        refreshing = true
        Task { @MainActor in
            let previews = await WindowProvider.previews(for: app)
            refreshing = false
            guard shownPID == pid else { return }
            if previews.isEmpty { hide(); return }
            if panel.update(previews) { cancelPeek() }
        }
    }

    private func cancelPeek() {
        peekTimer?.invalidate()
        peekToken += 1
        overlay.hide()
    }

    private func hoverCard(_ w: WindowPreview, entered: Bool) {
        if overlay.isVisible { lastPeekEnd = Date() }
        let wasPeeking = Date().timeIntervalSince(lastPeekEnd) < 0.3
        cancelPeek()
        guard entered, w.onScreen, w.image != nil else { return }
        let token = peekToken
        peekTimer = Timer.scheduledTimer(withTimeInterval: wasPeeking ? 0.05 : 0.45, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let img = await WindowProvider.fullImage(windowID: w.id),
                      token == self.peekToken, self.panel.isVisible else { return }
                self.overlay.show(image: img, cgFrame: w.frame)
            }
        }
    }

    // MARK: Keyboard

    private func handleKey(_ code: UInt16, _ flags: CGEventFlags) -> Bool {
        guard panel.isVisible else { return false }
        let mods = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        func nav(_ d: Int) -> Bool {
            panel.moveSelection(d)
            keyboardAnchor = NSEvent.mouseLocation
            leftAt = nil
            wakeTimer?.invalidate()
            return true
        }
        func closeSelected() -> Bool {
            guard let w = panel.selectedPreview else { return false }
            keyboardAnchor = NSEvent.mouseLocation
            panel.onClose?(w)
            return true
        }
        if code == 13, flags.contains(.maskCommand), mods == .maskCommand { return closeSelected() }   // ⌘W
        guard mods.isEmpty else { return false }
        switch code {
        case 53:                       // Esc
            suppressPID = shownPID
            hide()
            return true
        case 123, 126: return nav(-1)  // ← ↑
        case 124, 125: return nav(1)   // → ↓
        case 36, 76:                   // Return / Enter
            guard let w = panel.selectedPreview else { return false }
            WindowProvider.raise(w)
            hide()
            return true
        case 51, 117: return closeSelected()   // Delete / Forward delete
        default: return false
        }
    }

    private func hide() {
        keyTap.stop()
        keyboardAnchor = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancelPeek()
        panel.dismiss()
        shownPID = nil
        loadingPID = nil
        leftAt = nil
    }

    // MARK: Dock hit-testing

    private func nearEdge(_ p: NSPoint) -> Bool {
        guard let s = NSScreen.screens.first(where: { $0.frame.contains(p) }) else { return false }
        let f = s.frame, m: CGFloat = 130
        return p.x - f.minX < m || f.maxX - p.x < m || p.y - f.minY < m
    }

    private func dockItem(at mouse: NSPoint) -> (app: NSRunningApplication, frame: CGRect)? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let primaryH = NSScreen.screens[0].frame.height
        let axDock = AXUIElementCreateApplication(dock.processIdentifier)
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(axDock, Float(mouse.x), Float(primaryH - mouse.y), &el) == .success,
              let el else { return nil }

        var sub: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &sub)
        guard (sub as? String) == "AXApplicationDockItem" else { return nil }

        var urlRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXURLAttribute as CFString, &urlRef)
        guard let url = (urlRef as? URL)?.standardizedFileURL else { return nil }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL == url && $0.activationPolicy == .regular
        }) else { return nil }

        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        var pos = CGPoint.zero, size = CGSize.zero
        AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef)
        guard let posRef, let sizeRef,
              AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        let frame = CGRect(x: pos.x, y: primaryH - pos.y - size.height, width: size.width, height: size.height)
        return (app, frame)
    }
}
