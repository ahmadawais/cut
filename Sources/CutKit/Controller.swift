import AppKit

/// Keys in, keys out: decides each ⌘X / ⌘V in a file manager and sends the replacement. Everything it touches
/// outside itself (clipboard, layout, Accessibility, sending keys) is injected, so tests drive it end to end.
final class Controller {
    let cutter: Cutter
    let tap = KeyTap()
    private(set) var frontApp: String?

    var character: (Int) -> String? = { KeyMap.character($0) }
    var keyCode: (String) -> CGKeyCode = { KeyMap.code(for: $0) }
    var editingText: () -> Bool = { Focus.editingText() }
    var send: (CGKeyCode, CGEventFlags) -> Void = { KeyTap.send($0, $1) }

    private var timer: Timer?
    static let tickInterval: TimeInterval = 0.05

    init(changeCount: @escaping () -> Int = { NSPasteboard.general.changeCount }, now: @escaping () -> Date = Date.init) {
        cutter = Cutter(changeCount: changeCount, now: now)
        tap.onKeyDown = { [weak self] code, flags in self?.keyDown(code: code, flags: flags) ?? false }
    }

    static let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]

    /// True = the key was replaced; hold the original back.
    func keyDown(code: Int, flags: CGEventFlags) -> Bool {
        // Cheap checks first: this runs for every key typed in a file manager.
        let commandOnly = flags.intersection(Controller.modifiers) == .maskCommand
        guard commandOnly, FileManagers.supports(frontApp) else { return false }
        switch cutter.verdict(app: frontApp, key: character(code), commandOnly: true, editingText: editingText) {
        case .pass:
            return false
        case .cut:
            send(keyCode("c"), .maskCommand)
            watch()
            return true
        case .move:
            send(keyCode("v"), [.maskCommand, .maskAlternate])
            stopWatching()
            log.info("Move")
            return true
        }
    }

    /// The tap listens only while a file manager is in front.
    func frontAppChanged(_ bundleID: String?) {
        frontApp = bundleID
        tap.enabled = FileManagers.supports(bundleID)
    }

    /// Polls the clipboard (macOS has no change notification) only while a cut is being made.
    private func watch() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Controller.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func tick() {
        cutter.tick()
        if !cutter.watching { stopWatching() }
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    var watching: Bool { timer != nil }

    func cancel() {
        stopWatching()
        cutter.cancel()
    }
}
