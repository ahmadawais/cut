import AppKit
import Combine
import SwiftUI

/// `@State` is a macro shipped only with Xcode; this keeps the app buildable with Command Line Tools.
final class Box<T>: ObservableObject {
    @Published var v: T
    init(_ v: T) { self.v = v }
    // Swift 6.3.3 (Xcode 26.6) crashes inlining into this deinit in -O builds. Nothing to optimize here.
    @_optimize(none) deinit {}
}

/// Toolbar-tab settings window, golden ratio: 560 × 346 (width ÷ φ).
enum SettingsWindow {
    static let width: CGFloat = 560
    static let short = (width / 1.618).rounded()

    static func make() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        func add<V: View>(_ title: String, _ symbol: String, _ view: V) {
            let host = NSHostingController(rootView: view.frame(width: width, height: short))
            host.sizingOptions = .preferredContentSize
            host.title = title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add("General", "gearshape", GeneralTab())
        add("Shortcuts", "keyboard", ShortcutsTab())
        add("Privacy", "hand.raised", PrivacyTab())

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

// MARK: General

struct GeneralTab: View {
    @AppStorage(K.showMenuIcon, store: Prefs.d) private var showIcon = true
    @AppStorage(K.playSound, store: Prefs.d) private var playSound = true
    @StateObject private var launchAtLogin = Box(LoginItem.enabled)
    @StateObject private var trusted = Box(Permission.trusted)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if trusted.v {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { Permission.request(); Permission.openSettings() }
                    }
                } label: {
                    Text("Accessibility")
                    Text(trusted.v ? "Allowed. Used only for ⌘X and ⌘V in Finder." : "Needed to turn ⌘X into cut in Finder.")
                }
                Toggle(isOn: $playSound) {
                    Text("Play sound when cutting")
                    Text("Uses the alert volume in Sound settings.")
                }
                Toggle("Launch at login", isOn: $launchAtLogin.v)
                    .onChange(of: launchAtLogin.v) { _, on in LoginItem.enabled = on }
                Toggle(isOn: $showIcon) {
                    Text("Show menu bar icon")
                    Text("When hidden, open Cut from Spotlight to get here.")
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted.v = Permission.trusted }
    }
}

// MARK: Shortcuts

/// "⌘" "X" as key caps.
struct KeyCaps: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { k in
                Text(k)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .frame(minWidth: 14)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12)))
            }
        }
    }
}

struct ShortcutsTab: View {
    var body: some View {
        Form {
            Section {
                LabeledContent { KeyCaps(keys: ["⌘", "X"]) } label: {
                    Text("Cut")
                    Text("Files stay put until you paste.")
                }
                LabeledContent { KeyCaps(keys: ["⌘", "V"]) } label: {
                    Text("Move here")
                    Text("After a cut. Otherwise ⌘V pastes a copy, as always.")
                }
            } footer: {
                Text("In rename and search fields, ⌘X and ⌘V edit text as usual.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Works in") {
                ForEach(FileManagers.all.filter { $0.id == "com.apple.finder" || installed($0.id) }, id: \.id) { app in
                    AppRow(id: app.id, name: app.name)
                }
                if !FileManagers.all.dropFirst().contains(where: { installed($0.id) }) {
                    AppRow(id: "com.binarynights.ForkLift", name: "ForkLift")
                }
            }
        }
        .formStyle(.grouped)
    }

    func installed(_ id: String) -> Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil }
}

struct AppRow: View {
    let id: String
    let name: String
    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        LabeledContent {
            if url == nil { Text("Not installed").foregroundStyle(.secondary) }
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) }
                    ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage())
                    .resizable().frame(width: 20, height: 20)
                Text(name)
            }
        }
    }
}

// MARK: Privacy

struct PrivacyTab: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Network") {
                    Text(NoNetwork.active ? "Blocked by the kernel" : "Not blocked (development build)")
                }
                LabeledContent("Keystrokes") { Text("Seen only while Finder or ForkLift is in front") }
                LabeledContent("Files") { Text("Never touched: Finder does the move") }
                LabeledContent("Stored") { Text("Settings only") }
                LabeledContent("Updates, analytics") { Text("None") }
            }
        }
        .formStyle(.grouped)
    }
}
