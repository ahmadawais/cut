import AppKit
import OSLog

nonisolated let log = Logger(subsystem: "com.ahmadawais.cut", category: "app")

/// Status item, menu, the Accessibility grant and the event tap's on/off. Cut logic lives in `Controller`.
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller = Controller()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private var relaunching = false

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        LoginItem.apply()
        installMainMenu()
        controller.cutter.onChange = { [weak self] old, new in self?.cutChanged(old, new) }
        controller.frontAppChanged(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        updateStatusItem()

        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if Permission.trusted, controller.tap.start() {
            log.info("Ready: Accessibility allowed")
        } else {
            waitForPermission()
            Permission.request()
        }
    }

    /// Launching again (Spotlight, Finder) opens Settings: the way back when the icon is hidden.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    @objc private func appActivated(_ n: Notification) {
        let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        controller.frontAppChanged(app?.bundleIdentifier)
    }

    private func cutChanged(_ old: Cutter.State, _ new: Cutter.State) {
        if case .copying = old, case .armed = new {
            CutSound.play()
            log.info("Cut")
        }
        updateStatusItem()
    }

    @objc private func defaultsChanged() {
        DispatchQueue.main.async { [weak self] in self?.updateStatusItem() }
    }

    // MARK: Accessibility

    /// macOS applies a fresh grant reliably only to a new process, so relaunch once it's given.
    private func waitForPermission() {
        guard permissionTimer == nil else { return }
        log.info("Waiting for Accessibility")
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.permissionTick() }
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(accessibilityListChanged),
                                                            name: .init("com.apple.accessibility.api"), object: nil)
    }

    @objc private func accessibilityListChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.permissionTick() }
    }

    private func permissionTick() {
        guard Permission.trusted, !relaunching else { return }
        permissionTimer?.invalidate(); permissionTimer = nil
        updateStatusItem()
        let last = Prefs.d.double(forKey: K.lastRelaunch)
        guard Date().timeIntervalSince1970 - last > 30 else {   // never loop; try in this process instead
            controller.tap.start()
            return
        }
        Prefs.d.set(Date().timeIntervalSince1970, forKey: K.lastRelaunch)
        relaunching = true
        log.info("Accessibility allowed; relaunching so it takes effect")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        cfg.activates = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, error in
            if let error { log.error("Relaunch failed: \(error.localizedDescription, privacy: .public)"); return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Status item & menu

    static func symbol(armed: Bool) -> String { armed ? "scissors.circle.fill" : "scissors" }

    private func updateStatusItem() {
        guard Prefs.showMenuIcon else {
            if let s = statusItem { NSStatusBar.system.removeStatusItem(s) }
            statusItem = nil
            return
        }
        if statusItem == nil {
            let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            s.menu = menu
            statusItem = s
        }
        let armed = controller.cutter.isArmed
        let image = NSImage(systemSymbolName: AppDelegate.symbol(armed: armed), accessibilityDescription: armed ? "Cut: files ready to move" : "Cut")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.appearsDisabled = !Permission.trusted
    }

    /// "3 items cut" while a cut waits for ⌘V; how to start one otherwise.
    static func status(armed: Bool, items: Int) -> String {
        guard armed else { return "Select files in Finder, then ⌘X" }
        let what = items == 1 ? "1 item" : "\(items) items"
        return "\(what) cut. ⌘V moves \(items == 1 ? "it" : "them")."
    }

    private var cutItems: Int {
        NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.count ?? 0
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        controller.cutter.tick()
        if !Permission.trusted {
            menu.addItem(withTitle: "Allow Accessibility…", action: #selector(allowAccessibility), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        let armed = controller.cutter.isArmed
        menu.addItem(NSMenuItem(title: AppDelegate.status(armed: armed, items: armed ? cutItems : 0), action: nil, keyEquivalent: ""))
        if armed {
            menu.addItem(withTitle: "Cancel Cut", action: #selector(cancelCut), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func cancelCut() { controller.cancel() }

    @objc private func allowAccessibility() { Permission.request(); Permission.openSettings(); waitForPermission() }

    @objc private func openSettingsMenu() { openSettings() }

    func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow.make() }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// App menu so ⌘, ⌘W ⌘Q work while Settings is open in an accessory (LSUIElement) app.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsMenu), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Cut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }
}
