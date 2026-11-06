import AppKit
import Carbon.HIToolbox

/// Characters and key codes on the current keyboard layout, as typed with ⌘ held: layouts like
/// "Dvorak – QWERTY ⌘" switch to QWERTY while ⌘ is down, and ⌘X has to follow what the user sees.
enum KeyMap {
    /// ANSI positions, for when the layout can't be read (some input methods).
    static let ansi: [String: CGKeyCode] = ["x": CGKeyCode(kVK_ANSI_X), "c": CGKeyCode(kVK_ANSI_C), "v": CGKeyCode(kVK_ANSI_V)]

    static func character(_ code: Int) -> String? {
        withLayout { translate($0, code) } ?? ansi.first { Int($0.value) == code }?.key
    }

    static func code(for char: String) -> CGKeyCode {
        let found: CGKeyCode? = withLayout { layout in
            (0..<128).first { translate(layout, $0) == char }.map { CGKeyCode($0) }
        } ?? nil
        return found ?? ansi[char] ?? 0
    }

    private static func withLayout<T>(_ body: (UnsafePointer<UCKeyboardLayout>) -> T) -> T? {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        return withExtendedLifetime(src) {
            body(UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self))
        }
    }

    private static func translate(_ layout: UnsafePointer<UCKeyboardLayout>, _ code: Int) -> String? {
        var dead: UInt32 = 0, len = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let cmd = UInt32((cmdKey >> 8) & 0xFF)
        let st = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), cmd, UInt32(LMGetKbdType()),
                                OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        guard st == noErr, len > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: len).lowercased()
    }
}

/// Session event tap on key presses. Turned on only while Finder or ForkLift is in front, so Cut never sees
/// what's typed anywhere else.
final class KeyTap {
    /// Return true to hold the key back (it was turned into another one). Called on the main thread.
    var onKeyDown: ((_ code: Int, _ flags: CGEventFlags) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Key codes whose key-down was held back: their repeats and key-up are held back too, so the app never
    /// sees half a keystroke, and holding ⌘V can't paste a second copy after the move.
    private var held = Set<Int64>()
    private var sawKey = false

    /// Marks the keys Cut sends itself so the tap lets them through untouched.
    nonisolated static let marker: Int64 = 0x4355_5421 // 'CUT!'

    var running: Bool { tap != nil }

    /// Whether the tap receives keys. Off: macOS doesn't send it any.
    var enabled = false {
        didSet {
            guard let tap, enabled != oldValue else { return }
            CGEvent.tapEnable(tap: tap, enable: enabled)
            if !enabled { held.removeAll() }
        }
    }

    /// Creates the tap. Fails without Accessibility (macOS would only hand out a listen-only tap, which is useless here).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: KeyTap.callback, userInfo: me) else {
            return false
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: enabled)
        log.info("Event tap ready")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        held.removeAll()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        nonisolated(unsafe) let ev = event
        nonisolated(unsafe) let ptr = info
        let drop = MainActor.assumeIsolated {
            Unmanaged<KeyTap>.fromOpaque(ptr).takeUnretainedValue().drop(type, ev)
        }
        return drop ? nil : Unmanaged.passUnretained(event)
    }

    /// True = hold the event back.
    func drop(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Also sent when Cut switches the tap off itself (another app in front): nothing to do then.
            guard let tap, enabled else { return false }
            log.info("Event tap was disabled by macOS; re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
            return false
        case .keyDown:
            guard event.getIntegerValueField(.eventSourceUserData) != KeyTap.marker else { return false }
            if !sawKey { sawKey = true; log.info("Event tap is receiving keys") }   // never which key
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if held.contains(code) {
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
                held.remove(code)   // a fresh press whose key-up we missed
            }
            guard onKeyDown?(Int(code), event.flags) == true else { return false }
            held.insert(code)
            return true
        case .keyUp:
            guard event.getIntegerValueField(.eventSourceUserData) != KeyTap.marker else { return false }
            return held.remove(event.getIntegerValueField(.keyboardEventKeycode)) != nil
        default:
            return false
        }
    }

    /// The key-down and key-up Cut sends in place of the user's key.
    static func events(_ code: CGKeyCode, _ flags: CGEventFlags) -> [CGEvent] {
        let src = CGEventSource(stateID: .privateState)
        return [true, false].compactMap { down in
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { return nil }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            return e
        }
    }

    static func send(_ code: CGKeyCode, _ flags: CGEventFlags) {
        for e in events(code, flags) { e.post(tap: .cgSessionEventTap) }
    }
}
