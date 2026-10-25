import AppKit

/// Active key listener that exists only while the preview panel is open, so arrow keys,
/// Return, Esc and Delete can drive the panel without activating DockPeek (and without
/// stealing focus from the frontmost app). Needs the Accessibility permission.
final class KeyboardTap {
    /// Return true to swallow the key.
    var handler: ((UInt16, CGEventFlags) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeyboardTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if me.handler?(code, event.flags) == true { return nil }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap,
                                        eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                        callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    deinit { stop() }
}
