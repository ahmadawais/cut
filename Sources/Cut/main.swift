import AppKit
import CutKit

NoNetwork.apply()   // first: kernel blocks all networking for the life of the process

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
