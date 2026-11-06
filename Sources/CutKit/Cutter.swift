import Foundation

/// File managers where ⌘X cuts. Both move the files on the clipboard with ⌥⌘V ("Move Item Here").
public enum FileManagers {
    public static let all: [(id: String, name: String)] = [
        ("com.apple.finder", "Finder"),
        ("com.binarynights.ForkLift", "ForkLift"),
        ("com.binarynights.ForkLift-3", "ForkLift 3"),
    ]

    public static func supports(_ id: String?) -> Bool {
        guard let id else { return false }
        return all.contains { $0.id == id }
    }
}

/// What to do with a key press.
public enum Verdict: Equatable, Sendable {
    case pass   // leave it alone
    case cut    // ⌘X → ⌘C, and remember the cut
    case move   // ⌘V → ⌥⌘V: the cut files move here
}

/// The cut, and when ⌘V should move. No AppKit: the clipboard's change count and the clock come from outside.
///
/// ⌘X becomes ⌘C, so the file manager puts the files on the clipboard itself. The cut holds while the clipboard
/// still holds that copy: copy anything else and ⌘V pastes normally again. One move per cut, like Windows.
public final class Cutter {
    public enum State: Equatable, Sendable {
        case idle
        /// ⌘C sent; waiting for the file manager to write the clipboard.
        case copying(before: Int, since: Date)
        /// The clipboard holds the cut files. Changes before `settleUntil` still belong to that copy (an app can
        /// write the clipboard in more than one step); later ones mean something else was copied.
        case armed(count: Int, settleUntil: Date)
    }

    /// Nothing written by then: nothing was selected, so there's nothing to cut.
    static let copyTimeout: TimeInterval = 2
    static let settle: TimeInterval = 0.5

    public private(set) var state: State = .idle {
        didSet { if state != oldValue { onChange?(oldValue, state) } }
    }

    let changeCount: () -> Int
    let now: () -> Date
    /// (old, new) on every state change.
    var onChange: ((State, State) -> Void)?

    init(changeCount: @escaping () -> Int, now: @escaping () -> Date = Date.init) {
        self.changeCount = changeCount
        self.now = now
    }

    public var isArmed: Bool {
        if case .armed = state { return true }
        return false
    }

    /// True while the clipboard needs watching (waiting for the copy, or letting it settle).
    var watching: Bool {
        switch state {
        case .idle: false
        case .copying: true
        case .armed(_, let until): now() < until
        }
    }

    /// Decides a key press. `key` is what the key types with ⌘ held on the current layout; `commandOnly` means
    /// ⌘ is the only modifier. `editingText` asks Accessibility whether a text field has focus (rename, search):
    /// called only when it matters, since it's the one slow step.
    func verdict(app: String?, key: String?, commandOnly: Bool, editingText: () -> Bool) -> Verdict {
        guard commandOnly, FileManagers.supports(app) else { return .pass }
        switch key {
        case "x":
            guard !editingText() else { return .pass }
            state = .copying(before: changeCount(), since: now())
            return .cut
        case "v":
            tick()
            guard isArmed, !editingText() else { return .pass }
            state = .idle
            return .move
        default:
            return .pass
        }
    }

    /// One look at the clipboard.
    func tick() {
        let c = changeCount(), t = now()
        switch state {
        case .idle:
            break
        case .copying(let before, let since):
            if c != before {
                state = .armed(count: c, settleUntil: t.addingTimeInterval(Cutter.settle))
            } else if t.timeIntervalSince(since) > Cutter.copyTimeout {
                state = .idle
            }
        case .armed(let count, let until):
            if c != count { state = t < until ? .armed(count: c, settleUntil: until) : .idle }
        }
    }

    func cancel() { state = .idle }
}
