import Foundation
import Testing
@testable import CutKit

/// A clipboard change count and a clock the test moves by hand.
final class World {
    var count = 100
    var time = Date(timeIntervalSince1970: 1_000_000)
    var focusChecks = 0
    var editing = false
    lazy var cutter = Cutter(changeCount: { [unowned self] in count }, now: { [unowned self] in time })

    func editingText() -> Bool { focusChecks += 1; return editing }
    func wait(_ s: TimeInterval) { time = time.addingTimeInterval(s) }

    func press(_ key: String, app: String? = "com.apple.finder", commandOnly: Bool = true) -> Verdict {
        cutter.verdict(app: app, key: key, commandOnly: commandOnly, editingText: editingText)
    }

    /// ⌘X, then Finder writes the clipboard.
    func cut() {
        #expect(press("x") == .cut)
        count += 1
        cutter.tick()
    }
}

@Suite struct CutterTests {
    @Test func cutThenPasteMoves() {
        let w = World()
        w.cut()
        #expect(w.cutter.isArmed)
        #expect(w.press("v") == .move)
        #expect(w.cutter.state == .idle)
    }

    @Test("One move per cut: the next ⌘V pastes a copy")
    func oneMovePerCut() {
        let w = World()
        w.cut()
        #expect(w.press("v") == .move)
        #expect(w.press("v") == .pass)
    }

    @Test func pasteWithoutCutIsNormal() {
        let w = World()
        #expect(w.press("v") == .pass)
        #expect(w.focusChecks == 0)   // no Accessibility round trip when there's nothing to move
    }

    @Test("Copying something else after the cut cancels it")
    func laterCopyCancels() {
        let w = World()
        w.cut()
        w.wait(1)
        w.count += 1            // ⌘C on other files, or text anywhere
        #expect(w.press("v") == .pass)
        #expect(w.cutter.state == .idle)
    }

    @Test("Clipboard writes right after the cut still belong to it")
    func multiStepWriteSettles() {
        let w = World()
        w.cut()
        w.wait(0.1)
        w.count += 2            // the app wrote in more steps
        w.cutter.tick()
        #expect(w.cutter.isArmed)
        w.wait(1)
        #expect(!w.cutter.watching)
        #expect(w.press("v") == .move)
    }

    @Test("⌘X with nothing selected: no clipboard change, no cut")
    func nothingSelected() {
        let w = World()
        #expect(w.press("x") == .cut)       // still sent as ⌘C (what Finder would do with ⌘C)
        w.wait(1); w.cutter.tick()
        #expect(w.cutter.watching)
        w.wait(1.5); w.cutter.tick()
        #expect(w.cutter.state == .idle)
        #expect(!w.cutter.watching)
        #expect(w.press("v") == .pass)
    }

    @Test("⌘V before the clipboard is written pastes normally")
    func pasteTooEarly() {
        let w = World()
        #expect(w.press("x") == .cut)
        #expect(w.press("v") == .pass)
    }

    @Test func cuttingAgainReplacesTheCut() {
        let w = World()
        w.cut()
        w.wait(2)
        w.cut()
        #expect(w.press("v") == .move)
    }

    @Test("Rename and search fields keep text cut and paste")
    func textFieldsPassThrough() {
        let w = World()
        w.editing = true
        #expect(w.press("x") == .pass)
        #expect(w.cutter.state == .idle)
        w.editing = false
        w.cut()
        w.editing = true
        #expect(w.press("v") == .pass)     // pasting a name into the rename field
        #expect(w.cutter.isArmed)          // the cut waits for a ⌘V in the file list
        w.editing = false
        #expect(w.press("v") == .move)
    }

    @Test("Other apps and other modifiers are left alone",
          arguments: [("com.apple.Safari", true), ("com.apple.TextEdit", true), ("com.apple.finder", false)])
    func otherAppsAndModifiers(app: String, commandOnly: Bool) {
        let w = World()
        #expect(w.press("x", app: app, commandOnly: commandOnly) == .pass)
        #expect(w.press("v", app: app, commandOnly: commandOnly) == .pass)
        #expect(w.cutter.state == .idle)
        #expect(w.focusChecks == 0)
    }

    @Test func noFrontApp() {
        let w = World()
        #expect(w.press("x", app: nil) == .pass)
    }

    @Test("A cut in Finder can move in ForkLift", arguments: ["com.binarynights.ForkLift", "com.binarynights.ForkLift-3"])
    func forkLift(id: String) {
        let w = World()
        w.cut()
        #expect(w.press("v", app: id) == .move)
        #expect(w.press("x", app: id) == .cut)
    }

    @Test func pasteInAnotherAppKeepsTheCut() {
        let w = World()
        w.cut()
        #expect(w.press("v", app: "com.apple.mail") == .pass)
        #expect(w.cutter.isArmed)
        #expect(w.press("v") == .move)
    }

    @Test func otherKeysPass() {
        let w = World()
        for k in ["c", "a", "z", "n", "", "ç"] { #expect(w.press(k) == .pass) }
        #expect(w.cutter.state == .idle)
    }

    @Test func cancel() {
        let w = World()
        w.cut()
        w.cutter.cancel()
        #expect(w.press("v") == .pass)
    }

    @Test func stateChangesAreReported() {
        let w = World()
        var seen: [(Cutter.State, Cutter.State)] = []
        w.cutter.onChange = { seen.append(($0, $1)) }
        w.cut()
        _ = w.press("v")
        #expect(seen.count == 3)
        if case .copying = seen[1].0, case .armed = seen[1].1 {} else { Issue.record("expected copying → armed") }
        #expect(seen[2].1 == .idle)
    }

    @Test func supportedApps() {
        #expect(FileManagers.supports("com.apple.finder"))
        #expect(!FileManagers.supports("com.apple.finder.helper"))
        #expect(!FileManagers.supports(nil))
        #expect(FileManagers.all.first?.name == "Finder")
    }
}
