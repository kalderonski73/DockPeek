import AppKit
import ScreenCaptureKit

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowPreview {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let image: CGImage?
    let frame: CGRect      // CoreGraphics global coordinates (origin top-left of primary display)
    let onScreen: Bool
    let minimized: Bool
}

enum WindowProvider {
    /// IDs of the app's real (user-visible, incl. minimized) windows, per Accessibility,
    /// and which of them are minimized.
    /// Browsers keep invisible helper windows that CoreGraphics lists but AX does not.
    private static func axWindowInfo(pid: pid_t) -> (ids: Set<CGWindowID>, minimized: Set<CGWindowID>) {
        var ids = Set<CGWindowID>(), mini = Set<CGWindowID>()
        for win in axWindows(pid: pid) {
            var sub: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &sub)
            guard let s = sub as? String, s == "AXStandardWindow" || s == "AXDialog" else { continue }
            var wid: CGWindowID = 0
            guard _AXUIElementGetWindow(win, &wid) == .success else { continue }
            ids.insert(wid)
            var m: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &m)
            if (m as? Bool) == true { mini.insert(wid) }
        }
        return (ids, mini)
    }

    private static func axWindows(pid: pid_t) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value)
        return (value as? [AXUIElement]) ?? []
    }

    private static func axWindow(pid: pid_t, id: CGWindowID) -> AXUIElement? {
        axWindows(pid: pid).first {
            var wid: CGWindowID = 0
            return _AXUIElementGetWindow($0, &wid) == .success && wid == id
        }
    }

    /// Lists an app's windows and captures a small thumbnail for each (in parallel).
    static func previews(for app: NSRunningApplication) async -> [WindowPreview] {
        let pid = app.processIdentifier
        let appName = app.localizedName ?? ""
        let (real, minimized) = axWindowInfo(pid: pid)
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else {
            return fallbackList(pid: pid, name: appName, real: real, minimized: minimized)
        }
        let windows = content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer == 0
                && $0.frame.width > 80 && $0.frame.height > 60
                && (real.isEmpty || real.contains($0.windowID))
        }
        return await withTaskGroup(of: (Int, WindowPreview).self) { group in
            for (i, w) in windows.enumerated() {
                group.addTask {
                    let f = min(2, 440 / w.frame.width, 280 / w.frame.height)
                    let cfg = SCStreamConfiguration()
                    cfg.width = max(1, Int(w.frame.width * f))
                    cfg.height = max(1, Int(w.frame.height * f))
                    cfg.showsCursor = false
                    let image = try? await SCScreenshotManager.captureImage(
                        contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg)
                    let title = (w.title?.isEmpty == false ? w.title : nil) ?? appName
                    return (i, WindowPreview(id: w.windowID, pid: pid, title: title, image: image,
                                             frame: w.frame, onScreen: w.isOnScreen,
                                             minimized: minimized.contains(w.windowID)))
                }
            }
            var out: [(Int, WindowPreview)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    /// Full-resolution capture of one on-screen window, used for peek.
    static func fullImage(windowID: CGWindowID) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let w = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
        let f = min(2, 3840 / w.frame.width)
        let cfg = SCStreamConfiguration()
        cfg.width = max(1, Int(w.frame.width * f))
        cfg.height = max(1, Int(w.frame.height * f))
        cfg.showsCursor = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg)
    }

    /// No Screen Recording permission: list windows without thumbnails.
    private static func fallbackList(pid: pid_t, name: String, real: Set<CGWindowID>,
                                     minimized: Set<CGWindowID>) -> [WindowPreview] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard (d[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (d[kCGWindowLayer as String] as? Int) == 0,
                  let b = d[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) > 80, (b["Height"] ?? 0) > 60,
                  let id = d[kCGWindowNumber as String] as? CGWindowID,
                  real.isEmpty || real.contains(id) else { return nil }
            let title = (d[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
            return WindowPreview(id: id, pid: pid, title: title, image: nil, frame: .zero, onScreen: false,
                                 minimized: minimized.contains(id))
        }
    }

    /// Brings a specific window to the front (un-minimizing if needed).
    static func raise(_ w: WindowPreview) {
        if let win = axWindow(pid: w.pid, id: w.id) {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        NSRunningApplication(processIdentifier: w.pid)?.activate()
    }

    /// Presses the window's close button.
    static func close(_ w: WindowPreview) {
        guard let win = axWindow(pid: w.pid, id: w.id) else { return }
        var btn: CFTypeRef?
        AXUIElementCopyAttributeValue(win, kAXCloseButtonAttribute as CFString, &btn)
        if let btn { AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString) }
    }
}
