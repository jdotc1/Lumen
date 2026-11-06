import AppKit
import SwiftUI
import XCTest
import LumenTestSupport
@testable import LumenUI

@MainActor final class LumenNativeSourceListInsetTests: XCTestCase {
    private final class Rows: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        let item = NSObject()
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? 1 : 0 }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { self.item }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            NSView(frame: .zero)
        }
    }

    func testMeasureHostedNativeSelectionInset() throws {
        let rows = Rows()
        let outline = NSOutlineView(frame: CGRect(x: 0, y: 0, width: 240, height: 160))
        outline.style = .sourceList
        outline.headerView = nil
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        column.width = 240
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = rows
        outline.delegate = rows
        let scroll = NSScrollView(frame: outline.frame)
        scroll.documentView = outline
        let window = LumenHeadlessHost.window(contentRect: outline.frame,
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        LumenHeadlessHost.prepare(window)
        defer { window.close() }
        outline.reloadData()
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        for _ in 0..<20 {
            scroll.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let row = try XCTUnwrap(outline.rowView(atRow: 0, makeIfNecessary: true))
        print("NATIVE-SOURCE-LIST outline=\(outline.frame) bounds=\(outline.bounds) rowRect=\(outline.rect(ofRow: 0)) rowFrame=\(row.frame) rowBounds=\(row.bounds) spacing=\(outline.intercellSpacing) style=\(outline.effectiveStyle.rawValue)")
        func dump(_ view: NSView, depth: Int) {
            print("NATIVE-VIEW depth=\(depth) type=\(type(of: view)) frame=\(view.frame)")
            if let layer = view.layer {
                func layers(_ layer: CALayer, depth: Int) {
                    print("NATIVE-LAYER depth=\(depth) type=\(type(of: layer)) frame=\(layer.frame)")
                    for child in layer.sublayers ?? [] { layers(child, depth: depth + 1) }
                }
                layers(layer, depth: depth)
            }
            for child in view.subviews { dump(child, depth: depth + 1) }
        }
        dump(outline, depth: 0)
        let bitmap = try XCTUnwrap(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
        scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/source-list-measurements")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("native-source-list.png"))
        XCTAssertEqual(outline.effectiveStyle, .sourceList)
        XCTAssertTrue(row.isSelected)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(NSApp.isActive)
    }

    func testHostedPlateEqualsNativeSelectionInsetAndDeclaresNestedMargin() throws {
        let rows = Rows()
        let outline = NSOutlineView(frame: CGRect(x: 0, y: 0, width: 240, height: 160))
        outline.style = .sourceList
        outline.headerView = nil
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        column.width = 240
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = rows
        outline.delegate = rows
        let scroll = NSScrollView(frame: outline.frame)
        scroll.documentView = outline
        let nativeWindow = LumenHeadlessHost.window(contentRect: outline.frame,
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        nativeWindow.isReleasedWhenClosed = false
        nativeWindow.contentView = scroll
        LumenHeadlessHost.prepare(nativeWindow)
        defer { nativeWindow.close() }
        outline.reloadData()
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        var frames: [LumenMarginElementFrame] = []
        let root = LumenSourceList([.init(id: "selected", title: "Selected")], selection: .constant("selected"))
            .lumenScaffoldMargin(16)
            .lumenPaletteRoot()
            .onPreferenceChange(LumenMarginElementFrameKey.self) { frames = $0 }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        LumenHeadlessHost.prepare(window)
        defer { window.close() }
        for _ in 0..<25 {
            scroll.layoutSubtreeIfNeeded()
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let nativeRow = try XCTUnwrap(outline.rowView(atRow: 0, makeIfNecessary: true))
        let effects = nativeRow.subviews.compactMap { $0 as? NSVisualEffectView }
        let nativePlate = try XCTUnwrap(effects.first(where: { $0.material == .selection }),
            "Native effect materials: \(effects.map { $0.material.rawValue })")
        let nativeLeading = nativePlate.frame.minX - nativeRow.bounds.minX
        let nativeTrailing = nativeRow.bounds.maxX - nativePlate.frame.maxX
        let row = try XCTUnwrap(frames.first(where: { $0.role == "source-list-row" }))
        let plate = try XCTUnwrap(frames.first(where: { $0.role == "list-row-plate" }))
        print("SOURCE-LIST-GUARANTEE nativeRow=\(nativeRow.bounds) nativePlate=\(nativePlate.frame) nativeInset=(\(nativeLeading),\(nativeTrailing)) lumenRow=\(row.frame) lumenPlate=\(plate.frame)")
        XCTAssertGreaterThan(nativeLeading, 0)
        XCTAssertEqual(plate.frame.minX - row.frame.minX, nativeLeading, accuracy: 0.01)
        XCTAssertEqual(row.frame.maxX - plate.frame.maxX, nativeTrailing, accuracy: 0.01)
        let report = LumenWindowAuditReports.record(for: window)
        let declaration = try XCTUnwrap(report.scaffoldMargins.first(where: { $0.margin == nativeLeading }))
        print("SOURCE-LIST-MARGIN declaration=\(declaration.frame) margin=\(declaration.margin) depth=\(declaration.depth)")
        XCTAssertGreaterThan(declaration.depth, 0)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(nativeWindow.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(NSApp.isActive)
    }

}
