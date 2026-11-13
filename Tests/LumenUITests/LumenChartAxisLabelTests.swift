import AppKit
import SwiftUI
import Vision
import XCTest
import LumenTokens
@testable import LumenUI

/// Design review 2026-11 #9: a y-axis tick flush against its value read as a minus sign, so a
/// chart of positive counts showed "-20", "-15", "-10". Rendered and read back with the audit's OCR.
@MainActor
final class LumenChartAxisLabelTests: XCTestCase {
    func testPositiveAxisValuesNeverReadAsNegative() throws {
        let data = [("Mon", 4.0), ("Tue", 12), ("Wed", 20), ("Thu", 9), ("Fri", 16)]
            .map { LumenChartDatum(label: $0.0, value: $0.1) }
        for dark in [false, true] {
            let texts = try recognizedTexts(LumenBarChart(data), dark: dark)
            print("CHART-OCR dark=\(dark) \(texts)")
            XCTAssertTrue(texts.contains { $0.contains("20") || $0.contains("15") || $0.contains("10") },
                          "OCR must read the y-axis values at all (dark=\(dark)): \(texts)")
            let negative = texts.filter { $0.range(of: #"^[-–—−]\s?\d"#, options: .regularExpression) != nil }
            XCTAssertEqual(negative, [], "Positive axis values read as negative (dark=\(dark))")
        }
    }

    private func recognizedTexts(_ chart: some View, dark: Bool) throws -> [String] {
        let variant = LumenSnapshot.Variant(themeID: LumenThemes.standardID, colorScheme: dark ? .dark : .light)
        let store = LumenSnapshot.store(for: variant, registry: LumenRegistry(packs: [.core, .chart]))
        let size = CGSize(width: 420, height: 220)
        let content = chart
            .frame(width: size.width, height: size.height)
            .environment(\.lumenPalette, store.resolvedPalette())
            .environment(\.lumenStore, store)
            .environment(\.colorScheme, variant.colorScheme)
            .environment(\.lumenRendersOffscreen, true)
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.setContentSize(size)
        defer { window.close() }
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let request = try LumenAuditOCR.makeRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
