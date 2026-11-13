import XCTest
import SwiftUI
import LumenTokens
@testable import LumenUI

/// Design review 2026-11, note 24 (design review, 2026-11-13): one chrome style with no Drawn/Glass switch in
/// any window, and every top-bar button drawn as an app icon (`LumenToolbarIcon`): the glyph
/// centered on its own continuous-corner rounded square in app-icon proportions, face, light,
/// shadow and glyph drawn as one vector unit, lifted off the bar by a subtle elevation. It is
/// drawn by Lumen, never glass or the system's shared toolbar platter (`LumenToolbarPlatterGuardTests`
/// bans those), and never a key or plate layered behind a separate glyph.
@MainActor final class LumenToolbarIconTests: XCTestCase {
    private var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private func swiftFiles() -> [(path: String, text: String)] {
        guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            .compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).map { (url.path.replacingOccurrences(of: sources.path + "/", with: ""), $0) } }
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)
    }

    /// Source without comment lines, so doc comments can name what the code must not use.
    private func code(_ text: String) -> String {
        text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
    }

    // MARK: Source guards

    /// No window offers a chrome switch: the Catalog's Drawn/Glass toggle is gone, and nothing
    /// lists the chrome styles for a person to pick. The `.drawn` fallback (Reduce Transparency,
    /// offscreen rendering) stays internal.
    func testNoWindowOffersAChromeSwitch() {
        let banned = ["CatalogChromeToggle", "Use Glass Chrome", "Use Drawn Chrome", "LumenChromeStyle.allCases"]
        let offenders = swiftFiles().flatMap { file in banned.filter(file.text.contains).map { "\(file.path): \($0)" } }
        XCTAssertTrue(offenders.isEmpty, "A user-facing chrome switch is back: \(offenders)")
    }

    /// Every top-bar button is a toolbar icon: the shared toolbar icon style (build, run, stop, the
    /// sidebar toggle, Settings' Back and Forward and every app's toolbar icons), the panel toggles
    /// and New Tab. Neither the flat hover plate nor the layered key behind a glyph comes back.
    func testEveryTopBarButtonIsAToolbarIcon() throws {
        let components = try source("LumenUI/LumenComponents.swift")
        let style = try XCTUnwrap(components.range(of: "public struct LumenToolbarIconButtonStyle"))
        XCTAssertTrue(String(components[style.lowerBound...].prefix(2400)).contains("LumenToolbarIcon("),
                      "LumenToolbarIconButtonStyle no longer draws a toolbar icon")
        let workspace = try source("LumenUI/LumenWorkspace.swift")
        XCTAssertGreaterThanOrEqual(workspace.components(separatedBy: "LumenToolbarIconGlyphButtonStyle(").count - 1, 2,
                                    "The panel toggles and New Tab must be drawn as toolbar icons")
        let settings = code(try source("LumenUI/LumenSettings.swift"))
        XCTAssertEqual(settings.components(separatedBy: "LumenToolbarIconNativeButton(").count - 1, 2,
                       "Settings' Back and Forward must be toolbar icons (native NSButtons drawing LumenToolbarIcon)")
        XCTAssertTrue(code(try source("LumenUI/LumenToolbarIconNativeButton.swift")).contains("LumenToolbarIcon("),
                      "The native toolbar icon button no longer draws a toolbar icon")
        // A toolbar Menu becomes the system's menu item, which ignores button styles, so a pull-down
        // must be LumenToolbarIconMenu, not a Menu styled with the toolbar icon button style.
        let styledMenus = swiftFiles().filter { code($0.text).contains(".menuStyle(.button)\n            .buttonStyle(LumenToolbarIconButtonStyle())") }.map(\.path)
        XCTAssertTrue(styledMenus.isEmpty, "A toolbar Menu styled as an icon draws as a plain glyph; use LumenToolbarIconMenu: \(styledMenus)")
        XCTAssertTrue(code(try source("LumenCatalog/CatalogLibraryWindow.swift")).contains("LumenToolbarIconMenu("),
                      "The Image Library's filter pull-down must be a toolbar icon")
        // Groups of toolbar icons stand on the bar: nothing (no capsule, well or wash) is drawn behind
        // a LumenToolbarGroup or the panel toggles.
        for (file, type) in [("LumenUI/LumenPanelBar.swift", "public struct LumenToolbarGroup"), ("LumenUI/LumenWorkspace.swift", "public struct LumenPanelToggles")] {
            let text = code(try source(file))
            let start = try XCTUnwrap(text.range(of: type), "\(type) is gone")
            let end = text.range(of: "\n}\n", range: start.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
            let body = String(text[start.lowerBound..<end])
            XCTAssertFalse(body.contains(".background("), "\(type) draws a backing behind its toolbar icons")
        }
        let layered = swiftFiles().filter { ["LumenToolbarHoverPlate", "lumenToolbarKey", "LumenToolbarKey"].contains(where: $0.text.contains) }.map(\.path)
        XCTAssertTrue(layered.isEmpty, "A plate or key layered behind a toolbar glyph is back: \(layered)")
    }

    /// The icon is one drawing: face, rim, ring, shadow and glyph come from a single `Canvas` that
    /// resolves the glyph as a symbol, with nothing stacked behind or over it, and no glass.
    func testIconIsOneVectorDrawingNotGlass() throws {
        let icon = code(try source("LumenUI/LumenToolbarIcon.swift"))
        XCTAssertTrue(icon.contains("Canvas {") && icon.contains("resolveSymbol(id:"), "The icon must draw face and glyph in one Canvas")
        for banned in [".background", ".overlay", "ZStack", "glassEffect", "GlassEffectContainer", "Material", "toolbarBackground", ".bar)"] {
            XCTAssertFalse(icon.contains(banned), "The toolbar icon must be one drawn unit, not \(banned)")
        }
    }

    // MARK: Rendered

    private struct Pixels {
        let width: Int, height: Int, data: [UInt8]
        func luma(_ x: Int, _ y: Int) -> Double {
            let i = (y * width + x) * 4
            return 0.2126 * Double(data[i]) + 0.7152 * Double(data[i + 1]) + 0.0722 * Double(data[i + 2])
        }
    }

    private func pixels(_ view: some View, dark: Bool, scale: CGFloat) throws -> Pixels {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.lumenRendersOffscreen, true).environment(\.displayScale, scale)
            .environment(\.lumenIconAppearance, LumenIconAppearance(nil)))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Pixels(width: image.width, height: image.height, data: data)
    }

    /// A toolbar icon (or, `icon: false`, its bare glyph) with a 10 pt black square glyph on a flat
    /// ground, with 10 pt of ground around the canvas.
    private func sample(icon: Bool = true, side: CGFloat = 28, hovered: Bool = false, pressed: Bool = false, ground: Color) -> some View {
        let glyph = Rectangle().fill(Color.black).frame(width: 10, height: 10)
        return Group {
            if icon { LumenToolbarIcon(isHovered: hovered, isPressed: pressed, side: side) { glyph } } else { glyph.frame(width: side, height: side) }
        }
        .padding(10)
        .background(ground)
    }

    /// The run of pixels along row `y` whose luma passes `test`, around column `x`.
    private func run(_ p: Pixels, y: Int, from x: Int, _ test: (Double) -> Bool) -> ClosedRange<Int> {
        var lo = x, hi = x
        while lo > 0 && test(p.luma(lo - 1, y)) { lo -= 1 }
        while hi < p.width - 1 && test(p.luma(hi + 1, y)) { hi += 1 }
        return lo...hi
    }

    /// App-icon proportions: the face is 26/28 of the canvas, and the glyph, whatever its own size,
    /// is fitted so its longer side is half the face and centered on it. Holds at any side.
    func testIconHasAppIconProportions() throws {
        for side in [CGFloat(28), 56] {
            let scale: CGFloat = 4
            let p = try pixels(sample(side: side, ground: Color(white: 0.5)), dark: false, scale: scale)
            let mid = p.width / 2, row = p.height / 2
            // Light face (near white) left of the glyph, scanned out from just inside its edge.
            let faceSide = side * LumenToolbarIconGeometry.faceRatio
            // Scan each edge from just inside it: the glyph splits the face's run along the row.
            let inset = (side / 2 - faceSide / 2 + 2) * scale
            let left = run(p, y: row, from: Int((10 * scale + inset).rounded())) { $0 > 200 }
            let right = run(p, y: row, from: Int((CGFloat(p.width) - 10 * scale - inset).rounded())) { $0 > 200 }
            let face = left.lowerBound...right.upperBound
            let glyph = run(p, y: row, from: mid) { $0 < 40 }
            let faceWidth = Double(face.count) / scale, glyphWidth = Double(glyph.count) / scale
            XCTAssertEqual(faceWidth, Double(faceSide), accuracy: 1, "face width at side \(side)")
            XCTAssertEqual(glyphWidth, Double(faceSide * LumenToolbarIconGeometry.glyphRatio), accuracy: 0.75, "glyph is half the face at side \(side)")
            let faceCenter = Double(face.lowerBound + face.upperBound) / 2, glyphCenter = Double(glyph.lowerBound + glyph.upperBound) / 2
            XCTAssertEqual(glyphCenter, faceCenter, accuracy: 1.5, "glyph centered on the face at side \(side)")
        }
    }

    /// Vector at every scale: drawn at 8x, the face's edge and the glyph's edge each turn over in a
    /// pixel or two, as vector edges do; a raster scaled up would smear them across several.
    func testIconStaysSharpWhenEnlarged() throws {
        let p = try pixels(sample(ground: Color(white: 0.5)), dark: false, scale: 8)
        let row = p.height / 2
        func transition(from x0: Int, to x1: Int, low: Double, high: Double) -> Int {
            (min(x0, x1)...max(x0, x1)).filter { p.luma($0, row) > low && p.luma($0, row) < high }.count
        }
        let faceEdge = Int((10 + 1) * 8.0)   // the face's left edge at 8x
        XCTAssertLessThanOrEqual(transition(from: faceEdge - 6, to: faceEdge + 6, low: 140, high: 200), 3, "face edge is soft: drawn as raster?")
        let glyphEdge = Int((10 + 14 - 6.5) * 8.0)   // the glyph's left edge (13 pt glyph centered at 14 pt)
        XCTAssertLessThanOrEqual(transition(from: glyphEdge - 8, to: glyphEdge + 8, low: 40, high: 200), 3, "glyph edge is soft: scaled as raster?")
    }

    /// The icon stands off the bar: its shadow darkens the bar under its foot, hover raises it (the
    /// shadow reaches further), pressing settles it (the shadow tightens), and the bar beside it is
    /// untouched.
    func testIconLiftsOffTheBarAndShowsHoverAndPress() throws {
        for dark in [true, false] {
            let ground = dark ? Color(white: 0.16) : Color(white: 0.92)
            let bare = try pixels(sample(icon: false, ground: ground), dark: dark, scale: 2)
            let rest = try pixels(sample(ground: ground), dark: dark, scale: 2)
            let hover = try pixels(sample(hovered: true, ground: ground), dark: dark, scale: 2)
            let pressed = try pixels(sample(pressed: true, ground: ground), dark: dark, scale: 2)
            let mid = rest.width / 2, foot = 2 * (10 + 27)   // the face's foot at 2x
            XCTAssertLessThan(rest.luma(mid, foot + 1), bare.luma(mid, foot + 1) - 4, "no shadow under the icon (dark: \(dark))")
            XCTAssertLessThan(hover.luma(mid, foot + 6), rest.luma(mid, foot + 6) - 1, "hover does not raise the icon (dark: \(dark))")
            XCTAssertGreaterThan(pressed.luma(mid, foot + 4), rest.luma(mid, foot + 4) + 1, "press does not settle the icon (dark: \(dark))")
            XCTAssertEqual(rest.luma(2, rest.height / 2), bare.luma(2, bare.height / 2), accuracy: 1, "icon spills beside its canvas (dark: \(dark))")
        }
    }
}
