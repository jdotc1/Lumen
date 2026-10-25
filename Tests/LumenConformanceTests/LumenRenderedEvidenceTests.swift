import LumenTestSupport
import AppKit
import LumenConformance
@_spi(LayoutAudit) @testable import LumenUI
import SwiftUI
import XCTest

#if DEBUG
/// Counterexamples in which incomplete ownership or line matching would invent a defect.
@MainActor
final class LumenRenderedEvidenceTests: XCTestCase {
    func testOwnedSeparatorCannotHideInsideNativeExclusions() throws {
        let frame = CGRect(x: 0, y: 0, width: 240, height: 180)
        let button = CGRect(x: 12, y: 155, width: 12, height: 12)
        for (y, fails) in [(160.0, true), (154.5, true), (146.0, false)] {
            let ink = CGRect(x: 14, y: y, width: 8, height: 0.5)
            let capture = LumenRenderedAudit.Capture(image: try solidImage(.white), frame: frame,
                usable: frame, chrome: CGRect(x: 0, y: 156, width: 240, height: 24),
                exclusions: [button], elements: [], clips: [], drawingBounds: [], margin: nil,
                scaffoldMargins: [], reports: [], ownedChromeInk: [ink],
                protectedButtons: [button.insetBy(dx: -1, dy: -1)])
            let result = try LumenRenderedAudit.analyze(capture)
            XCTAssertEqual(result.findings.contains { $0.rule == "rendered-chrome" }, fails)
        }
    }

    func testSurfaceGradientPreservesMarginInkAndClippedContours() throws {
        let frame = CGRect(x: 0, y: 0, width: 240, height: 180)
        for mutation in ["clean", "margin", "edge", "line", "wide-line", "covered", "covered-clean"] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 180, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            for y in 0..<180 {
                let shade = 0.1 + CGFloat(min(y, 100)) / 900
                context.setFillColor(CGColor(gray: shade, alpha: 1))
                context.fill(CGRect(x: 0, y: y, width: 240, height: 1))
            }
            var declarations = [LumenScaffoldMargin(frame: frame, margin: 16, depth: 0)]
            if mutation.hasPrefix("covered") {
                let nested = CGRect(x: 16, y: 0, width: 208, height: 180)
                context.setFillColor(CGColor(gray: 0.5, alpha: 1))
                context.fill(nested)
                declarations.append(.init(frame: nested, margin: 0, depth: 1))
            }
            context.setFillColor(NSColor.white.cgColor)
            if mutation == "margin" { context.fill(CGRect(x: 4, y: 60, width: 8, height: 14)) }
            if mutation == "edge" { context.fill(CGRect(x: -4, y: 60, width: 20, height: 14)) }
            if mutation == "line" { context.fill(CGRect(x: 0, y: 60, width: 240, height: 3)) }
            if mutation == "wide-line" { context.fill(CGRect(x: 0, y: 60, width: 240, height: 14)) }
            if mutation == "covered" {
                context.fill(CGRect(x: 0, y: 60, width: 16, height: 14))
                context.fill(CGRect(x: 224, y: 60, width: 16, height: 14))
            }
            let capture = LumenRenderedAudit.Capture(image: try XCTUnwrap(context.makeImage()), frame: frame,
                usable: frame, chrome: .zero, exclusions: [], elements: [], clips: [], drawingBounds: [],
                margin: nil, scaffoldMargins: declarations, reports: [])
            let result = try LumenRenderedAudit.analyze(capture)
            XCTAssertEqual(result.findings.contains { $0.rule == "rendered-margin" }, !mutation.hasSuffix("clean"), mutation)
            XCTAssertEqual(result.findings.contains { $0.rule == "rendered-edge" },
                           ["edge", "line", "wide-line", "covered"].contains(mutation), "\(mutation): \(result.findings)")
        }
    }

    func testSurfaceTrendWeightsOwnedAreaWhenNestedCoverageChanges() throws {
        let frame = CGRect(x: 0, y: 0, width: 240, height: 180)
        let nested = CGRect(x: 8, y: 0, width: 224, height: 160)
        let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 180, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(frame)
        context.setFillColor(NSColor.gray.cgColor)
        context.fill(nested)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 160))
        context.fill(CGRect(x: 232, y: 0, width: 8, height: 160))
        let capture = LumenRenderedAudit.Capture(image: try XCTUnwrap(context.makeImage()), frame: frame,
            usable: frame, chrome: .zero, exclusions: [], elements: [], clips: [], drawingBounds: [],
            margin: nil, scaffoldMargins: [.init(frame: frame, margin: 8, depth: 0),
                                           .init(frame: nested, margin: 0, depth: 1)], reports: [])
        let result = try LumenRenderedAudit.analyze(capture)
        let middleOfInk = CGRect(x: 0, y: 40, width: 8, height: 60)
        XCTAssertTrue(zip(result.findings, result.findingRects).contains {
            $0.0.rule == "rendered-margin" && $0.1.intersects(middleOfInk)
        }, "The black strip itself must be detected, not just its white header: \(result.findings)")
        XCTAssertTrue(result.findings.contains { $0.rule == "rendered-edge" }, "\(result.findings)")
    }

    func testContentEdgeBackgroundDoesNotBorrowNativeTitlebarColors() throws {
        let frame = CGRect(x: 0, y: 0, width: 240, height: 180)
        let content = CGRect(x: 0, y: 0, width: 240, height: 148)
        let nested = CGRect(x: 8, y: 8, width: 224, height: 120)
        for cutInk in [false, true] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 180, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 30.0 / 255, alpha: 1))
            context.fill(frame)
            for y in 0..<148 {
                let factor = max(0, CGFloat(y - 45)) / 103
                context.setFillColor(CGColor(red: (22 + 15 * factor) / 255,
                    green: (24 + 13 * factor) / 255, blue: (29 + 23 * factor) / 255, alpha: 1))
                context.fill(CGRect(x: 0, y: y, width: 240, height: 1))
            }
            context.setFillColor(CGColor(gray: 0.3, alpha: 1))
            context.fill(nested)
            if cutInk {
                context.setFillColor(NSColor.white.cgColor)
                context.fill(CGRect(x: -4, y: 105, width: 12, height: 14))
            }
            let capture = LumenRenderedAudit.Capture(image: try XCTUnwrap(context.makeImage()), frame: frame,
                usable: content, chrome: CGRect(x: 0, y: 148, width: 240, height: 32),
                exclusions: [], elements: [], clips: [], drawingBounds: [], margin: 8,
                scaffoldMargins: [.init(frame: nested, margin: 0, depth: 0)], reports: [])
            let result = try LumenRenderedAudit.analyze(capture)
            XCTAssertEqual(result.findings.contains { $0.rule == "rendered-edge" }, cutInk, "\(result.findings)")
            XCTAssertEqual(result.findings.contains { $0.rule == "rendered-margin" }, cutInk, "\(result.findings)")
        }
    }

    func testDisconnectedRulesDoNotBecomeAClippedContour() throws {
        let frame = CGRect(x: 0, y: 0, width: 240, height: 180)
        for cutInk in [false, true] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 180, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(NSColor.white.cgColor)
            context.fill(frame)
            context.setFillColor(NSColor.black.cgColor)
            for y in [20, 60, 140] { context.fill(CGRect(x: 0, y: y, width: 240, height: 1)) }
            context.fillEllipse(in: CGRect(x: 0, y: 80, width: 20, height: 20))
            if cutInk { context.fill(CGRect(x: -4, y: 105, width: 20, height: 14)) }
            let capture = LumenRenderedAudit.Capture(image: try XCTUnwrap(context.makeImage()), frame: frame,
                usable: frame, chrome: .zero, exclusions: [], elements: [], clips: [], drawingBounds: [],
                margin: nil, scaffoldMargins: [], reports: [])
            let result = try LumenRenderedAudit.analyze(capture)
            XCTAssertEqual(result.findings.contains { $0.rule == "rendered-edge" }, cutInk, "\(result.findings)")
        }
    }

    func testOnePixelHairlineThroughButtonBandFailsAndBelowPasses() throws {
        let frame = CGRect(x: 0, y: 0, width: 240, height: 180)
        let chrome = CGRect(x: 0, y: 148, width: 240, height: 32)
        let buttons = [12.0, 32.0, 52.0].map { CGRect(x: $0, y: 155, width: 12, height: 12) }
        for (y, fails) in [(160.0, true), (146.0, false)] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 480, height: 360, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: 2, y: 2)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(frame)
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 0, y: y, width: 240, height: 0.5))
            let capture = LumenRenderedAudit.Capture(image: try XCTUnwrap(context.makeImage()), frame: frame,
                usable: CGRect(x: 0, y: 0, width: 240, height: 148), chrome: chrome,
                exclusions: buttons, elements: [], clips: [], drawingBounds: [], margin: nil, scaffoldMargins: [], reports: [])
            let result = try LumenRenderedAudit.analyze(capture)
            XCTAssertEqual(result.findings.contains { $0.rule == "rendered-chrome" }, fails, "\(result.findings)")
        }
    }

    func testNarrowOwnedSurfaceBetweenHistogramSamplesIsBackground() throws {
        let window = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let left = CGRect(x: 0, y: 0, width: 8, height: 1024)
        let right = CGRect(x: 12, y: 0, width: 1012, height: 1024)
        let context = try XCTUnwrap(CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(window)
        context.setFillColor(NSColor.gray.cgColor)
        context.fill(left)
        context.fill(right)
        let capture = LumenRenderedAudit.Capture(image: try XCTUnwrap(context.makeImage()), frame: window,
            usable: window, chrome: .zero, exclusions: [], elements: [], clips: [], drawingBounds: [],
            margin: nil, scaffoldMargins: [left, right].map { .init(frame: $0, margin: 0, depth: 0) }, reports: [])
        let result = try LumenRenderedAudit.analyze(capture)
        XCTAssertFalse(result.findings.contains { $0.rule == "rendered-edge" }, "\(result.findings)")
    }

    func testExcludedNestedSurfaceDoesNotBecomeTheOwnedBackground() throws {
        let window = CGRect(x: 0, y: 0, width: 240, height: 180)
        let nested = CGRect(x: 0, y: 30, width: 240, height: 150)
        let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 180, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(window)
        context.setFillColor(NSColor.gray.cgColor)
        context.fill(nested)
        let capture = LumenRenderedAudit.Capture(image: try XCTUnwrap(context.makeImage()), frame: window,
            usable: window, chrome: .zero, exclusions: [], elements: [], clips: [], drawingBounds: [],
            margin: 16, scaffoldMargins: [
                .init(frame: window, margin: 16, depth: 0),
                .init(frame: nested, margin: 8, depth: 1),
            ], reports: [])
        let result = try LumenRenderedAudit.analyze(capture)
        XCTAssertFalse(result.findings.contains { $0.rule == "rendered-margin" }, "\(result.findings)")
    }

    func testRenderedMarginsUseTheInnermostScaffoldAndWindowFallback() throws {
        let window = CGRect(x: 0, y: 0, width: 240, height: 180)
        let panel = LumenScaffoldMargin(frame: CGRect(x: 0, y: 40, width: 160, height: 100), margin: 12, depth: 1)
        let outer = LumenScaffoldMargin(frame: window, margin: 16, depth: 0)
        let sidebar = LumenScaffoldMargin(frame: panel.frame, margin: 8, depth: 2)
        // Header ink at the panel's 12 pt inset passes; 8 pt fails. Outside the
        // shorter panel the window still requires 16 pt, even at the same x.
        for (x, y, declarations, fails) in [
            (12.0, 80.0, [outer, panel], false),
            (8.0, 80.0, [outer, panel], true),
            (12.0, 20.0, [panel], true),
            (8.0, 80.0, [outer, panel, sidebar], false),
            (4.0, 80.0, [outer, panel, sidebar], true),
        ] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 180, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(NSColor.white.cgColor)
            context.fill(window)
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: x, y: y, width: 8, height: 10))
            let capture = LumenRenderedAudit.Capture(image: try XCTUnwrap(context.makeImage()), frame: window,
                usable: window, chrome: .zero, exclusions: [], elements: [], clips: [], drawingBounds: [],
                margin: 16, scaffoldMargins: declarations, reports: [])
            let result = try LumenRenderedAudit.analyze(capture)
            XCTAssertEqual(result.findings.contains { $0.rule == "rendered-margin" }, fails,
                           "x=\(x), y=\(y): \(result.findings)")
        }
    }

    func testFullBleedSidebarSurfacePassesButCutGlyphFails() throws {
        let window = CGRect(x: 0, y: 0, width: 240, height: 180)
        let sidebar = CGRect(x: 0, y: 0, width: 60, height: 180)
        for cutGlyph in [false, true] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 180, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(NSColor.white.cgColor)
            context.fill(window)
            context.setFillColor(NSColor.gray.cgColor)
            context.fill(sidebar)
            if cutGlyph {
                // A block E extends beyond the left edge; its stem and bars are cut.
                context.setFillColor(NSColor.black.cgColor)
                context.fill(CGRect(x: -4, y: 70, width: 6, height: 20))
                for y in [70, 78, 87] { context.fill(CGRect(x: -4, y: y, width: 16, height: 3)) }
            }
            let capture = LumenRenderedAudit.Capture(image: try XCTUnwrap(context.makeImage()), frame: window,
                usable: window, chrome: .zero, exclusions: [], elements: [], clips: [], drawingBounds: [],
                margin: nil, scaffoldMargins: [.init(frame: sidebar, margin: 8, depth: 0)], reports: [])
            let result = try LumenRenderedAudit.analyze(capture)
            XCTAssertEqual(result.findings.contains { $0.rule == "rendered-edge" }, cutGlyph, "\(result.findings)")
        }
    }

    func testPartialMenuBarPanelDeclaresItsHeaderMargin() throws {
        let window = makeWindow()
        defer { window.close() }
        let host = NSHostingView(rootView:
            LumenMenuBarPanel("Panel", width: 360, maximumHeight: 200, showsFooter: false) {
                Text("Panel content").frame(height: 60)
            }
            .frame(width: 500, height: 300)
            .lumenPaletteRoot())
        host.sizingOptions = []
        window.contentView = host
        settle(window)
        let report = LumenWindowAuditReports.record(for: window)
        XCTAssertEqual(report.pageMargin, 16)
        let panel = try XCTUnwrap(report.scaffoldMargins.first)
        XCTAssertEqual(panel.margin, 12)
        XCTAssertEqual(panel.frame.width, 360, accuracy: 0.5)
        XCTAssertLessThan(panel.frame.height, 300)
        let result = try LumenRenderedAudit.analyze(LumenRenderedAudit.capture(in: window))
        XCTAssertTrue(result.observes("Panel"))
        XCTAssertFalse(result.findings.contains { $0.rule == "rendered-margin" }, "\(result.findings)")
    }

    func testPresenceRequiresTheWholeLabelAndRecordsOCRExtras() throws {
        let image = try solidImage(.white)
        for (text, expected) in [("Open Fixturel", true), ("Open Fixt…", false), ("Fixture", false)] {
            let line = LumenRenderedAudit.Line(text: text, frame: CGRect(x: 20, y: 20, width: 90, height: 12),
                                              confidence: 1, inkPixels: 40)
            let result = LumenRenderedAudit.Result(image: image, frame: .zero, findings: [], findingRects: [],
                                                  lines: [line], visionSeconds: 0)
            XCTAssertEqual(result.observes("Open Fixture"), expected, text)
            if expected {
                XCTAssertEqual(result.presence(of: "Open Fixture")?.leading, "")
                XCTAssertEqual(result.presence(of: "Open Fixture")?.trailing, "l")
            }
        }
    }

    func testPresenceJoinsOnlyAdjacentObservationsOnTheSameBaseline() throws {
        let image = try solidImage(.white)
        let first = LumenRenderedAudit.Line(text: " OPEN ", frame: CGRect(x: 20, y: 20, width: 30, height: 12),
                                           confidence: 1, inkPixels: 40)
        for (x, y, expected) in [(54.0, 20.0, true), (54.0, 40.0, false), (100.0, 20.0, false)] {
            let second = LumenRenderedAudit.Line(text: "Fixturel", frame: CGRect(x: x, y: y, width: 50, height: 12),
                                                confidence: 1, inkPixels: 40)
            let result = LumenRenderedAudit.Result(image: image, frame: .zero, findings: [], findingRects: [],
                                                  lines: [second, first], visionSeconds: 0)
            XCTAssertEqual(result.observes(" open   fixture "), expected)
        }
    }

    func testCompleteMultilineNativeLabelIsNotTruncated() throws {
        let window = makeWindow()
        defer { window.close() }
        let label = NSTextField(wrappingLabelWithString: "First visible line\nSecond visible line")
        label.font = try XCTUnwrap(NSFont(name: "Arial", size: 10))
        label.textColor = .black
        label.frame = CGRect(x: 40, y: 120, width: 360, height: 70)
        label.maximumNumberOfLines = 0
        try XCTUnwrap(window.contentView).addSubview(label)
        settle(window)

        let result = try LumenRenderedAudit.analyze(LumenRenderedAudit.capture(in: window))
        XCTAssertTrue(result.observes("First visible line"), "The first complete line must be rendered: \(result.lines.map(\.text))")
        XCTAssertTrue(result.observes("Second visible line"), "The second complete line must be rendered: \(result.lines.map(\.text))")
        XCTAssertFalse(result.findings.contains { $0.rule == "rendered-truncation" },
                       "Separate recognized lines belonging to one complete label are not truncation: \(result.findings)")
    }

    func testImageInsideItsOwnButtonIsNotAnIndependentOverlap() throws {
        let window = makeWindow()
        defer { window.close() }
        let button = NSButton(title: "Image action", target: nil, action: nil)
        button.font = try XCTUnwrap(NSFont(name: "Arial", size: 10))
        button.bezelStyle = .flexiblePush
        button.frame = CGRect(x: 50, y: 80, width: 200, height: 100)
        let imageView = NSImageView(frame: CGRect(x: 12, y: 70, width: 22, height: 22))
        imageView.image = NSImage(cgImage: try solidImage(.magenta), size: imageView.bounds.size)
        button.addSubview(imageView)
        try XCTUnwrap(window.contentView).addSubview(button)
        settle(window)

        let capture = try LumenRenderedAudit.capture(in: window)
        let imageFrame = window.convertToScreen(imageView.convert(imageView.bounds, to: nil))
        let bitmap = NSBitmapImageRep(cgImage: capture.image)
        let x = Int((imageFrame.midX - capture.frame.minX) * CGFloat(capture.image.width) / capture.frame.width)
        let y = Int((capture.frame.maxY - imageFrame.midY) * CGFloat(capture.image.height) / capture.frame.height)
        let sample = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(sample.redComponent, 0.8, "The nested image must contribute visible pixels")
        XCTAssertGreaterThan(min(sample.redComponent, sample.blueComponent) - sample.greenComponent, 0.4,
                             "The nested image must retain magenta contrast through native compositing")
        XCTAssertGreaterThan(sample.blueComponent, 0.8, "The nested image must contribute visible pixels")
        let result = try LumenRenderedAudit.analyze(capture)
        XCTAssertTrue(result.observes("Image action"), "The image's owning control must also be visible: \(result.lines.map(\.text))")
        XCTAssertFalse(result.findings.contains { $0.rule == "rendered-overlap" },
                       "An image belonging to a button is part of that control: \(result.findings)")
    }

    func testUnchangedTextDoesNotGrowIntoASeparateLongerLabel() throws {
        let image = try solidImage(.white)
        let save = LumenRenderedAudit.Line(text: "Save", frame: CGRect(x: 40, y: 90, width: 30, height: 12),
                                          confidence: 1, inkPixels: 40)
        let longer = LumenRenderedAudit.Line(text: "Save Document", frame: CGRect(x: 150, y: 90, width: 90, height: 12),
                                            confidence: 1, inkPixels: 120)
        let small = LumenRenderedAudit.Result(image: image, frame: CGRect(x: 0, y: 0, width: 320, height: 200),
                                             findings: [], findingRects: [], lines: [save], visionSeconds: 0)
        let large = LumenRenderedAudit.Result(image: image, frame: CGRect(x: 0, y: 0, width: 960, height: 600),
                                             findings: [], findingRects: [], lines: [save, longer], visionSeconds: 0)
        XCTAssertEqual(LumenRenderedAudit.differential(small, large), [],
                       "The unchanged Save label must not be matched to the separate Save Document label")
    }

    func testDifferentialDistinguishesJoinedButtonsFromGrowingText() throws {
        let image = try solidImage(.white)
        let back = LumenRenderedAudit.Line(text: "Go Back", frame: CGRect(x: 20, y: 20, width: 64, height: 16),
                                           confidence: 1, inkPixels: 40)
        for (x, y, text, survives, fails) in [(100.0, 20.0, "Go Back Done", false, false),
                                             (100.0, 50.0, "Go Back Done", false, true),
                                             (200.0, 20.0, "Go Back Done", false, true),
                                             (100.0, 20.0, "Go Back Done now", false, true),
                                             (100.0, 20.0, "Go Back Done", true, true)] {
            let done = LumenRenderedAudit.Line(text: "Done", frame: CGRect(x: x, y: y, width: 45, height: 16),
                                               confidence: 1, inkPixels: 40)
            let joined = LumenRenderedAudit.Line(text: text, frame: CGRect(x: 20, y: 20, width: 125, height: 16),
                                                 confidence: 1, inkPixels: 80)
            let small = LumenRenderedAudit.Result(image: image, frame: .zero, findings: [], findingRects: [],
                                                  lines: [back, done], visionSeconds: 0)
            let large = LumenRenderedAudit.Result(image: image, frame: .zero, findings: [], findingRects: [],
                                                  lines: survives ? [joined, done] : [joined], visionSeconds: 0)
            XCTAssertEqual(!LumenRenderedAudit.differential(small, large).isEmpty, fails)
        }
        let middle = LumenRenderedAudit.Line(text: "X", frame: CGRect(x: 88, y: 20, width: 4, height: 16),
                                             confidence: 1, inkPixels: 8)
        let done = LumenRenderedAudit.Line(text: "Done", frame: CGRect(x: 100, y: 20, width: 45, height: 16),
                                           confidence: 1, inkPixels: 40)
        let joined = LumenRenderedAudit.Line(text: "Go Back Done", frame: CGRect(x: 20, y: 20, width: 125, height: 16),
                                             confidence: 1, inkPixels: 80)
        let small = LumenRenderedAudit.Result(image: image, frame: .zero, findings: [], findingRects: [],
                                              lines: [back, middle, done], visionSeconds: 0)
        let large = LumenRenderedAudit.Result(image: image, frame: .zero, findings: [], findingRects: [],
                                              lines: [joined, middle], visionSeconds: 0)
        XCTAssertFalse(LumenRenderedAudit.differential(small, large).isEmpty,
                       "A surviving intervening label must block reconstruction")
    }

    func testHostedWindowLayoutIncludesDifferentialTruncationOfPlainText() {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        let findings = LumenConformance.windowLayout(
            sizes: [CGSize(width: 180, height: 160)],
            chrome: [.init(titleVisibility: .hidden, toolbarStyle: .automatic,
                           toolbar: false, fullSizeContentView: false)],
            textScales: [1]
        ) {
            Text("The complete document title remains readable when the window has enough space")
                .font(.custom("Arial", size: 10))
                .foregroundStyle(.black)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.white)
                .environment(\.colorScheme, .light)
        }
        XCTAssertTrue(findings.contains {
            $0.message.hasPrefix("rendered-truncation:") && $0.message.contains("recognized text grows")
        }, "The hosted offscreen capture must expose text growth without Lumen text reports: \(findings)")
        XCTAssertFalse(findings.contains { $0.message.hasPrefix("rendered-capture:") },
                       "The public check must capture its own offscreen host: \(findings)")
    }

    func testLiveWindowIncludesIndependentImageControlCollision() throws {
        let window = makeWindow()
        defer { window.close() }
        let button = NSButton(title: "Independent image collision", target: nil, action: nil)
        button.font = try XCTUnwrap(NSFont(name: "Arial", size: 10))
        button.bezelStyle = .flexiblePush
        button.frame = CGRect(x: 50, y: 80, width: 230, height: 100)
        let image = NSImageView(frame: CGRect(x: 100, y: 140, width: 40, height: 30))
        image.image = NSImage(cgImage: try solidImage(.magenta), size: image.bounds.size)
        let content = try XCTUnwrap(window.contentView)
        content.addSubview(button)
        content.addSubview(image)
        settle(window)

        let findings = LumenConformance.liveWindow(window)
        XCTAssertTrue(findings.contains { $0.message.hasPrefix("rendered-overlap:") },
                      "The public live-window check must include a rendered collision between independent siblings: \(findings)")
        XCTAssertFalse(findings.contains { $0.message.hasPrefix("rendered-capture:") },
                       "The public live-window check must capture the fixture: \(findings)")
    }

    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        let window = LumenHeadlessHost.window(contentRect: CGRect(x: 80, y: 80, width: 500, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.backgroundColor = .white
        window.appearance = NSAppearance(named: .aqua)
        LumenHeadlessHost.order(window)
        return window
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<12 {
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func solidImage(_ color: NSColor) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 24, height: 24, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        return try XCTUnwrap(context.makeImage())
    }
}
#endif
