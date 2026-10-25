import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

/// One inactive-window look for every Lumen toolbar piece, the identity
/// at its ideal width inside a toolbar item.
@MainActor
final class LumenToolbarStateTests: XCTestCase {
    private func pixels(_ view: some View) throws -> (data: [UInt8], width: Int, height: Int) {
        let renderer = ImageRenderer(content: view.padding(4).background(Color.white))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width, height)
    }

    /// The largest channel spread (max − min) of any pixel: 0 for a grey image.
    private func maxChroma(_ view: some View) throws -> Int {
        let (data, _, _) = try pixels(view)
        var best = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            let rgb = [Int(data[i]), Int(data[i + 1]), Int(data[i + 2])]
            best = max(best, rgb.max()! - rgb.min()!)
        }
        return best
    }

    private var pieces: [(name: String, view: AnyView)] {
        [
            ("Identity", AnyView(LumenToolbarIdentity("Lumen", subtitle: "Workspace", systemImage: "lumen.lens", hue: .hueViolet))),
            ("Tasks", AnyView(LumenTaskCluster([
                LumenTaskAction("Build", systemImage: "hammer.fill") {},
                LumenTaskAction("Run", systemImage: "play.fill", role: .start) {},
                LumenTaskAction("Stop", systemImage: "stop.fill", role: .stop) {},
            ], activity: .idle()))),
            ("Working status", AnyView(LumenActivityStatus(.working("Indexing", progress: 0.5), width: 200))),
            ("Failed status", AnyView(LumenActivityStatus(.failed("Backend unavailable"), width: 200))),
        ]
    }

    func testLumensToolbarPiecesGreyOutTogetherInAnInactiveWindow() throws {
        // Calibrate SwiftUI's renderer independently of Lumen's dimming modifier. A failure in
        // a Lumen piece must never be used as the reason to skip its own assertion.
        let reference = Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 12, height: 12)
        XCTAssertGreaterThan(try maxChroma(reference), 60, "the reference swatch must render in color")
        try XCTSkipIf(try maxChroma(reference.saturation(0)) >= 6,
                      "ImageRenderer does not desaturate an independent SwiftUI reference swatch in this process")
        let activeChroma = try pieces.map { try maxChroma($0.view.environment(\.appearsActive, true)) }
        XCTAssertGreaterThan(activeChroma.max() ?? 0, 60,
                             "Active, build, run, the identity tile and the status keep their color")
        for piece in pieces {
            XCTAssertLessThan(try maxChroma(piece.view.environment(\.appearsActive, false)), 6,
                              "Inactive, \(piece.name) must go grey like the panel toggles")
        }
    }

    func testInactiveBandMatchesImageAndWindowPaths() throws {
        let view = LumenTitlebarBackground().environment(\.appearsActive, false)
        let variant = LumenSnapshot.Variant(themeID: LumenThemes.standardID, colorScheme: .light)
        let size = CGSize(width: 80, height: 40)
        let image = try XCTUnwrap(LumenSnapshot.png(of: view, size: size, variant: variant, registry: .core))
        let window = try XCTUnwrap(LumenSnapshot.png(of: view, size: size, variant: variant, registry: .core, renderer: .window))
        XCTAssertEqual(LumenSnapshot.compare(image, window).differingPixelFraction, 0)
    }

    func testNestedToolbarDimmingAppliesOnce() throws {
        let square = Color.black.frame(width: 10, height: 10)
            .lumenToolbarDimming().lumenToolbarDimming()
            .environment(\.appearsActive, false)
        let (data, width, height) = try pixels(square)
        let centre = ((height / 2) * width + width / 2) * 4
        // 55% black over white: about 115. Dimmed twice it would be about 178.
        XCTAssertEqual(Double(data[centre]), 255 * (1 - LumenToolbarDimming.inactiveOpacity), accuracy: 6)
    }

    func testIdentityYieldsWhenAToolbarItemProposesLess() {
        let identity = LumenToolbarIdentity("Lumen Catalog", subtitle: "~/Developer/Lumen", systemImage: "lumen.lens", hue: .hueViolet)
        let host = NSHostingController(rootView: identity)
        let ideal = host.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 60))
        let squeezed = host.sizeThatFits(in: CGSize(width: ideal.width - 30, height: 60))
        XCTAssertLessThanOrEqual(squeezed.width, ideal.width - 29.5, "The identity must honor a tight item proposal")
    }
}
