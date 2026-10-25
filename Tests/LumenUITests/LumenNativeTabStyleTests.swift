import AppKit
import SwiftUI
import XCTest
import LumenTokens
import LumenConformance
@testable import LumenUI

/// Tab geometry, title fitting, and edge fades are measured without making windows visible.
@MainActor
final class LumenNativeTabStyleTests: XCTestCase {
    func testEveryTabIsVisibleOrReachableAndStripIsFilled() throws {
        var configurations = 0
        var truncatedTitles = 0
        var fittingTitles = 0
        for scale in [1.0, 1.3] {
            let metrics = LumenMetrics.resolving(nil, textScale: scale)
            let minimum = metrics.layout.controlHeight * 6 + 2 * metrics.stroke.hairline
            for count in 1...12 {
                for stripWidth: CGFloat in [240, 400, 660, 1000, 1800] {
                    for pins in Set([0, 1, count]) {
                        let available = stripWidth - 2 * metrics.spacing.s4
                        let intrinsic = (0..<count).map { CGFloat(140 + $0 * 13) * CGFloat(scale) }
                        let ideal = LumenDocumentTabLayout.widths(intrinsic: intrinsic, pinnedCount: pins,
                                                                 available: nil, minimum: minimum)
                        let overflow = ideal.reduce(0, +) > available
                        let viewport = available - (overflow ? metrics.layout.minimumHitTarget : 0)
                        let widths = LumenDocumentTabLayout.widths(intrinsic: intrinsic, pinnedCount: pins,
                                                                  available: viewport, minimum: min(minimum, viewport))
                        for selected in 0..<count {
                            let frames = LumenTabWindowLayout.frames(widths: widths, selected: selected, available: viewport)
                            assertCoverage(frames, viewport: viewport, selected: selected, overflow: overflow, count: count)
                            configurations += 1
                        }
                        let normal = widths.dropFirst(pins)
                        XCTAssertTrue(normal.allSatisfy { abs($0 - (normal.first ?? 0)) < 0.001 })
                        if !overflow { XCTAssertEqual(widths.reduce(0, +), viewport, accuracy: 0.001) }
                    }
                    // Exercise the actual production ViewThatFits/offscreen branch, not just its
                    // arithmetic: a clipped/dropped child or unfilled viewport fails this measurement.
                    let placement = LumenDocumentTabPlacement()
                    let titleMeasurements = LumenDocumentTabTitles()
                    let selected = count - 1
                    let tabs = documents(count: count)
                    let view = LumenDocumentTabBar(tabs, selection: .constant(tabs[selected].id), onClose: { _ in })
                        .lumenMetrics(metrics)
                        .environment(\.lumenRendersOffscreen, true)
                        .environment(\.lumenDocumentTabPlacement, placement)
                        .environment(\.lumenDocumentTabTitles, titleMeasurements)
                        .frame(width: stripWidth, height: metrics.layout.tabHeight)
                    let renderer = ImageRenderer(content: view)
                    XCTAssertNotNil(renderer.cgImage)
                    let placed = try XCTUnwrap(placement.measurement)
                    assertCoverage(placed.frames, viewport: placed.width, selected: selected,
                                   overflow: placed.overflow, count: count)
                    let expectedViewport = stripWidth - 2 * metrics.spacing.s4
                        - (placed.overflow ? metrics.layout.minimumHitTarget : 0)
                    XCTAssertEqual(placed.width, expectedViewport, accuracy: 0.01)
                    assertTitleWidths(titleMeasurements, frames: placed.frames, metrics: metrics)
                    truncatedTitles += titleMeasurements.truncations.values.filter { $0 }.count
                    fittingTitles += titleMeasurements.truncations.values.filter { !$0 }.count
                }
            }
        }
        XCTAssertGreaterThan(truncatedTitles, 0)
        XCTAssertGreaterThan(fittingTitles, 0)
        print("Title layout: \(truncatedTitles) truncated titles use all available width; \(fittingTitles) fitting titles are not truncated")
        print("Tab coverage: \(configurations) selected/pinned geometry cases; 120 production renders; counts 1...12, five widths, scales 1.0/1.3")
    }

    func testScrollEdgeFadesAndHiddenTruncationAudit() throws {
        // Exercise the mask's real alpha output at the start, middle and end, including an
        // unfaded fixed chevron region. The same edge views composite the live scroll viewport.
        for (count, selected) in [(1, 0), (12, 0), (12, 5), (12, 11)] {
            let viewport: CGFloat = 360
            let widths = LumenDocumentTabLayout.widths(intrinsic: Array(repeating: 146, count: count),
                pinnedCount: 0, available: viewport, minimum: 146)
            let frames = LumenTabWindowLayout.frames(widths: widths, selected: selected, available: viewport)
            let edges = LumenTabHiddenEdges(contentMinX: frames.first?.minX ?? 0,
                                           contentMaxX: frames.last?.maxX ?? 0, viewport: viewport)
            XCTAssertEqual(edges.leading, count > 1 && selected > 0)
            XCTAssertEqual(edges.trailing, count > 1 && selected < count - 1)
            let maskPlacement = LumenDocumentTabPlacement()
            let content = HStack(spacing: 0) {
                LumenTabWindowLayout(selectedIndex: selected, pinnedCount: 0, minimumWidth: 146,
                                     maskPlacement: maskPlacement) {
                    ForEach(0..<count, id: \.self) { _ in Color.white }
                    LumenTabScrollEdge(leading: true).hidden()
                    LumenTabScrollEdge(leading: false).hidden()
                }
                .mask { LumenTabRecordedMask(placement: maskPlacement) }
                .clipped()
                .frame(width: viewport, height: 24)
                Color.white.frame(width: 24, height: 24)
            }
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            func alpha(_ x: Int) throws -> CGFloat {
                try XCTUnwrap(bitmap.colorAt(x: x, y: 24)).alphaComponent
            }
            for (hidden, fromLeading) in [(edges.leading, true), (edges.trailing, false)] {
                let samples = try [0, 12, 24, 36, 47, 50].map { step in
                    try alpha(fromLeading ? step : 719 - step)
                }
                if hidden {
                    XCTAssertLessThan(samples[0], 0.04)
                    XCTAssertEqual(samples[2], 0.5, accuracy: 0.04)
                    XCTAssertGreaterThan(samples[4], 0.96)
                    XCTAssertTrue(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
                } else {
                    XCTAssertTrue(samples.allSatisfy { $0 > 0.99 })
                }
            }
            XCTAssertGreaterThan(try alpha(720), 0.99, "The fixed chevron region must not fade")
            XCTAssertGreaterThan(try alpha(743), 0.99)
            // The live native scroll host uses the equivalent normal alpha mask, without
            // rasterizing platform-backed views. Verify its full ramp against the cached path.
            let liveMask = ImageRenderer(content: Color.white
                .mask { LumenTabViewportMask(hidden: edges) }
                .frame(width: viewport, height: 24))
            liveMask.scale = 2
            let liveBitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(liveMask.cgImage))
            for x in 0..<720 {
                XCTAssertEqual(try XCTUnwrap(liveBitmap.colorAt(x: x, y: 24)).alphaComponent,
                               try alpha(x), accuracy: 0.01)
            }

            // Use the real production tree and the public audit, not a fabricated finding.
            let tabs = documents(count: count)
            for enabled in [true, false] {
                let findings = LumenConformance.truncation(sizes: [CGSize(width: 400, height: 32)]) {
                    LumenDocumentTabBar(tabs, selection: .constant(tabs[selected].id), onClose: { _ in })
                        .environment(\.lumenRendersOffscreen, true)
                        .environment(\.lumenReportsLayoutChecks, true)
                        .environment(\.lumenTabScrollEdgeFadeEnabled, enabled)
                }
                let clips = findings.filter { $0.message.contains("scroll edge without a fade") }
                XCTAssertEqual(clips.count, enabled ? 0 : (edges.leading ? 1 : 0) + (edges.trailing ? 1 : 0))
                if !enabled && edges.leading { XCTAssertTrue(clips.contains { $0.message.contains("leading") }) }
                if !enabled && edges.trailing { XCTAssertTrue(clips.contains { $0.message.contains("trailing") }) }
            }
        }
        // Arbitrary continuous offsets, resize-to-fit and elastic overscroll use the live
        // scroll geometry predicate, independent of selection-centering in cached fixtures.
        for (offset, viewport, leading, trailing): (CGFloat, CGFloat, Bool, Bool) in [
            (-8, 360, false, true), (0, 360, false, true), (1, 360, true, true),
            (700, 360, true, true), (1392, 360, true, false), (1400, 360, true, false),
            (0, 1752, false, false), (0, 1800, false, false)
        ] {
            let edges = LumenTabHiddenEdges(contentMinX: -offset, contentMaxX: 1752 - offset, viewport: viewport)
            XCTAssertEqual(edges.leading, leading)
            XCTAssertEqual(edges.trailing, trailing)
        }
        print("Scroll edges: start/middle/end/fit alpha ramps, fixed menu, continuous offsets and unfaded production negative controls passed")
    }

    private func assertTitleWidths(_ titles: LumenDocumentTabTitles, frames: [CGRect], metrics: LumenMetrics,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(titles.values.count, frames.count, file: file, line: line)
        XCTAssertEqual(titles.truncations.count, frames.count, file: file, line: line)
        for (id, measurement) in titles.values {
            // Outer hairline gap and one inner padding pair are the only horizontal insets.
            XCTAssertEqual(measurement.contentWidth, frames[0].width - 2 * metrics.stroke.hairline - 2 * metrics.spacing.s2,
                           accuracy: 0.01, file: file, line: line)
            XCTAssertEqual(measurement.available, measurement.contentWidth - measurement.leadingWidth,
                           accuracy: 0.01, file: file, line: line)
            if measurement.ideal > measurement.available {
                // SwiftUI rounds a fractional proposal to the rendering pixel grid (1 pt here).
                XCTAssertEqual(measurement.rendered, measurement.available, accuracy: 1,
                               "Truncated title did not receive all available width", file: file, line: line)
                XCTAssertEqual(titles.truncations[id], true, "Long title must truncate", file: file, line: line)
            } else {
                XCTAssertGreaterThanOrEqual(measurement.rendered, measurement.ideal, file: file, line: line)
                XCTAssertEqual(titles.truncations[id], false,
                               "Full title fits but was shortened", file: file, line: line)
            }
        }
    }

    /// Compare full pixels inside each inter-pill gap with the untouched strip at the same y.
    /// cacheDisplay is essential: ImageRenderer does not reproduce AppKit's stroke end ticks.
    private func gapInk(_ bitmap: NSBitmapImageRep, frames: [CGRect], viewport: CGFloat,
                        metrics: LumenMetrics, stripWidth: CGFloat) -> Int {
        let scale = CGFloat(bitmap.pixelsWide) / stripWidth
        var maximum = 0
        let height = CGFloat(bitmap.pixelsHigh) / scale
        let radius = LumenTabChrome.radius(metrics: metrics)
        let shape = LumenTabChrome.shape(radius: radius)
        func outline(_ frame: CGRect) -> Path {
            let rect = CGRect(x: metrics.spacing.s4 + frame.minX + metrics.stroke.hairline,
                              y: (height - metrics.layout.controlHeight) / 2,
                              width: frame.width - 2 * metrics.stroke.hairline, height: metrics.layout.controlHeight)
            // Exclude two pixels of cached antialiasing/placement rounding at the curved edge.
            // The negative control still catches the old ticks well outside this allowance.
            return shape.inset(by: -2 / scale).path(in: rect)
        }
        for index in frames.indices.dropLast() {
            let frame = frames[index]
            guard frame.maxX > 0 && frame.maxX < viewport else { continue }
            let edge = metrics.spacing.s4 + frame.maxX
            let first = Int(ceil((edge - radius - metrics.stroke.hairline) * scale))
            let last = Int(floor((edge + radius + metrics.stroke.hairline) * scale))
            let left = outline(frame)
            let right = outline(frames[index + 1])
            guard first >= 0 && last <= bitmap.pixelsWide else { continue }
            let top = Int(ceil((height - metrics.layout.controlHeight) / 2 * scale))
            let bottom = Int(floor((height + metrics.layout.controlHeight) / 2 * scale))
            for y in top..<bottom {
                var background = [Int](repeating: 0, count: 4)
                bitmap.getPixel(&background, atX: 0, y: y)
                for x in first..<last {
                    let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                    guard !left.contains(point) && !right.contains(point) else { continue }
                    var pixel = [Int](repeating: 0, count: 4)
                    bitmap.getPixel(&pixel, atX: x, y: y)
                    maximum = max(maximum, zip(pixel, background).map { abs($0 - $1) }.max() ?? 0)
                }
            }
        }
        return maximum
    }

    private func assertCoverage(_ frames: [CGRect], viewport: CGFloat, selected: Int, overflow: Bool, count: Int,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(frames.count, count, file: file, line: line)
        guard frames.count == count else { return }
        XCTAssertGreaterThan(viewport, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(frames[selected].maxX, viewport + 0.01, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frames[selected].minX, -0.01, file: file, line: line)
        var covered: CGFloat = 0
        for (index, frame) in frames.enumerated() {
            XCTAssertGreaterThan(frame.width, 0, file: file, line: line)
            if index > 0 { XCTAssertEqual(frames[index - 1].maxX, frame.minX, accuracy: 0.01, file: file, line: line) }
            let inside = frame.minX >= -0.01 && frame.maxX <= viewport + 0.01
            XCTAssertTrue(inside || overflow, "Hidden tab without scroll/overflow route", file: file, line: line)
            covered += max(0, min(viewport, frame.maxX) - max(0, frame.minX))
            // Selecting each overflow entry must bring that exact tab fully into view.
            let reached = LumenTabWindowLayout.frames(widths: frames.map(\.width), selected: index, available: viewport)[index]
            XCTAssertGreaterThanOrEqual(reached.minX, -0.01, file: file, line: line)
            XCTAssertLessThanOrEqual(reached.maxX, viewport + 0.01, file: file, line: line)
        }
        XCTAssertEqual(covered, viewport, accuracy: 0.01, "Unused space with hidden tabs", file: file, line: line)
    }

}

private let tabDocuments = [
    LumenDocumentTab(id: "edited", title: "Edited.swift", systemImage: "swift", hue: .hueOrange,
                     isEdited: true, isPinned: false, accent: .hueBlue),
    LumenDocumentTab(id: "hovered", title: "Hovered.swift", systemImage: "swift", hue: .hueOrange),
    LumenDocumentTab(id: "plain", title: "README.md", systemImage: "doc.text", hue: .fgTertiary),
]
private func documents(count: Int) -> [LumenDocumentTab] {
    if count <= tabDocuments.count { return Array(tabDocuments.prefix(count)) }
    return tabDocuments + (3..<count).map {
        LumenDocumentTab(id: "file-\($0)", title: "Document\($0).swift", systemImage: "swift", hue: .hueOrange)
    }
}
private let tabPanels = [
    LumenPanelTab(id: "debug", title: "Debug Console", systemImage: "ladybug.fill", hue: .hueBlue),
    LumenPanelTab(id: "extension", title: "Extension Console", systemImage: "puzzlepiece.extension.fill", hue: .hueBlue),
    LumenPanelTab(id: "transcript", title: "Transcript", systemImage: "doc.plaintext", hue: .hueBlue),
]
