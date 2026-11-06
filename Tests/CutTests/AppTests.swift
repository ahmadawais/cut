import AppKit
import ServiceManagement
import Testing
@testable import CutKit

/// Suites that touch global state (Prefs, AppKit) run one at a time.
@Suite(.serialized) struct SharedState {}

enum Env {
    /// Fresh, isolated preferences for one test — never the user's real ones.
    @discardableResult
    static func prefs() -> UserDefaults {
        let d = UserDefaults(suiteName: "com.ahmadawais.cut.tests.\(UUID().uuidString)")!
        Prefs.d = d
        Prefs.register()
        return d
    }
}

@MainActor @Suite struct ControllerTests {
    /// The clipboard change count the test controls.
    final class Clip { var count = 1 }

    @Test("⌘X sends ⌘C and holds the X back; ⌘V then sends ⌥⌘V")
    func cutAndMove() {
        let clip = Clip()
        let (r, c) = make(clip)
        #expect(c.keyDown(code: 7, flags: .maskCommand))
        #expect(r.sent.last?.0 == 8 && r.sent.last?.1 == .maskCommand)
        #expect(c.watching)
        clip.count += 1
        c.tick()
        #expect(c.cutter.isArmed)
        #expect(c.keyDown(code: 9, flags: .maskCommand))
        #expect(r.sent.last?.0 == 9 && r.sent.last?.1 == [.maskCommand, .maskAlternate])
        #expect(!c.watching)
        #expect(!c.keyDown(code: 9, flags: .maskCommand))   // next ⌘V: a normal paste
        #expect(r.sent.count == 2)
    }

    @Test("Caps Lock and fn don't matter; ⇧ ⌃ ⌥ do",
          arguments: [(CGEventFlags.maskShift, false), (.maskControl, false), (.maskAlternate, false),
                      (.maskAlphaShift, true), (.maskSecondaryFn, true), (.maskNumericPad, true)])
    func modifiers(extra: CGEventFlags, cuts: Bool) {
        let (_, c) = make(Clip())
        #expect(c.keyDown(code: 7, flags: [.maskCommand, extra]) == cuts)
    }

    @Test func plainXIsTyping() {
        let (r, c) = make(Clip())
        #expect(!c.keyDown(code: 7, flags: []))
        #expect(r.sent.isEmpty)
    }

    @Test func otherAppsAreIgnored() {
        let (r, c) = make(Clip(), front: "com.apple.Safari")
        #expect(!c.keyDown(code: 7, flags: .maskCommand))
        #expect(r.sent.isEmpty)
    }

    @Test("The tap listens only while a file manager is in front")
    func tapFollowsFrontApp() {
        let (_, c) = make(Clip(), front: "com.apple.Safari")
        #expect(!c.tap.enabled)
        c.frontAppChanged("com.apple.finder")
        #expect(c.tap.enabled)
        c.frontAppChanged("com.binarynights.ForkLift")
        #expect(c.tap.enabled)
        c.frontAppChanged(nil)
        #expect(!c.tap.enabled)
    }

    @Test func watchingStopsWhenNothingWasCut() async throws {
        let (_, c) = make(Clip())
        #expect(c.keyDown(code: 7, flags: .maskCommand))
        #expect(c.watching)
        let deadline = Date().addingTimeInterval(4)
        while c.watching, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!c.watching)
        #expect(c.cutter.state == .idle)
    }

    @Test func timerArmsTheCut() async throws {
        let clip = Clip()
        let (_, c) = make(clip)
        #expect(c.keyDown(code: 7, flags: .maskCommand))
        clip.count += 1
        let deadline = Date().addingTimeInterval(2)
        while !c.cutter.isArmed, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(c.cutter.isArmed)
        c.cancel()
        #expect(!c.watching && !c.cutter.isArmed)
    }

    func make(_ clip: Clip, front: String? = "com.apple.finder") -> (Recorder, Controller) {
        let rec = Recorder()
        let c = Controller(changeCount: { clip.count })
        let qwerty: [Int: String] = [7: "x", 8: "c", 9: "v", 0: "a"]
        c.character = { qwerty[$0] }
        c.keyCode = { ch in CGKeyCode(qwerty.first { $0.value == ch }!.key) }
        c.send = { rec.sent.append(($0, $1)) }
        c.editingText = { false }
        c.frontAppChanged(front)
        return (rec, c)
    }

    final class Recorder { var sent: [(CGKeyCode, CGEventFlags)] = [] }
}

@MainActor @Suite struct KeyTapTests {
    @Test("Sent keys: down + up, exact flags, marked so the tap skips them")
    func events() {
        let e = KeyTap.events(9, [.maskCommand, .maskAlternate])
        #expect(e.count == 2)
        #expect(e.map { $0.type } == [.keyDown, .keyUp])
        for ev in e {
            #expect(ev.getIntegerValueField(.keyboardEventKeycode) == 9)
            #expect(ev.flags.intersection(Controller.modifiers) == [.maskCommand, .maskAlternate])
            #expect(ev.getIntegerValueField(.eventSourceUserData) == KeyTap.marker)
        }
    }

    func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = .maskCommand, repeat r: Bool = false, mine: Bool = false) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        e.flags = flags
        if r { e.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        if mine { e.setIntegerValueField(.eventSourceUserData, value: KeyTap.marker) }
        return e
    }

    @Test("A replaced key's repeats and key-up are held back too")
    func holdsWholeKeystroke() {
        let tap = KeyTap()
        var calls = 0
        tap.onKeyDown = { code, _ in calls += 1; return code == 9 }
        #expect(tap.drop(.keyDown, key(9, down: true)))
        #expect(tap.drop(.keyDown, key(9, down: true, repeat: true)))   // holding ⌘V can't paste again
        #expect(tap.drop(.keyUp, key(9, down: false)))
        #expect(!tap.drop(.keyUp, key(9, down: false)))                  // only once
        #expect(!tap.drop(.keyDown, key(0, down: true)))
        #expect(!tap.drop(.keyUp, key(0, down: false)))
        #expect(calls == 2)
    }

    @Test func ownKeysPassUntouched() {
        let tap = KeyTap()
        var calls = 0
        tap.onKeyDown = { _, _ in calls += 1; return true }
        #expect(!tap.drop(.keyDown, key(8, down: true, mine: true)))
        #expect(!tap.drop(.keyUp, key(8, down: false, mine: true)))
        #expect(calls == 0)
    }

    @Test func layoutRoundTrip() {
        for ch in ["x", "c", "v"] {
            let code = KeyMap.code(for: ch)
            #expect(KeyMap.character(Int(code)) == ch, "layout maps \(ch) to key \(code)")
        }
        #expect(KeyMap.ansi == ["x": 7, "c": 8, "v": 9])
    }

    @Test func textRoles() {
        for r in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] { #expect(Focus.isText(role: r)) }
        for r in ["AXOutline", "AXList", "AXBrowser", "AXGroup", "AXScrollArea", "AXWindow"] { #expect(!Focus.isText(role: r)) }
        #expect(!Focus.isText(role: nil))
    }
}

extension SharedState {
    @MainActor struct PrefsTests {
        @Test("Defaults: menu icon, sound and launch at login on")
        func defaults() {
            Env.prefs()
            #expect(Prefs.showMenuIcon)
            #expect(Prefs.playSound)
            #expect(LoginItem.enabled)
        }

        @Test func loginItemSteps() {
            #expect(LoginItem.step(enabled: true, status: .notRegistered) == .register)
            #expect(LoginItem.step(enabled: true, status: .requiresApproval) == .nothing)   // user said no
            #expect(LoginItem.step(enabled: false, status: .enabled) == .unregister)
            #expect(LoginItem.step(enabled: true, status: .enabled) == .nothing)
            #expect(!LoginItem.installed)   // the test runner never registers
        }

        @Test func soundFileExists() {
            #expect(FileManager.default.fileExists(atPath: CutSound.url.path))
        }

        @Test func menuText() {
            #expect(AppDelegate.status(armed: false, items: 0) == "Select files in Finder, then ⌘X")
            #expect(AppDelegate.status(armed: true, items: 1) == "1 item cut. ⌘V moves it.")
            #expect(AppDelegate.status(armed: true, items: 3) == "3 items cut. ⌘V moves them.")
            for armed in [false, true] {
                #expect(NSImage(systemSymbolName: AppDelegate.symbol(armed: armed), accessibilityDescription: nil) != nil)
            }
        }

        @Test("Settings window uses golden-ratio toolbar tabs")
        func goldenRatio() throws {
            _ = NSApplication.shared
            Env.prefs()
            let window = SettingsWindow.make()
            let tabs = try #require(window.contentViewController as? NSTabViewController)
            #expect(tabs.tabStyle == .toolbar)
            #expect(tabs.tabViewItems.map(\.label) == ["General", "Shortcuts", "Privacy"])
            #expect(SettingsWindow.short == 346)
        }

        /// Renders every tab to .build/renders/*.png — open them and look before calling the UI done.
        @Test("Render settings for review")
        func render() throws {
            _ = NSApplication.shared
            Env.prefs()
            let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../.build/renders").standardized
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let window = SettingsWindow.make()
                window.appearance = NSAppearance(named: appearance)
                let tabs = try #require(window.contentViewController as? NSTabViewController)
                tabs.transitionOptions = []
                for i in tabs.tabViewItems.indices {
                    tabs.selectedTabViewItemIndex = i
                    window.layoutIfNeeded()
                    let view = try #require(window.contentView?.superview)
                    view.layoutSubtreeIfNeeded()
                    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let png = try #require(rep.representation(using: .png, properties: [:]))
                    try png.write(to: dir.appendingPathComponent("settings-\(name)-\(i)-\(tabs.tabViewItems[i].label).png"))
                }
            }
        }
    }
}
