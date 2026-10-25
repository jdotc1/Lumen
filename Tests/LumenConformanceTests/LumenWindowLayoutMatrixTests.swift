import AppKit
import LumenTestSupport
@_spi(LayoutAudit) @testable import LumenUI
import SwiftUI
import XCTest
#if DEBUG
import Vision
#endif
@testable import LumenConformance

/// Deterministic pairwise covering array, not a selection of hand-written regressions.
/// Each pair of values in any two dimensions occurs in at least one sampled cell.
/// The complete product is intentionally not rendered. Add values to the arrays below;
/// the generator, coverage assertion, reports and contact sheet follow automatically.
/// `swiftUIHost` uses NSHostingController and toolbar bridging, not a WindowGroup scene.
@MainActor
final class LumenWindowLayoutMatrixTests: XCTestCase {
    @MainActor private struct Kind {
        let name: String
        let minimum: CGSize
        let wrap: @MainActor (AnyView) -> AnyView

        init(_ name: String, _ minimum: CGSize, wrap: @escaping @MainActor (AnyView) -> AnyView) {
            self.name = name
            self.minimum = minimum
            self.wrap = wrap
        }
    }
    private static let ordinaryMinimum = CGSize(width: 640, height: 400)
    // A new kind is one entry, including its scaffold constructor.
    private static let kinds: [Kind] = [
        .init("swiftUIHost", ordinaryMinimum) { $0 },
        .init("hosted-sheet-root", ordinaryMinimum) { $0 },
        .init("NSWindow", ordinaryMinimum) { $0 },
        .init("NSPanel", ordinaryMinimum) { $0 },
        .init("workspace", ordinaryMinimum) { body in
            AnyView(LumenWorkspaceWindow(panels: .constant(.init(leading: false, bottom: false, trailing: false))) {
                body.padding(16)
            } topLeading: { Text("Workspace") })
        },
        .init("utility", ordinaryMinimum) { body in
            AnyView(LumenUtilityWindow(minimumSize: ordinaryMinimum) { body.padding(16) } topLeading: { Text("Utility") })
        },
        .init("menuBarPanel", .init(width: 360, height: 480)) { body in
            AnyView(LumenMenuBarPanel("Panel", width: 360, maximumHeight: 480, showsFooter: false) { body.frame(minHeight: 200) })
        },
        .init("wizard", .init(width: 640, height: 460)) { body in
            AnyView(LumenWizardWindow(pages: [.init(id: "one", title: "Page")], current: .constant(0),
                              onCancel: {}, onFinish: {}) { _ in body.padding(16) })
        },
        .init("library", ordinaryMinimum) { body in
            AnyView(LumenLibraryWindow(minimumSize: ordinaryMinimum) { body.padding(16) } topLeading: { Text("Library") })
        },
        .init("document", ordinaryMinimum) { body in
            AnyView(LumenDocumentWindow(title: .constant("Document"), isModified: false, minimumSize: ordinaryMinimum) { body.padding(16) })
        },
    ]
    private struct Chrome {
        let name: String
        let title: NSWindow.TitleVisibility
        let style: NSWindow.ToolbarStyle
    }
    private static let chrome: [Chrome] = [
        .init(name: "hiddenTitle", title: .hidden, style: .automatic),
        .init(name: "defaultTitle", title: .visible, style: .automatic),
        .init(name: "unifiedCompact", title: .hidden, style: .unifiedCompact),
        .init(name: "unified", title: .visible, style: .unified),
    ]
    private static let toolbars = [false, true]
    private static let fullSize = [false, true]
    @MainActor private struct Composition {
        let name: String
        let content: @MainActor () -> AnyView
        init(_ name: String, content: @escaping @MainActor () -> AnyView) {
            self.name = name
            self.content = content
        }
    }
    private struct PageMargin: ViewModifier {
        @Environment(\.lumenMetrics) private var metrics

        func body(content: Content) -> some View {
            content.padding(metrics.spacing.s6)
        }
    }

    private static let compositions: [Composition] = [
        .init("stack") {
            AnyView(VStack { Button("Open Fixture") {}; Spacer(minLength: 0) }.frame(maxWidth: .infinity, maxHeight: .infinity))
        },
        .init("navigation") {
            AnyView(NavigationSplitView {
                Text("Source").modifier(PageMargin()).navigationSplitViewColumnWidth(min: 100, ideal: 120, max: 160)
            } detail: {
                VStack { Button("Open Fixture") {}; Spacer(minLength: 0) }.modifier(PageMargin())
            }.toolbar { ToolbarItem(placement: .primaryAction) { Button("Refresh") {} } })
        },
        .init("scroll") {
            AnyView(ScrollView { VStack(alignment: .leading, spacing: 12) {
                Button("Open Fixture") {}
                ForEach(0..<4) { Text("Row \($0)") }
            }.frame(maxWidth: .infinity, alignment: .leading).modifier(PageMargin()) })
        },
        .init("list") { AnyView(List { Button("Open Fixture") {}; Text("List content") }) },
        .init("form") { AnyView(Form { Button("Open Fixture") {}; Toggle("Enabled", isOn: .constant(true)) }.padding(16)) },
        .init("status") {
            AnyView(VStack(spacing: 0) {
                Button("Open Fixture") {}
                Spacer(minLength: 12)
                LumenStatusBar { Text("Ready"); Spacer(); Button("Details") {} }.modifier(PageMargin())
            }.frame(maxWidth: .infinity, maxHeight: .infinity))
        },
    ]
    private static let scales: [Double] = [1, 1.3]
    private static let sizes = ["minimum", "large"]
    private struct ContentMinimum {
        let name: String
        let factor: CGFloat
    }
    // Relative to the requested window content size, before root minimum propagation. The
    // equal/above cells deliberately require scrolling or a larger enforced window minimum.
    private static let contentMinimums: [ContentMinimum] = [
        .init(name: "below", factor: 0.5),
        .init(name: "equal", factor: 1),
        .init(name: "above", factor: 1.15),
    ]
    private static var dimensions: [Int] {
        [kinds.count, chrome.count, toolbars.count, fullSize.count, compositions.count, scales.count, sizes.count, contentMinimums.count]
    }
    private struct Pair: Hashable {
        let a: Int, x: Int, b: Int, y: Int
    }
    private struct Cell {
        let values: [Int]
        var pairs: Set<Pair> {
            var result = Set<Pair>()
            for a in values.indices {
                for b in values.indices where b > a {
                    result.insert(Pair(a: a, x: values[a], b: b, y: values[b]))
                }
            }
            return result
        }
        @MainActor var label: String {
            let kinds = LumenWindowLayoutMatrixTests.kinds
            let chrome = LumenWindowLayoutMatrixTests.chrome
            let toolbars = LumenWindowLayoutMatrixTests.toolbars
            let fullSize = LumenWindowLayoutMatrixTests.fullSize
            let compositions = LumenWindowLayoutMatrixTests.compositions
            let scales = LumenWindowLayoutMatrixTests.scales
            let sizes = LumenWindowLayoutMatrixTests.sizes
            let minimums = LumenWindowLayoutMatrixTests.contentMinimums
            let v = values
            return "\(kinds[v[0]].name) / \(chrome[v[1]].name) / toolbar \(toolbars[v[2]]) / full \(fullSize[v[3]]) / \(compositions[v[4]].name) / \(scales[v[5]]) / \(sizes[v[6]]) / min \(minimums[v[7]].name)"
        }
    }
    private static func sample() -> (cells: [Cell], allPairs: Set<Pair>, total: Int) {
        let product = dimensions.reduce([[]] as [[Int]]) { rows, count in
            rows.flatMap { row in (0..<count).map { row + [$0] } }
        }.map { Cell(values: $0) }
        let pairs = product.map(\.pairs)
        var remaining = pairs.reduce(into: Set<Pair>()) { $0.formUnion($1) }
        let allPairs = remaining
        var selected: [Cell] = []
        while !remaining.isEmpty {
            var best = 0, score = -1
            for index in product.indices {
                let next = pairs[index].intersection(remaining).count
                if next > score { best = index; score = next }
            }
            selected.append(product[best])
            remaining.subtract(pairs[best])
        }
        return (selected, allPairs, product.count)
    }

    /// Revisit only the three native boundary findings from the initial pairwise run. This
    /// bounded diagnostic is separate from the matrix's required pure-SwiftUI presence proof.
    func testNativeBoundariesForMatrixCells5And13And27() throws {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        let sample = Self.sample()
        for index in [5, 13, 27] {
            try autoreleasepool {
                let cell = sample.cells[index]
                let hosted = makeWindow(cell, rooted: true)
                defer { hosted.close() }
                settle(hosted.window)
                hosted.window.toolbar?.isVisible = Self.toolbars[cell.values[2]]
                settle(hosted.window)
                let findings = LumenConformance.liveWindow(hosted.window)
                print("BOUNDARY cell \(index): \(cell.label); window=\(hosted.window.frame); host=\(String(describing: hosted.window.contentView?.frame)); usable=\(hosted.window.contentLayoutRect); minimum=\(hosted.window.contentMinSize); findings=\(findings)")
                var seen = Set<ObjectIdentifier>()
                var tables: [NSTableView] = []
                @MainActor func describe(_ object: AnyObject, ancestors: [String]) {
                    guard seen.insert(ObjectIdentifier(object)).inserted else { return }
                    let native = object as? NSView
                    if let table = native as? NSTableView { tables.append(table) }
                    let semantic = object as? any NSAccessibilityProtocol
                    let description: String
                    if let native {
                        let frame = hosted.window.convertToScreen(native.convert(native.bounds, to: nil))
                        description = "\(type(of: object)) frame=\(frame) clips=\(native.clipsToBounds)"
                    } else { description = "\(type(of: object))" }
                    if semantic?.accessibilityRole() == .button {
                        print("BOUNDARY button \(description) semantic=\(String(describing: semantic?.accessibilityFrame())) ancestors=\(ancestors)")
                    }
                    let ancestry = ancestors + [description]
                    for child in native?.subviews ?? [] { describe(child, ancestors: ancestry) }
                    for child in semantic?.accessibilityChildren() ?? [] {
                        describe(child as AnyObject, ancestors: ancestry)
                    }
                }
                if let content = hosted.window.contentView { describe(content, ancestors: []) }
                if index == 13 {
                    let table = try XCTUnwrap(tables.first, "The wizard List must have its native table")
                    let scroll = try XCTUnwrap(table.enclosingScrollView)
                    XCTAssertGreaterThanOrEqual(table.numberOfRows, 2, "Both fixture rows must be present")
                    XCTAssertGreaterThan(scroll.contentView.bounds.height, 0,
                                         "The List viewport must not collapse to its zero intrinsic height")
                    XCTAssertTrue(table.visibleRect.intersects(table.rect(ofRow: 0)),
                                  "The first List row must intersect its visible viewport")
                    print("BOUNDARY List viewport=\(scroll.contentView.bounds) visible=\(table.visibleRect) row0=\(table.rect(ofRow: 0))")
                }
                // Unique indices preserve the original diagnostic captures for comparison.
                _ = try capture(hosted.window, index: 1000 + index)
                let boundaries = findings.filter {
                    $0.message.hasPrefix("bottom-bar:") || $0.message.hasPrefix("ancestor-clip:")
                }
                XCTAssertEqual(boundaries, [], "cell \(index): \(cell.label)\n\(boundaries)")
            }
        }
    }

    #if DEBUG
    /// Records the actual native transition without re-running an audit or an OCR request.
    /// Cell 25 owns its scaffold top bar, but its minimum must still fit below native chrome.
    func testNativeMinimumCaptureDiagnosticCell25() throws {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        let cell = Self.sample().cells[25]
        let hosted = makeWindow(cell, rooted: true, colorScheme: .light)
        defer { hosted.close() }
        let window = hosted.window
        var lines = ["CELL25 MINIMUM \(cell.label)"]
        func record(_ stage: String, tick: Int) {
            let report = LumenWindowAuditReports.record(for: window)
            let frameContent = window.contentRect(forFrameRect: window.frame)
            let line = "stage=\(stage) tick=\(tick) frame=\(window.frame) frameContent=\(frameContent) contentBounds=\(String(describing: window.contentView?.bounds)) contentLayoutRect=\(window.contentLayoutRect) styleMask=\(window.styleMask.rawValue) fullSize=\(window.styleMask.contains(.fullSizeContentView)) toolbar=\(String(describing: window.toolbar?.isVisible)) contentMinSize=\(window.contentMinSize) reportMinimum=\(String(describing: report.contentMinimum)) reportFrame=\(String(describing: report.contentFrame)) ownsTop=\(report.ownsTopBar) minimumEnforced=\(report.minimumEnforced) exceedsScreen=\(report.contentMinimumExceedsScreen) visibleScreen=\(String(describing: window.screen?.visibleFrame))"
            lines.append(line)
            print("CELL25 MINIMUM \(line)")
        }
        func advance(_ stage: String, ticks: Int) {
            for tick in 1...ticks {
                window.contentView?.superview?.layoutSubtreeIfNeeded()
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                record(stage, tick: tick)
            }
        }
        record("created", tick: 0)
        advance("initial", ticks: 30)
        window.toolbar?.isVisible = Self.toolbars[cell.values[2]]
        record("requested-toolbar", tick: 0)
        advance("after-toolbar", ticks: 15)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: repository.appending(path: ".build/test-artifacts"), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").appending("\n")
            .write(to: repository.appending(path: ".build/test-artifacts/cell25-minimum-transition.txt"),
                   atomically: true, encoding: .utf8)
    }

    /// Bounded route comparison for the navigation cell whose layer capture lost text contrast.
    /// This measures capture fidelity; it does not rerun the semantic or rendered detectors.
    func testNavigationCaptureDiagnostic() async throws {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        let cell = Self.sample().cells[1]
        let hosted = makeWindow(cell, rooted: true, colorScheme: .light)
        defer { hosted.close() }
        settle(hosted.window)
        hosted.window.toolbar?.isVisible = Self.toolbars[cell.values[2]]
        settle(hosted.window)
        let window = hosted.window
        let frameView = try XCTUnwrap(window.contentView?.superview)
        print("NAVIGATION CAPTURE \(cell.label); window=\(window.frame); usable=\(window.contentLayoutRect); appearance=\(String(describing: window.effectiveAppearance.name)); theme=\(LumenThemeStore.active.theme().id); forced=\(String(describing: LumenThemeStore.active.forcedAppearance(for: .window)))")
        func describe(_ view: NSView, depth: Int) {
            let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
            print("NAVIGATION VIEW depth=\(depth) type=\(type(of: view)) frame=\(frame) hidden=\(view.isHiddenOrHasHiddenAncestor) alpha=\(view.alphaValue) layer=\(String(describing: view.layer.map { String(describing: type(of: $0)) })) layerOpacity=\(view.layer?.opacity ?? -1)")
            for child in view.subviews { describe(child, depth: depth + 1) }
        }
        describe(frameView, depth: 0)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appending(path: ".build/test-artifacts/navigation-capture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func record(_ image: CGImage, route: String) throws {
            let bitmap = NSBitmapImageRep(cgImage: image)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appending(path: "\(route).png"))
            let request = try LumenAuditOCR.makeRequest()
            let start = Date()
            try VNImageRequestHandler(cgImage: image).perform([request])
            let recognized = (request.results ?? []).compactMap { line -> String? in
                guard let text = line.topCandidates(1).first else { return nil }
                return "\(text.string) confidence=\(text.confidence) box=\(line.boundingBox)"
            }
            print("NAVIGATION ROUTE \(route) pixels=\(image.width)x\(image.height) vision=\(Date().timeIntervalSince(start))s text=\(recognized)")
        }
        try record(LumenRenderedAudit.capture(in: window).image, route: "frame-bitmap")
        frameView.displayIfNeeded()
        let bitmap = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        try record(XCTUnwrap(bitmap.cgImage), route: "bitmap")
    }

    func testSeparatorOwnerCell29() throws {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        let hosted = makeWindow(Self.sample().cells[29], rooted: true, colorScheme: .light)
        defer { hosted.close() }
        settle(hosted.window)
        hosted.window.toolbar?.isVisible = false
        settle(hosted.window)
        let window = hosted.window
        let capture = try LumenRenderedAudit.capture(in: window)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: ".build/test-artifacts/window-layout")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(cgImage: capture.image)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: root.appending(path: "separator-owner.png"))
        var lines = ["frame=\(window.frame) contentLayoutRect=\(window.contentLayoutRect) toolbarVisible=\(window.toolbar?.isVisible == true)"]
        func layers(_ layer: CALayer, _ depth: String) {
            lines.append("\(depth)layer \(type(of: layer)) name=\(layer.name ?? "nil") frame=\(layer.frame) hidden=\(layer.isHidden) background=\(String(describing: layer.backgroundColor))")
            for child in layer.sublayers ?? [] { layers(child, depth + "  ") }
        }
        func views(_ view: NSView, _ depth: String) {
            lines.append("\(depth)view \(type(of: view)) frame=\(view.frame) windowRect=\(view.convert(view.bounds, to: nil)) hidden=\(view.isHiddenOrHasHiddenAncestor) safeArea=\(view.safeAreaInsets)")
            if let layer = view.layer { layers(layer, depth + "  ") }
            for child in view.subviews { views(child, depth + "  ") }
        }
        if let frame = window.contentView?.superview { views(frame, "") }
        try lines.joined(separator: "\n").write(to: root.appending(path: "separator-owner.txt"), atomically: true, encoding: .utf8)
    }

    /// Inspect geometry and ownership of a dark window without bitmap analysis.
    func testDarkWindowOwnershipMetadata() throws {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        let cell = Self.sample().cells[34]
        let hosted = makeWindow(cell, rooted: true, colorScheme: .dark)
        defer { hosted.close() }
        settle(hosted.window)
        hosted.window.toolbar?.isVisible = Self.toolbars[cell.values[2]]
        settle(hosted.window)
        let geometry = LumenWindowGeometry(window: hosted.window)
        let report = LumenWindowAuditReports.record(for: hosted.window)
        var lines = ["Window geometry and ownership metadata.",
                     "frame=\(hosted.window.frame) usable=\(geometry.contentBounds) chrome=\(geometry.chromeBand)",
                     "pageMargin=\(String(describing: report.pageMargin))"]
        for declaration in report.scaffoldMargins {
            lines.append("owner frame=\(declaration.frame) margin=\(declaration.margin) depth=\(declaration.depth)")
        }
        func walk(_ view: NSView, depth: Int) {
            guard !view.isHiddenOrHasHiddenAncestor else { return }
            let rect = hosted.window.convertToScreen(view.convert(view.bounds, to: nil))
            lines.append("\(String(repeating: " ", count: depth))\(String(reflecting: type(of: view))) frame=\(rect) clips=\(view.clipsToBounds)")
            for child in view.subviews { walk(child, depth: depth + 1) }
        }
        walk(try XCTUnwrap(hosted.window.contentView?.superview), depth: 0)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: root.appending(path: ".build/test-artifacts/window-layout"), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").appending("\n").write(
            to: root.appending(path: ".build/test-artifacts/window-layout/dark34-ownership.txt"), atomically: true, encoding: .utf8)
    }

    /// Each sampled layout is captured once. The same pixels prove control presence, drive the
    /// rendered rules and form the contact sheet; semantic strings cannot substitute for ink.
    func testRootedPairwiseWindowMatrix() throws {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        let sample = Self.sample()
        XCTAssertEqual(sample.cells.reduce(into: Set<Pair>()) { $0.formUnion($1.pairs) }, sample.allPairs)
        let appearances: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]
        var captures: [(String, NSImage)] = []
        var visionSeconds: [Double] = []
        var falsePositives: [String: Int] = [:]
        var missingControls = 0
        var ocrExtraCount = 0
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let reportURL = root.appending(path: ".build/test-artifacts/rendered-window-matrix.txt")
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var report = ["dimensions=\(Self.dimensions)", "cartesian=\(sample.total)",
                       "sampled=\(sample.cells.count) per appearance; appearances=light,dark; pairs=\(sample.allPairs.count)",
                       "sampling=greedy pairwise; lexicographic first candidate wins ties; text scales 1.0 and 1.3",
                       "overflow=content min 0.5/1/1.15 times requested content size before root propagation",
                       "presence=whole normalized Open Fixture contained in one line or adjacent same-baseline observations plus foreground ink; ocrExtra records surrounding characters",
                       "capture=frame-view bitmap cache after display; same bitmap reused for rules and image",
                       "differential=same root and window at twice the laid-out size, minimum 1600x1000",
                       "swiftUIHost=NSHostingController with toolbar bridging; not a SwiftUI scene"]
        for (appearanceIndex, appearance) in appearances.enumerated() {
            for (index, cell) in sample.cells.enumerated() {
                var cellFailed = false
                try autoreleasepool {
                    let label = "\(appearance.0) / cell \(index): \(cell.label)"
                    let hosted = makeWindow(cell, rooted: true, colorScheme: appearance.1)
                    defer { hosted.close() }
                    settle(hosted.window)
                    hosted.window.toolbar?.isVisible = Self.toolbars[cell.values[2]]
                    settle(hosted.window)
                    let capture = try LumenRenderedAudit.capture(in: hosted.window)
                    let rendered = try LumenRenderedAudit.analyze(capture)
                    visionSeconds.append(rendered.visionSeconds)
                    let presence = rendered.presence(of: "Open Fixture")
                    let observed = presence != nil
                    let ocrExtra = presence.map { [$0.leading, $0.trailing] } ?? []
                    if ocrExtra.contains(where: { !$0.isEmpty }) { ocrExtraCount += 1 }
                    if !observed { missingControls += 1 }
                    let observedLines = rendered.lines.map { "\($0.text) [ink=\($0.inkPixels)]" }
                    let semantic = LumenLayoutAudit.findings(in: hosted.window)
                    let findings = semantic + rendered.findings
                    for finding in rendered.findings { falsePositives[finding.rule, default: 0] += 1 }
                    // Retain a contact-sheet thumbnail, not every full-resolution bitmap.
                    // The original pixels are saved below before this autorelease pool ends.
                    let image = NSImage(cgImage: rendered.image, size: capture.frame.size)
                    let thumbnail = NSImage(size: CGSize(width: 320, height: 210))
                    thumbnail.lockFocus()
                    let thumbnailScale = min(320 / image.size.width, 210 / image.size.height)
                    let drawn = CGSize(width: image.size.width * thumbnailScale,
                                       height: image.size.height * thumbnailScale)
                    image.draw(in: CGRect(x: (320 - drawn.width) / 2, y: (210 - drawn.height) / 2,
                                          width: drawn.width, height: drawn.height))
                    thumbnail.unlockFocus()
                    captures.append((label, thumbnail))
                    let shotDirectory = root.appending(path: ".build/test-artifacts/images/rendered-matrix-cells")
                    try FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)
                    let bitmap = NSBitmapImageRep(cgImage: rendered.image)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: shotDirectory.appending(path: "cell-\(appearanceIndex)-\(index).png"))
                    report.append("\(label); observed=\(observed); pixels=\(rendered.image.width)x\(rendered.image.height); vision=\(rendered.visionSeconds)s; semantic=\(semantic.count); rendered=\(rendered.findings.count)")
                    report.append("  ocrExtra=\(ocrExtra); ocrExtraCount=\(ocrExtraCount)")
                    if !observed { report.append("  recognized=\(observedLines)") }
                    for finding in findings { report.append("  \(finding.rule): \(finding.view): \(finding.message)") }
                    try report.joined(separator: "\n").appending("\n")
                        .write(to: reportURL, atomically: true, encoding: .utf8)
                    if !observed || !findings.isEmpty {
                        cellFailed = true
                        FileHandle.standardOutput.write(Data("RENDERED MATRIX STOP \(label); observed=\(observed); semantic=\(semantic.count); rendered=\(rendered.findings.count)\n".utf8))
                        XCTAssertTrue(observed,
                            "The rendered fixture must expose its top control in \(label); observed: \(observedLines)")
                        XCTAssertEqual(findings, [], "\(label)\n\(findings)")
                        return
                    }
                    // Expand the existing root rather than constructing a different fixture. The
                    // content minimum remains the original one, so responsive text may grow.
                    let original = hosted.window.contentView?.bounds.size ?? capture.frame.size
                    hosted.window.setContentSize(CGSize(width: max(1600, original.width * 2),
                                                       height: max(1000, original.height * 2)))
                    settle(hosted.window)
                    let expanded = try LumenRenderedAudit.analyze(LumenRenderedAudit.capture(in: hosted.window))
                    visionSeconds.append(expanded.visionSeconds)
                    let differential = LumenRenderedAudit.differential(rendered, expanded)
                    for finding in differential { falsePositives[finding.rule, default: 0] += 1 }
                    report.append("  expanded=\(expanded.image.width)x\(expanded.image.height); vision=\(expanded.visionSeconds)s; differential=\(differential.count)")
                    for finding in differential { report.append("  \(finding.rule): \(finding.view): \(finding.message)") }
                    // Keep partial evidence if a later native capture or OCR request fails.
                    try report.joined(separator: "\n").appending("\n")
                        .write(to: reportURL, atomically: true, encoding: .utf8)
                    FileHandle.standardOutput.write(Data("RENDERED MATRIX \(label); observed=\(observed); semantic=\(semantic.count); rendered=\(rendered.findings.count); differential=\(differential.count); vision=\(rendered.visionSeconds)s\n".utf8))
                    cellFailed = !differential.isEmpty
                    XCTAssertEqual(differential, [], "\(label), differential truncation: \(differential)")
                }
                if cellFailed { return }
            }
        }
        for rule in ["rendered-chrome", "rendered-edge", "rendered-margin", "rendered-overlap",
                     "rendered-escape", "rendered-truncation", "rendered-text-geometry"] {
            report.append("\(rule): detections=0 (clean matrix); falsePositives=\(falsePositives[rule, default: 0])")
        }
        let mean = visionSeconds.reduce(0, +) / Double(max(1, visionSeconds.count))
        report.append("missingControls=\(missingControls); ocrExtraCount=\(ocrExtraCount); windows=\(captures.count); visionRequests=\(visionSeconds.count); visionMean=\(mean)s; visionMax=\(visionSeconds.max() ?? 0)s")
        try report.joined(separator: "\n").appending("\n")
            .write(to: reportURL, atomically: true, encoding: .utf8)
        try contactSheet(captures, to: root.appending(path: ".build/test-artifacts/images/chrome-matrix.png"))
    }
    #endif

    @MainActor private final class RootGeometry {
        var content = CGRect.null
    }

    /// The four public entry points must share the correction, including when the app opts out
    /// of title-bar painting. Window creation is intentionally smaller than the content minimum.
    func testEveryPaletteRootOverloadAnchorsAndPropagatesOversizedMinimum() throws {
        _ = NSApplication.shared
        let minimum = CGSize(width: 800, height: 700)
        let roots: [(String, @MainActor (AnyView) -> AnyView)] = [
            ("implicit", { AnyView($0.lumenPaletteRoot()) }),
            ("explicit", { AnyView($0.lumenPaletteRoot(store: .active)) }),
            ("implicit plain chrome", { AnyView($0.lumenPaletteRoot(windowChrome: false)) }),
            ("explicit plain chrome", { AnyView($0.lumenPaletteRoot(store: .active, windowChrome: false)) }),
            ("nested implicit", { AnyView($0.lumenPaletteRoot().lumenPaletteRoot()) }),
            ("nested mixed", { AnyView($0.lumenPaletteRoot(store: .active, windowChrome: false).lumenPaletteRoot()) }),
        ]
        var singleRootMinimum: CGSize?
        var singleRootOrigin: CGPoint?
        for (name, wrap) in roots {
            let geometry = RootGeometry()
            let content = AnyView(VStack(alignment: .leading, spacing: 0) {
                Button("Top content") {}
                Spacer(minLength: 0)
                Button("Bottom content") {}
            }
                .padding(LumenMetrics.standard.spacing.s6)
                .frame(minWidth: minimum.width, minHeight: minimum.height, alignment: .topLeading)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    geometry.content = $0
                })
            let host = NSHostingView(rootView: wrap(content))
            host.sizingOptions = []
            let window = LumenHeadlessHost.window(contentRect: .init(x: 80, y: 80, width: 640, height: 400),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.title = "Root overload: \(name)"
            window.contentView = host
            window.setContentSize(.init(width: 640, height: 400))
            LumenHeadlessHost.order(window)
            defer { window.close() }
            settle(window)
            XCTAssertGreaterThanOrEqual(window.contentMinSize.width, minimum.width, name)
            XCTAssertGreaterThanOrEqual(window.contentMinSize.height, minimum.height, name)
            XCTAssertFalse(geometry.content.isNull, "The content frame must be measured: \(name)")
            let hostScreen = window.convertToScreen(host.convert(host.bounds, to: nil))
            let usable = window.convertToScreen(window.contentLayoutRect)
            let usableTop = hostScreen.maxY - usable.maxY
            XCTAssertGreaterThan(geometry.content.minY, usableTop + 0.5, "Content must retain a gap below chrome: \(name)")
            XCTAssertGreaterThanOrEqual(geometry.content.minX, 0, "Overflow must remain reachable from its leading edge: \(name)")
            if name == "implicit" {
                singleRootMinimum = window.contentMinSize
                singleRootOrigin = geometry.content.origin
            } else if name.hasPrefix("nested") {
                let expectedMinimum = try XCTUnwrap(singleRootMinimum)
                let expectedOrigin = try XCTUnwrap(singleRootOrigin)
                XCTAssertEqual(window.contentMinSize.width, expectedMinimum.width, accuracy: 0.5, name)
                XCTAssertEqual(window.contentMinSize.height, expectedMinimum.height, accuracy: 0.5, name)
                XCTAssertEqual(geometry.content.minX, expectedOrigin.x, accuracy: 0.5, "Nested roots must not double the page inset")
                XCTAssertEqual(geometry.content.minY, expectedOrigin.y, accuracy: 0.5, "Nested roots must not double the chrome gap")
            }
            let findings = LumenConformance.liveWindow(window)
            XCTAssertEqual(findings, [], "Root overload \(name): \(findings)")
        }
    }

    func testUnpaddedPaletteRootStillReportsPageEdge() throws {
        _ = NSApplication.shared
        let content = AnyView(VStack(alignment: .leading, spacing: 0) {
            Button("Top content") {}
            Spacer(minLength: 0)
            Button("Bottom content") {}
        }.frame(minWidth: 800, minHeight: 700, alignment: .topLeading))
        let host = NSHostingView(rootView: content.lumenPaletteRoot())
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: .init(x: 80, y: 80, width: 640, height: 400),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = "Root overload: implicit"
        window.contentView = host
        window.setContentSize(.init(width: 640, height: 400))
        LumenHeadlessHost.order(window)
        defer { window.close() }
        settle(window)
        let findings = LumenConformance.liveWindow(window)
        // This fixture proves bitmap margin/edge detection. Semantic page-edge findings
        // may also fire, but depend on the elements available to the semantic traversal.
        XCTAssertTrue(findings.contains { $0.message.contains("rendered-margin:") }
            && findings.contains { $0.message.contains("rendered-edge:") },
            "Unpadded root must report rendered margin and edge ink; findings: \(findings)")
    }

    @MainActor private struct StatefulRootLeaf: View {
        @State private var identity = UUID()
        let measured: @MainActor (UUID, CGRect) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button("Stateful top control") {}
                Spacer(minLength: 0)
                Text("Stateful bottom content")
            }
            .frame(minWidth: 800, minHeight: 700, alignment: .topLeading)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                measured(identity, frame)
            }
        }
    }

    @MainActor private final class RootLifecycleMeasurements {
        var values: [(UUID, CGRect)] = []
    }

    func testBareHostLeafStateAcrossWindowAttachment() throws {
        _ = NSApplication.shared
        let measurements = RootLifecycleMeasurements()
        let host = NSHostingView(rootView: StatefulRootLeaf { identity, frame in
            measurements.values.append((identity, frame))
        })
        host.sizingOptions = []
        host.frame = .init(x: 0, y: 0, width: 640, height: 400)
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let initialIdentity = try XCTUnwrap(measurements.values.first?.0)
        let window = LumenHeadlessHost.window(contentRect: .init(x: 80, y: 80, width: 640, height: 400),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = host
        window.setContentSize(.init(width: 640, height: 400))
        LumenHeadlessHost.order(window)
        defer { window.close() }
        settle(window)
        XCTAssertEqual(Set(measurements.values.map { $0.0 }), [initialIdentity],
                       "Bare-host control for attachment lifecycle")
    }

    func testRootPreservesLeafStateFromOffWindowLayoutThroughOverflowAndResize() throws {
        _ = NSApplication.shared
        let measurements = RootLifecycleMeasurements()
        let content = StatefulRootLeaf { identity, frame in
            measurements.values.append((identity, frame))
        }.lumenPaletteRoot()
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        host.frame = .init(x: 0, y: 0, width: 640, height: 400)
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let offWindowCount = measurements.values.count
        XCTAssertGreaterThan(offWindowCount, 0, "The leaf must be measured before attachment")
        let initialIdentity = try XCTUnwrap(measurements.values.first?.0)
        let window = LumenHeadlessHost.window(contentRect: .init(x: 80, y: 80, width: 640, height: 400),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = "Root state lifecycle"
        window.contentView = host
        window.setContentSize(.init(width: 640, height: 400))
        LumenHeadlessHost.order(window)
        defer { window.close() }
        settle(window)
        XCTAssertGreaterThan(measurements.values.count, offWindowCount,
                             "The leaf must be measured after attaching to the live undersized window")
        XCTAssertEqual(Set(measurements.values.map { $0.0 }), [initialIdentity],
                       "Switching to live overflow placement must preserve leaf state")
        XCTAssertGreaterThanOrEqual(window.contentMinSize.width, 800)
        XCTAssertGreaterThanOrEqual(window.contentMinSize.height, 700)
        let attachedFrame = try XCTUnwrap(measurements.values.last?.1)
        let hostScreen = window.convertToScreen(host.convert(host.bounds, to: nil))
        let usable = window.convertToScreen(window.contentLayoutRect)
        XCTAssertGreaterThan(attachedFrame.minY, hostScreen.maxY - usable.maxY + 0.5,
                             "The live root must place the stateful content below the usable top with a gap")
        let attachedCount = measurements.values.count
        window.setContentSize(.init(width: 1000, height: 900))
        settle(window)
        XCTAssertGreaterThan(measurements.values.count, attachedCount,
                             "Resizing past the content minimum must produce a fresh geometry measurement")
        XCTAssertEqual(Set(measurements.values.map { $0.0 }), [initialIdentity],
                       "Leaving overflow placement must preserve the same leaf state")
    }

    func testNestedScaffoldDoesNotExemptSurroundingSiblingControls() throws {
        _ = NSApplication.shared
        let geometry = RootGeometry()
        let content = VStack(spacing: 0) {
            Button("Sibling above scaffold") {}
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    geometry.content = $0
                }
            LumenUtilityWindow(minimumSize: .init(width: 640, height: 400)) {
                Text("Nested scaffold content").padding(24)
            } topLeading: {
                Text("Nested utility")
            }
            Button("Sibling below scaffold") {}
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .lumenPaletteRoot()
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: .init(x: 80, y: 80, width: 900, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = "Nested scaffold ownership"
        window.contentView = host
        window.setContentSize(.init(width: 900, height: 700))
        LumenHeadlessHost.order(window)
        defer { window.close() }
        settle(window)
        XCTAssertFalse(geometry.content.isNull)
        let hostScreen = window.convertToScreen(host.convert(host.bounds, to: nil))
        let usable = window.convertToScreen(window.contentLayoutRect)
        XCTAssertGreaterThan(geometry.content.minY, hostScreen.maxY - usable.maxY + 0.5,
                             "A descendant scaffold cannot exempt the sibling above its complete extent")
        let findings = LumenConformance.liveWindow(window)
        XCTAssertFalse(findings.contains { $0.subject.contains("Sibling above scaffold") &&
            ($0.message.hasPrefix("chrome:") || $0.message.hasPrefix("top-edge:")) }, "\(findings)")
    }

    /// A deliberately unprotected native control proves the live audit discovers real controls
    /// without a root, preferences, or a conformance wrapper around the content.
    func testRootlessNativeChromeCollisionIsDiscovered() throws {
        _ = NSApplication.shared
        let window = LumenHeadlessHost.window(contentRect: .init(x: 100, y: 100, width: 640, height: 400),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = "Rootless chrome negative"
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let button = NSButton(title: "Chrome collision fixture", target: nil, action: nil)
        button.frame = CGRect(x: content.bounds.midX - 100, y: content.bounds.maxY - 24, width: 200, height: 24)
        content.addSubview(button)
        LumenHeadlessHost.order(window)
        settle(window)
        let findings = LumenConformance.liveWindow(window)
        XCTAssertTrue(findings.contains { $0.message.localizedCaseInsensitiveContains("chrome") || $0.message.localizedCaseInsensitiveContains("traffic") },
                      "The audit must discover the native control in the measured chrome band: \(findings)")
    }

    @MainActor private struct Hosted {
        let window: NSWindow
        func close() {
            window.close()
        }
    }
    private func makeWindow(_ cell: Cell, rooted: Bool, colorScheme: ColorScheme = .dark) -> Hosted {
        let v = cell.values, kind = Self.kinds[v[0]], chrome = Self.chrome[v[1]], scale = Self.scales[v[5]]
        let size = Self.sizes[v[6]] == "minimum" ?
            CGSize(width: kind.minimum.width * scale, height: kind.minimum.height * scale) : CGSize(width: 1200, height: 820)
        let factor = Self.contentMinimums[v[7]].factor
        let minimum = CGSize(width: size.width * factor, height: size.height * factor)
        let content = AnyView(kind.wrap(Self.compositions[v[4]].content())
            .frame(minWidth: minimum.width, minHeight: minimum.height))
        let root = (rooted ? AnyView(content.lumenPaletteRoot()) : content)
            .lumenTextScale(scale)
            .environment(\.colorScheme, colorScheme)
            .environment(\.appearsActive, true)
        let host = NSHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        host.sceneBridgingOptions = [.toolbars]
        var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if Self.fullSize[v[3]] { mask.insert(.fullSizeContentView) }
        let window: NSWindow = kind.name == "NSPanel" ?
            LumenHeadlessHost.panel(contentRect: .init(origin: .zero, size: size), styleMask: mask, backing: .buffered, defer: false) :
            LumenHeadlessHost.window(contentRect: .init(origin: .zero, size: size), styleMask: mask, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Matrix \(cell.label)"
        window.titleVisibility = chrome.title
        window.titlebarAppearsTransparent = chrome.title == .hidden
        window.toolbarStyle = chrome.style
        window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        if Self.toolbars[v[2]] { window.toolbar = NSToolbar(identifier: "matrix") }
        if kind.name == "swiftUIHost" {
            let controller = NSHostingController(rootView: AnyView(root))
            controller.sizingOptions = []
            controller.sceneBridgingOptions = [.toolbars]
            if let controllerHost = controller.view as? NSHostingView<AnyView> {
                controllerHost.sizingOptions = []
                controllerHost.sceneBridgingOptions = [.toolbars]
            }
            window.contentViewController = controller
        } else { window.contentView = host }
        window.setContentSize(size)
        // Presentation needs a live check; this cell exercises the hosted sheet content only.
        LumenHeadlessHost.order(window)
        return Hosted(window: window)
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<12 {
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
    private func capture(_ window: NSWindow, index: Int) throws -> NSImage {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appending(path: ".build/test-artifacts/images/matrix-cells")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "cell-\(index).png")
        let rendered = try LumenRenderedAudit.capture(in: window)
        let bitmap = NSBitmapImageRep(cgImage: rendered.image)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return try XCTUnwrap(NSImage(contentsOf: url))
    }
    private func contactSheet(_ cells: [(String, NSImage)], to url: URL) throws {
        let columns = 5, tile = CGSize(width: 330, height: 260)
        let rows = (cells.count + columns - 1) / columns
        let size = CGSize(width: tile.width * CGFloat(columns), height: tile.height * CGFloat(rows))
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        let font = try XCTUnwrap(NSFont(name: "Arial", size: 10))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, cell) in cells.enumerated() {
            let x = CGFloat(index % columns) * tile.width, y = size.height - CGFloat(index / columns + 1) * tile.height
            let available = CGRect(x: x + 5, y: y + 42, width: tile.width - 10, height: tile.height - 47)
            let scale = min(available.width / cell.1.size.width, available.height / cell.1.size.height)
            let drawn = CGSize(width: cell.1.size.width * scale, height: cell.1.size.height * scale)
            cell.1.draw(in: CGRect(x: available.midX - drawn.width / 2, y: available.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
            (cell.0 as NSString).draw(in: CGRect(x: x + 6, y: y + 3, width: tile.width - 12, height: 36),
                                    withAttributes: [.font: font, .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
