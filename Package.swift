// swift-tools-version:6.2
import PackageDescription

// Swift 6 language mode, main-actor-by-default (AppKit app: the event tap, Accessibility calls and UI live on the main thread).
let app: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Cut",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CNoNetwork", path: "Sources/CNoNetwork"),   // sandbox_init, from <sandbox.h>
        .target(name: "CutKit", dependencies: ["CNoNetwork"], path: "Sources/CutKit", swiftSettings: app),
        .executableTarget(name: "Cut", dependencies: ["CutKit"], path: "Sources/Cut", swiftSettings: app),
        .testTarget(name: "CutTests", dependencies: ["CutKit"], path: "Tests/CutTests", swiftSettings: app),
    ]
)
