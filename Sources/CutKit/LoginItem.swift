import Foundation
import ServiceManagement

/// Launch at login: on by default. The choice lives in this app's prefs, and every launch makes macOS match it,
/// so a fresh install, a new Mac or a cleared Login Items list all come back on by themselves.
/// Turning it off in Settings unregisters; turning it off in System Settings → Login Items (status
/// `.requiresApproval`) is respected and never overridden.
enum LoginItem {
    static let key = K.launchAtLogin

    static var enabled: Bool {
        get { Prefs.d.bool(forKey: key) }
        set { Prefs.d.set(newValue, forKey: key); apply() }
    }

    /// Only the installed app registers: not build/ copies, and not the test runner (which lives in
    /// /Applications/Xcode.app on machines with Xcode).
    static var installed: Bool {
        Bundle.main.bundleIdentifier == "com.ahmadawais.cut" && Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    /// What to do for a given state; pure, so tests cover it.
    enum Step: Equatable { case register, unregister, nothing }

    static func step(enabled: Bool, status: SMAppService.Status) -> Step {
        switch (enabled, status) {
        case (true, .notRegistered), (true, .notFound): .register
        case (false, .enabled): .unregister
        default: .nothing   // already right, or the user switched it off in System Settings
        }
    }

    static func apply(_ service: SMAppService = .mainApp) {
        guard installed else { return }
        do {
            switch step(enabled: enabled, status: service.status) {
            case .register: try service.register()
            case .unregister: try service.unregister()
            case .nothing: break
            }
        } catch {
            log.error("Login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
