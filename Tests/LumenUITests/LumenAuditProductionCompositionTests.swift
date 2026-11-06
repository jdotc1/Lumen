import AppKit
import SwiftUI
import Observation
import XCTest
import LumenTestSupport
import LumenTokens
import LumenConformance
@_spi(LayoutAudit) @testable import LumenUI
@testable import LumenCatalog

@MainActor final class LumenAuditProductionCompositionTests: XCTestCase {
    func testProductionBannerAndFourPointDisassemblyLines() throws {
        let views: [(String, AnyView, CGSize)] = [
            ("banner", AnyView(CatalogOSBanner().padding(20)), CGSize(width: 748, height: 150)),
            ("disassembly", AnyView(VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(["push rbp", "mov rbp, rsp", "sub rsp, 0x20", "call parse_header", "test eax, eax", "jne 0x100003f40", "leave", "ret"].enumerated()), id: \.offset) { index, line in
                    HStack(spacing: 16) {
                        Text(String(format: "0x%08X", 0x1000_3F00 + index * 4))
                        Text(line)
                    }.font(.body.monospaced())
                }
            }.padding(20)), CGSize(width: 480, height: 260)),
        ]
        for (name, view, size) in views {
            let window = host(view, size: size)
            defer { window.close() }
            let capture = try LumenRenderedAudit.capture(in: window)
            let result = try LumenRenderedAudit.analyze(capture)
            for line in result.lines { print("LINE \(name) \(line.text) word=\(line.frame) observation=\(String(describing: line.observationFrame)) glyphBand=\(String(describing: line.glyphBand))") }
            XCTAssertGreaterThan(result.lines.count, 1)
            XCTAssertFalse(result.findings.contains { $0.rule == "rendered-text-geometry" && $0.message.contains("overlaps") }, "\(result.findings)")
            // Reproduce the production admission failure on this real composition: a padded
            // recognition box includes the next baseline, while Vision's line geometry stays
            // attached to its own glyphs. No synthetic bitmap or hand-drawn text substitutes.
            let padded = result.lines.map { line in
                LumenRenderedAudit.Line(text: line.text,
                    frame: CGRect(x: line.frame.minX, y: line.frame.minY - 20,
                                  width: line.frame.width, height: line.frame.height + 20),
                    confidence: line.confidence, inkPixels: line.inkPixels,
                    observationFrame: line.observationFrame, glyphBand: line.glyphBand)
            }
            XCTAssertTrue(padded.allSatisfy { $0.glyphBand != nil })
            let broad = try LumenRenderedAudit.analyze(capture, recognizedLines: padded)
            XCTAssertFalse(broad.findings.contains { $0.rule == "rendered-text-geometry" && $0.message.contains("overlaps") }, "\(broad.findings)")
            print("PRODUCTION-LINES \(name) findings=\(result.findings) broad=\(broad.findings)")
        }
    }

    func testRealFieldWellsDisabledFocusedAndClipped() throws {
        for mode in ["address", "disabled", "focused", "clipped"] {
            let field: AnyView
            if mode == "address" || mode == "clipped" {
                let address = LumenAddressField(text: .constant("100003f0c")) { _ in }.frame(width: 320)
                field = mode == "clipped" ? AnyView(address.frame(width: 180, alignment: .leading).clipped()) : AnyView(address)
            } else {
                field = AnyView(LumenTextField("Bundled runtime", text: .constant(mode == "disabled" ? "" : "Focused runtime"))
                    .disabled(mode == "disabled").frame(width: 320))
            }
            let window = host(AnyView(field.padding(20)), size: CGSize(width: 380, height: 120))
            defer { window.close() }
            if mode == "focused" || mode == "address" || mode == "clipped" {
                let input = try XCTUnwrap(descendants(window.contentView!).compactMap { $0 as? NSTextField }.first { $0.isEditable })
                XCTAssertTrue(window.makeFirstResponder(input))
                settle(window)
            }
            let capture = try LumenRenderedAudit.capture(in: window)
            let result = try LumenRenderedAudit.analyze(capture)
            print("FIELD-WELL \(mode) owners=\(capture.compositeOwners.filter { $0.identity.hasPrefix("lumen-composite:") }.map { "\($0.frame) clip=\(String(describing: $0.clip))" }) clips=\(capture.clips) findings=\(result.findings)")
            if mode == "clipped" {
                XCTAssertTrue(result.findings.contains { $0.rule == "rendered-edge" }, "Clipped real well must fail: \(result.findings)")
            } else { XCTAssertTrue(result.findings.isEmpty, "\(mode): \(result.findings)") }
        }
    }

    func testDarkProductionSettingsSearchAndOverlaidLumenInk() throws {
        let window = host(AnyView(LumenSettingsSidebarView(CatalogSettings.windowCategories,
            initialSelection: CatalogSettings.initialSelection)), size: CGSize(width: 980, height: 720))
        defer { window.close() }
        let search = try XCTUnwrap(descendants(window.contentView!).compactMap { $0 as? NSSearchField }.first)
        let searchFrame = window.convertToScreen(search.convert(search.bounds, to: nil))
        for view in descendants(search) {
            print("SEARCH-SUBVIEW type=\(String(reflecting: type(of: view))) frame=\(window.convertToScreen(view.convert(view.bounds, to: nil))) hidden=\(view.isHiddenOrHasHiddenAncestor) alpha=\(view.alphaValue)")
        }
        let native = try LumenRenderedAudit.capture(in: window)
        print("SEARCH-FRAMES search=\(searchFrame) chrome=\(native.nativeControlChrome) preserving=\(native.nativeMaskPreservingInk) drawing=\(native.drawingBounds)")
        let result = try LumenRenderedAudit.analyze(native)
        XCTAssertFalse(zip(result.findings, result.findingRects).contains { $0.1.intersects(searchFrame) }, "\(result.findings)")
        // Real Lumen drawing remains over the native frame, rather than replacing the search.
        let stroke = SearchOverlapStroke(frame: search.bounds)
        stroke.clipsToBounds = true
        search.addSubview(stroke)
        let overlap = try LumenRenderedAudit.capture(in: window)
        let failed = try LumenRenderedAudit.analyze(overlap)
        XCTAssertTrue(zip(failed.findings, failed.findingRects).contains { $0.1.intersects(searchFrame) }, "\(failed.findings)")
        print("SEARCH-PRODUCTION native=\(result.findings) overlaid=\(failed.findings)")
    }

    func testActuallyOverprintedDisassemblyStringsFail() throws {
        var frames: [LumenMarginElementFrame] = []
        let root = VStack(alignment: .leading, spacing: 4) {
            Text("mov rbp, rsp").lumenReportsMarginElement("overprint-first")
            Text("sub rsp, 0x20").lumenReportsMarginElement("overprint-second").offset(y: -16)
        }.font(.body.monospaced()).padding(20)
            .onPreferenceChange(LumenMarginElementFrameKey.self) { frames = $0 }
        let window = host(AnyView(root), size: CGSize(width: 320, height: 140))
        defer { window.close() }
        let hosted = try LumenRenderedAudit.capture(in: window)
        let measured = try ["overprint-first", "overprint-second"].map { role in
            let local = try XCTUnwrap(frames.first { $0.role == role }).frame
            // Preference geometry is SwiftUI global (top-left); the audit is screen (bottom-left).
            return CGRect(x: hosted.frame.minX + local.minX, y: hosted.frame.maxY - local.maxY,
                          width: local.width, height: local.height)
        }
        let lines = zip(["mov rbp, rsp", "sub rsp, 0x20"], measured).map {
            LumenRenderedAudit.Line(text: $0.0, frame: $0.1.insetBy(dx: -2, dy: -8),
                confidence: 1, inkPixels: 100, glyphBand: $0.1)
        }
        // Isolate the text-ink rule from semantic-frame overlap using the same real pixels.
        let capture = LumenRenderedAudit.Capture(image: hosted.image, frame: hosted.frame, usable: hosted.usable,
            chrome: hosted.chrome, exclusions: hosted.exclusions, elements: [], clips: [], drawingBounds: [],
            margin: nil, scaffoldMargins: [], reports: [])
        let result = try LumenRenderedAudit.analyze(capture, recognizedLines: lines)
        XCTAssertTrue(result.findings.contains { $0.rule == "rendered-text-geometry" && $0.message.contains("glyph ink overlaps") }, "\(result.findings)")
        print("OVERPRINTED-LINES bands=\(measured) findings=\(result.findings)")
    }

    func testLumenInkInsideNativeSearchAccessoryStillFails() throws {
        let window = host(AnyView(LumenSettingsSidebarView(CatalogSettings.windowCategories,
            initialSelection: CatalogSettings.initialSelection)), size: CGSize(width: 980, height: 720))
        defer { window.close() }
        let search = try XCTUnwrap(descendants(window.contentView!).compactMap { $0 as? NSSearchField }.first)
        let button = try XCTUnwrap(descendants(search).compactMap { $0 as? NSButton }.first { !$0.isHiddenOrHasHiddenAncestor })
        let nativeButton = window.convertToScreen(button.convert(button.bounds, to: nil))
        let cellButton = try XCTUnwrap(LumenNativeControlChrome.searchButtonFrames(in: window).first { $0.intersects(nativeButton) })
        let covered = cellButton.intersection(nativeButton)
        XCTAssertFalse(covered.isEmpty)
        let accessory = search.convert(window.convertFromScreen(covered), from: nil)
        let stroke = SearchOverlapStroke(frame: accessory)
        stroke.clipsToBounds = true
        search.addSubview(stroke)
        let capture = try LumenRenderedAudit.capture(in: window)
        let frame = window.convertToScreen(stroke.convert(stroke.bounds, to: nil))
        XCTAssertTrue(capture.exclusions.contains { $0.insetBy(dx: -2, dy: -2).contains(frame) })
        let result = try LumenRenderedAudit.analyze(capture)
        XCTAssertTrue(zip(result.findings, result.findingRects).contains { $0.1.intersects(frame) }, "\(result.findings)")
        print("NATIVE-ACCESSORY-OVERLAY frame=\(frame) exclusions=\(capture.exclusions) findings=\(result.findings)")
    }

    func testRealFieldWellClippedByWindowStillFails() throws {
        let window = host(AnyView(LumenAddressField(text: .constant("100003f0c")) { _ in }
            .frame(width: 320).frame(width: 140, alignment: .leading).padding(20)), size: CGSize(width: 180, height: 120))
        defer { window.close() }
        let input = try XCTUnwrap(descendants(window.contentView!).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        XCTAssertTrue(window.makeFirstResponder(input))
        settle(window)
        let capture = try LumenRenderedAudit.capture(in: window)
        let well = try XCTUnwrap(capture.compositeOwners.first { $0.identity.hasPrefix("lumen-composite:") })
        XCTAssertFalse(capture.frame.contains(well.frame))
        let result = try LumenRenderedAudit.analyze(capture)
        XCTAssertTrue(zip(result.findings, result.findingRects).contains {
            $0.0.rule == "rendered-edge" && ($0.1.minX <= capture.frame.minX || $0.1.maxX >= capture.frame.maxX)
        }, "\(result.findings)")
        print("WINDOW-CLIPPED-WELL window=\(capture.frame) well=\(well.frame) findings=\(result.findings)")
    }

    func testSolidLumenInkInsideNativeSearchFieldStillFails() throws {
        let window = host(AnyView(LumenSettingsSidebarView(CatalogSettings.windowCategories,
            initialSelection: CatalogSettings.initialSelection)), size: CGSize(width: 980, height: 720))
        defer { window.close() }
        let search = try XCTUnwrap(descendants(window.contentView!).compactMap { $0 as? NSSearchField }.first)
        let stroke = SearchOverlapStroke(frame: search.bounds)
        stroke.fillsBounds = true
        stroke.clipsToBounds = true
        search.addSubview(stroke)
        let capture = try LumenRenderedAudit.capture(in: window)
        let frame = window.convertToScreen(stroke.convert(stroke.bounds, to: nil))
        let result = try LumenRenderedAudit.analyze(capture)
        XCTAssertTrue(zip(result.findings, result.findingRects).contains { $0.0.rule == "rendered-edge" && $0.1.intersects(frame) }, "\(result.findings)")
        print("SOLID-NATIVE-OVERLAY frame=\(frame) findings=\(result.findings)")
    }

    func testSolidAppControlInkInsideNativeSearchFieldStillFails() throws {
        let window = host(AnyView(LumenSettingsSidebarView(CatalogSettings.windowCategories,
            initialSelection: CatalogSettings.initialSelection)), size: CGSize(width: 980, height: 720))
        defer { window.close() }
        let search = try XCTUnwrap(descendants(window.contentView!).compactMap { $0 as? NSSearchField }.first)
        let stroke = SearchOverlapControl(frame: search.bounds)
        stroke.setAccessibilityElement(false)
        stroke.clipsToBounds = true
        search.addSubview(stroke)
        let capture = try LumenRenderedAudit.capture(in: window)
        let frame = window.convertToScreen(stroke.convert(stroke.bounds, to: nil))
        let result = try LumenRenderedAudit.analyze(capture)
        XCTAssertTrue(zip(result.findings, result.findingRects).contains { $0.0.rule == "rendered-edge" && $0.1.intersects(frame) }, "\(result.findings)")
        print("SOLID-CONTROL-NATIVE-OVERLAY frame=\(frame) findings=\(result.findings)")
    }

    func testSplitProductionSidebarUsesSingleCharacterRows() throws {
        let window = host(AnyView(SplitWorkspaceDemo()), size: CGSize(width: 1440, height: 900))
        defer { window.close() }
        let result = try LumenRenderedAudit.analyze(LumenRenderedAudit.capture(in: window))
        XCTAssertTrue(result.observes("Targets"))
        XCTAssertTrue(result.observes("Functions"))
        XCTAssertTrue(result.findings.isEmpty, "\(result.findings)")
        XCTAssertTrue(result.detectorRegions.contains { !$0.characterBoxes.isEmpty })
        let statistics = result.lines.filter { $0.text == "1" || $0.text == "5" }
        XCTAssertEqual(statistics.count, 2)
        XCTAssertTrue(statistics.allSatisfy { ($0.glyphBand?.height ?? .infinity) < 2 * ($0.observationFrame?.height ?? 0) })
        print("SPLIT-ROWS statistics=\(statistics) detectorRows=\(result.detectorRegions.map { $0.rows.count }) findings=\(result.findings)")
    }

    func testWorkspaceProcessActionBesideDividerAndClippedText() throws {
        let window = host(AnyView(SampleWorkspace()), size: SampleWorkspace.defaultSize)
        defer { window.close() }
        let result = try LumenRenderedAudit.analyze(LumenRenderedAudit.capture(in: window))
        XCTAssertTrue(result.observes("Attach to Process"))
        XCTAssertFalse(result.findings.contains { $0.view.contains("Attach") }, "\(result.findings)")
        let clipped = host(AnyView(Color.black), size: CGSize(width: 180, height: 100))
        defer { clipped.close() }
        let boundary = NSView(frame: CGRect(x: 20, y: 25, width: 12, height: 40))
        boundary.clipsToBounds = true
        let label = NSTextField(labelWithString: "MMMMMMMMMMMM")
        label.font = .monospacedSystemFont(ofSize: 32, weight: .black)
        label.textColor = .white
        label.frame = CGRect(x: 0, y: 0, width: 320, height: 40)
        boundary.addSubview(label)
        clipped.contentView!.addSubview(boundary)
        let cutCapture = try LumenRenderedAudit.capture(in: clipped)
        let textFrame = clipped.convertToScreen(label.convert(label.bounds, to: nil))
        let negative = try LumenRenderedAudit.analyze(cutCapture, recognizedLines: [
            .init(text: label.stringValue, frame: textFrame, confidence: 1, inkPixels: 100, glyphBand: textFrame)
        ])
        XCTAssertTrue(negative.findings.contains { $0.rule == "rendered-edge" && $0.view == label.stringValue }, "\(negative.findings)")
        print("WORKSPACE-PROCESS-ACTION findings=\(result.findings); clippedText=\(negative.findings)")
    }

    func testTransparentProductionHelperDoesNotPreserveNativeDividerButStrokeDoes() throws {
        let root = Color.white.frame(maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: .constant(true)) { Color.white.inspectorColumnWidth(220) }
            .background(CatalogToolbarReport())
        let window = host(AnyView(root), size: CGSize(width: 720, height: 360))
        defer { window.close() }
        let native = try LumenRenderedAudit.capture(in: window)
        let divider = try XCTUnwrap(LumenNativeSplitDividers.frames(in: window).first)
        let helper = try XCTUnwrap(descendants(window.contentView!).first { $0 is CatalogToolbarReport.ReportView })
        let helperFrame = window.convertToScreen(helper.convert(helper.bounds, to: nil))
        XCTAssertTrue(helperFrame.contains(divider))
        XCTAssertFalse(native.nativeMaskPreservingSources.contains { $0.viewClass.contains("ReportView") })
        let result = try LumenRenderedAudit.analyze(native)
        XCTAssertFalse(zip(result.findings, result.findingRects).contains { $0.1.intersects(divider) }, "\(result.findings)")
        let strokeFrame = window.contentView!.convert(window.convertFromScreen(
            CGRect(x: divider.minX, y: divider.midY, width: 1, height: 24)), from: nil)
        let stroke = SearchOverlapStroke(frame: strokeFrame)
        stroke.fillsBounds = true
        stroke.clipsToBounds = true
        window.contentView!.addSubview(stroke)
        let painted = try LumenRenderedAudit.capture(in: window)
        XCTAssertTrue(painted.nativeMaskPreservingSources.contains { $0.viewClass.contains("SearchOverlapStroke") })
        let negative = try LumenRenderedAudit.analyze(painted)
        XCTAssertTrue(zip(negative.findings, negative.findingRects).contains { $0.1.intersects(divider) }, "\(negative.findings)")
        print("HELPER-DIVIDER helper=\(helperFrame) divider=\(divider) native=\(result.findings) stroke=\(negative.findings) sources=\(painted.nativeMaskPreservingSources)")
    }

    func testProductionSidebarWashDeclarationAndForeground() throws {
        let window = host(AnyView(SampleWorkspace()), size: SampleWorkspace.defaultSize)
        defer { window.close() }
        let capture = try LumenRenderedAudit.capture(in: window)
        let wash = try XCTUnwrap(capture.fullBleedWashes.first)
        let sidebar = try XCTUnwrap(capture.fullBleedBackgrounds.first { $0.frame.minX == capture.frame.minX })
        let result = try LumenRenderedAudit.analyze(capture)
        XCTAssertTrue(result.findings.isEmpty, "\(result.findings)")
        var undeclared = capture
        undeclared.fullBleedWashes = []
        let missing = try LumenRenderedAudit.analyze(undeclared, recognizedLines: result.lines)
        XCTAssertTrue(missing.findings.contains { $0.rule == "rendered-margin" }, "An undeclared gradient to the edge must fail: \(missing.findings)")
        let frame = CGRect(x: sidebar.frame.minX + 2, y: sidebar.frame.maxY - 26, width: 4, height: 12)
        let stroke = SearchOverlapStroke(frame: window.contentView!.convert(window.convertFromScreen(frame), from: nil))
        stroke.fillsBounds = true
        window.contentView!.addSubview(stroke)
        let painted = try LumenRenderedAudit.capture(in: window)
        let negative = try LumenRenderedAudit.analyze(painted, recognizedLines: result.lines)
        XCTAssertTrue(zip(negative.findings, negative.findingRects).contains {
            $0.0.rule == "rendered-margin" && $0.1.intersects(frame)
        }, "A real stroke over the wash in its margin must fail: \(negative.findings)")
        print("COMPOSITED-WASH frame=\(wash.frame) stops=\(wash.stops) background=\(sidebar) plain=\(result.findings.count) undeclared=\(missing.findings.count) stroke=\(negative.findings)")
    }

    func testWorkspaceDeclaresSharedBandAndPreservesMarginChecks() throws {
        let window = workspaceHost()
        defer { window.close() }
        let capture = try LumenRenderedAudit.capture(in: window)
        let bands = capture.fullBleedBackgrounds.filter { $0.frame.height == 22 && $0.cornerRadius > 0 }
        XCTAssertEqual(bands.count, 1)
        let result = try LumenRenderedAudit.analyze(capture)
        XCTAssertTrue(result.findings.isEmpty, "\(result.findings)")
        print("WORKSPACE-SHARED-BAND frames=\(bands.map(\.frame)) findings=\(result.findings)")
    }

    func testSharedCodeListingBandPreservesMarginTextChecks() throws {
        let overlay = CodeBandOverlayState()
        let window = host(AnyView(SharedCodeListingFixture(overlay: overlay)), size: CGSize(width: 360, height: 180))
        defer { window.close() }
        let capture = try LumenRenderedAudit.capture(in: window)
        let band = try XCTUnwrap(capture.fullBleedBackgrounds.first { $0.cornerRadius > 0 })
        XCTAssertEqual(band.frame.maxX, capture.frame.maxX, accuracy: 0.5)
        let result = try LumenRenderedAudit.analyze(capture)
        XCTAssertTrue(result.findings.isEmpty, "\(result.findings)")
        let frame = CGRect(x: band.frame.maxX - 13, y: band.frame.midY - 9, width: 13, height: 18)
        overlay.enabled = true
        settle(window)
        let painted = try LumenRenderedAudit.capture(in: window)
        let negative = try LumenRenderedAudit.analyze(painted, recognizedLines: result.lines + [
            .init(text: "M", frame: frame, confidence: 1, inkPixels: 100, glyphBand: frame)
        ])
        XCTAssertTrue(zip(negative.findings, negative.findingRects).contains {
            $0.0.rule == "rendered-margin" && $0.1.intersects(frame)
        }, "Text on the shared band in its margin must fail: \(negative.findings)")
        print("SHARED-CODE-LISTING band=\(band.frame) plain=\(result.findings) marginText=\(negative.findings)")
    }

    @Observable final class CodeBandOverlayState { var enabled = false }

    private struct SharedCodeListingFixture: View {
        let overlay: CodeBandOverlayState
        var body: some View {
            LumenCodeListing([[LumenCodeRun("mov x0, x1")], [LumenCodeRun("ret")]], currentLine: 0)
                .overlay(alignment: .topTrailing) {
                    Text("M").font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white).frame(width: 13, height: 18)
                        .padding(.top, LumenMetrics.standard.spacing.s4)
                        .opacity(overlay.enabled ? 1 : 0)
                }
                .padding(.leading, 20).padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func workspaceHost() -> NSWindow {
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: .dark),
                                       registry: LumenRegistry(packs: [.core, .code, .chart]))
        let root = WorkspaceDemo().lumenPaletteRoot(store: store).lumenDensityRoot(store: store)
            .lumenMetrics(.standard).lumenTextScale(1).lumenChromeStyle(.drawn)
            .frame(minWidth: 1000, minHeight: 660)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let size = CGSize(width: 1200, height: 800)
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Workspace"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.setContentSize(size)
        LumenHeadlessHost.prepare(window)
        LumenHeadlessHost.order(window)
        settle(window)
        return window
    }

    private final class SearchOverlapControl: NSControl {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemRed.setFill()
            bounds.fill()
        }
    }

    private final class SearchOverlapStroke: NSView {
        var fillsBounds = false
        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemRed.setFill()
            if fillsBounds { bounds.fill() }
            else { CGRect(x: -4, y: 7, width: 40, height: 12).fill() }
        }
    }

    private func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap { descendants($0) } }
    private func host(_ view: AnyView, size: CGSize) -> NSWindow {
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: .dark),
                                       registry: LumenRegistry(packs: [.core, .code, .chart]))
        let root = view.lumenPaletteRoot(store: store).lumenDensityRoot(store: store)
            .lumenMetrics(.standard).lumenTextScale(1).lumenChromeStyle(.drawn)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.setContentSize(size)
        LumenHeadlessHost.prepare(window)
        LumenHeadlessHost.order(window)
        settle(window)
        return window
    }
    private func settle(_ window: NSWindow) {
        for _ in 0..<15 {
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
