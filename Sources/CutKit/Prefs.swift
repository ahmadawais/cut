import AppKit
import AudioToolbox

/// Preference keys.
enum K {
    static let showMenuIcon = "showMenuIcon"
    static let launchAtLogin = "launchAtLogin"
    static let playSound = "playSound"
    static let lastRelaunch = "lastRelaunch"
}

/// All settings go through `Prefs.d`, so tests can swap in an isolated suite.
public enum Prefs {
    nonisolated(unsafe) static var d = UserDefaults.standard

    public static func register() {
        d.register(defaults: [
            K.showMenuIcon: true,
            K.launchAtLogin: true,
            K.playSound: true,
        ])
    }

    public static var showMenuIcon: Bool {
        get { d.bool(forKey: K.showMenuIcon) }
        set { d.set(newValue, forKey: K.showMenuIcon) }
    }

    public static var playSound: Bool {
        get { d.bool(forKey: K.playSound) }
        set { d.set(newValue, forKey: K.playSound) }
    }
}

/// The cut sound: a system effect, so it plays at the alert volume and stays quiet when
/// "Play user interface sound effects" is off (System Settings → Sound).
enum CutSound {
    static let url = URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff")
    private static var id: SystemSoundID = 0

    static var systemEffectsOn: Bool {
        let g = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return (g?["com.apple.sound.uiaudio.enabled"] as? Int ?? 1) != 0
    }

    static func play() {
        guard Prefs.playSound, systemEffectsOn else { return }
        if id == 0, AudioServicesCreateSystemSoundID(url as CFURL, &id) != noErr { return }
        AudioServicesPlaySystemSound(id)
    }
}
