import AppKit
import ApplicationServices

/// Is the user typing text in the front app? Then ⌘X and ⌘V stay text cut and paste (Finder's rename field,
/// its search field, Go to Folder).
enum Focus {
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    static func isText(role: String?) -> Bool { role.map(textRoles.contains) ?? false }

    static func editingText() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid > 0 else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)   // a busy Finder must not stall typing
        guard let el: AXUIElement = copy(app, kAXFocusedUIElementAttribute) else { return false }
        return isText(role: copy(el, kAXRoleAttribute))
    }

    static func copy<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let v else { return nil }
        return v as? T
    }
}

/// Accessibility permission: the event tap that sees ⌘X in Finder, the keys Cut sends, and the focus check.
enum Permission {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt, which links to System Settings.
    static func request() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
