// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Lumen",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "LumenTokens", targets: ["LumenTokens"]),
        .library(name: "LumenUI", targets: ["LumenUI"]),
        .library(name: "LumenIntents", targets: ["LumenIntents"]),
        .library(name: "LumenConformance", targets: ["LumenConformance"]),
        .executable(name: "lumen-theme", targets: ["lumen-theme"]),
        .executable(name: "LumenCatalog", targets: ["LumenCatalog"]),
    ],
    targets: [
        // Internal offscreen host; the process guard is linked exclusively by test targets.
        .target(name: "LumenHeadlessCore", publicHeadersPath: "include", linkerSettings: [.linkedFramework("AppKit")]),
        .target(name: "LumenTestSupport", dependencies: ["LumenHeadlessCore"]),
        .target(name: "LumenHeadlessGuard", dependencies: ["LumenHeadlessCore"], publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("AppKit")]),
        // Tokens, themes, the validator and export: plain Swift, no UI.
        .target(name: "LumenTokens"),
        // SwiftUI and AppKit: the theme store, palette environment, scales, components, and the
        // theme gallery, editor and library.
        // Resources: Lumen's custom SF Symbols (an asset catalog of symbol templates).
        .target(name: "LumenUI", dependencies: ["LumenTokens"], resources: [.process("Resources")]),
        // Opt-in command adapter; LumenUI does not depend on App Intents.
        .target(name: "LumenIntents", dependencies: ["LumenUI"]),
        .testTarget(name: "LumenIntentsTests", dependencies: ["LumenTestSupport", "LumenHeadlessGuard", "LumenIntents", "LumenUI"]),
        // Theme, layout, shortcut and coverage checks for application test targets.
        // For app test targets; the Catalog also links check metadata for its conformance page.
        .target(name: "LumenConformance", dependencies: ["LumenTokens", "LumenUI", "LumenTestSupport"]),
        // Validates theme files and exports the reference artifacts from the command line.
        .executableTarget(name: "lumen-theme", dependencies: ["LumenTokens"]),
        // Every component in a real Mac app, including native menus and the Settings window.
        .executableTarget(name: "LumenCatalog", dependencies: ["LumenTokens", "LumenUI", "LumenIntents", "LumenConformance"]),
        .testTarget(name: "LumenTokensTests", dependencies: ["LumenTestSupport", "LumenHeadlessGuard", "LumenTokens"]),
        // LumenConformance: the golden views also pass the design-rule checks.
        .testTarget(name: "LumenUITests", dependencies: ["LumenTestSupport", "LumenHeadlessGuard", "LumenUI", "LumenConformance", "LumenCatalog"], exclude: ["Goldens", "Fixtures"]),
        // The Catalog's windows never cut their content off: each page fits its column's minimum.
        .testTarget(name: "LumenConformanceTests", dependencies: ["LumenTestSupport", "LumenHeadlessGuard", "LumenConformance", "LumenUI", "LumenTokens"]),
        .testTarget(name: "LumenCatalogTests", dependencies: ["LumenTestSupport", "LumenHeadlessGuard", "LumenCatalog", "LumenUI", "LumenConformance"]),
    ],
    swiftLanguageModes: [.v6]
)

// Force Objective-C +load registration even in test bundles with no window-host call.
for target in package.targets where target.type == .test {
    target.linkerSettings = (target.linkerSettings ?? []) + [.unsafeFlags(["-Xlinker", "-ObjC"])]
}
