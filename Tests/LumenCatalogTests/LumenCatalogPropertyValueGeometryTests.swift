import AppKit
import SwiftUI
import XCTest
import LumenTokens
import LumenConformance
@testable import LumenCatalog
@_spi(LayoutAudit) @testable import LumenUI

extension LumenCatalogLayoutAuditTests {
    /// One capture supplies both OCR results and the actual value layout frames.
    func testCatalogPropertyValueGeometry() throws {
        LumenGlyph.register([.catalogPage])
        let original = try XCTUnwrap(subjects.first { $0.name == "Catalog" })
        var values: [LumenMarginElementFrame] = []
        let measured = Subject(original.name, source: original.source, size: original.size,
                               panel: original.panel, compact: original.compact, fullSize: original.fullSize,
                               outer: { root in
            AnyView(original.outer(root).onPreferenceChange(LumenMarginElementFrameKey.self) { values = $0 })
        }, make: original.make)
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: .dark),
                                       registry: LumenRegistry(packs: [.core, .code, .chart]))
        let window = host(measured, store: store)
        defer { window.close() }
        let capture = try LumenRenderedAudit.capture(in: window)
        let result = try LumenRenderedAudit.analyze(capture)
        let expected: Set<String> = ["Contributor", "0x1000a3e1c", "sparkles", "hue.violet"]
        var report = ["# Catalog property-value geometry", "window=\(window.frame)"]
        if let content = window.contentView {
            let hostScreen = window.convertToScreen(content.convert(content.bounds, to: nil))
            report.append("host bounds=\(content.bounds) screen=\(hostScreen) flipped=\(content.isFlipped)")
            for value in values where value.role.hasPrefix("property-value:") {
                let screen = CGRect(x: hostScreen.minX + value.frame.minX,
                                    y: hostScreen.maxY - value.frame.maxY,
                                    width: value.frame.width, height: value.frame.height)
                report.append("VALUE \(value.role) global=\(value.frame) screen=\(screen)")
            }
            func visit(_ view: NSView) {
                if let field = view as? NSTextField {
                    let screen = window.convertToScreen(field.convert(field.bounds, to: nil))
                    report.append("FIELD text=\(field.stringValue) type=\(type(of: field)) frame=\(field.frame) bounds=\(field.bounds) screen=\(screen) AX=\(field.accessibilityFrame()) AXvalue=\(String(describing: field.accessibilityValue()))")
                }
                for child in view.subviews { visit(child) }
            }
            visit(content)
        }
        for element in capture.elements {
            report.append("ELEMENT source=\(element.source) identity=\(element.identity) frame=\(element.frame) control=\(element.control) clip=\(String(describing: element.clip))")
        }
        for line in result.lines where expected.contains(line.text) {
            report.append("OCR text=\(line.text) recognized=\(line.frame) ink=\(line.inkPixels) confidence=\(line.confidence)")
        }
        report.append(contentsOf: result.findings.map { "FINDING \($0.rule) \($0.view): \($0.message)" })
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/test-artifacts/property-value-geometry")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = report.joined(separator: "\n") + "\n"
        print(text)
        try text.write(to: directory.appendingPathComponent("property-value-geometry.md"), atomically: true, encoding: .utf8)
        let bitmap = NSBitmapImageRep(cgImage: capture.image)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("property-value-geometry.png"))
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) })
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(NSApp.isActive)
    }
}
