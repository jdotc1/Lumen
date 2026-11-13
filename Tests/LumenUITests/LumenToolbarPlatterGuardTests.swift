import XCTest

/// design review, 2026-11-12: the system's glass bubbles around toolbar items are out of every Lumen app.
/// This source scan keeps them out: every `ToolbarItem` in Sources hides its platter, the platter
/// rule never returns `.automatic`, and `glassEffect` appears only on the floating surfaces that
/// are allowed to use it (command palette, toast stack).
final class LumenToolbarPlatterGuardTests: XCTestCase {
    private var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private func swiftFiles() -> [(path: String, text: String)] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: keys) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            .compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).map { (url.path.replacingOccurrences(of: sources.path + "/", with: ""), $0) } }
    }

    func testEveryToolbarItemHidesItsPlatter() {
        var offenders: [String] = []
        for (path, text) in swiftFiles() {
            let ns = text as NSString
            let regex = try! NSRegularExpression(pattern: #"(?<!NS)ToolbarItem(Group)?\("#)
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for (index, match) in matches.enumerated() {
                let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
                let slice = ns.substring(with: NSRange(location: match.range.location, length: min(end - match.range.location, 1800)))
                if !slice.contains("lumenToolbarPlatter") && !slice.contains("sharedBackgroundVisibility(.hidden)") {
                    let line = ns.substring(to: match.range.location).components(separatedBy: "\n").count
                    offenders.append("\(path):\(line)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Toolbar items that can draw a system glass platter: \(offenders)")
    }

    func testPlatterRuleNeverShowsTheSystemPlatter() throws {
        let text = try String(contentsOf: sources.appendingPathComponent("LumenUI/LumenChromeStyle.swift"), encoding: .utf8)
        XCTAssertFalse(text.contains("sharedBackgroundVisibility(style == .glass"), "lumenToolbarPlatter must not vary with the chrome style")
        XCTAssertFalse(text.contains("sharedBackgroundVisibility(.automatic)") || text.contains("sharedBackgroundVisibility(.visible)"))
    }

    func testGlassEffectStaysOnFloatingSurfaces() {
        let allowed: Set<String> = ["LumenUI/LumenCommandPalette.swift", "LumenUI/LumenToast.swift"]
        let users = swiftFiles().filter { $0.text.contains(".glassEffect(") }.map(\.path)
        XCTAssertTrue(Set(users).isSubset(of: allowed), "glassEffect outside the allowed floating surfaces: \(Set(users).subtracting(allowed))")
    }
}
