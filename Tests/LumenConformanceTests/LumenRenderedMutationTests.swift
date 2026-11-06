import AppKit
import LumenTestSupport
@_spi(LayoutAudit) import LumenUI
import SwiftUI
import XCTest
#if DEBUG
/// Each mutation changes pixels in a real window. Expected rules and defect rectangles remain
/// in the test, never in detector input. Clean counterparts use the identical drawing mechanism.
@MainActor
final class LumenRenderedMutationTests: XCTestCase {
    private enum Mutation: String, CaseIterable {
        case canvasChrome, shapeEdge, imageControl, nativeEscape, canvasClip, pageMargin
        case textHead, textMiddle, textTail, textClip, textOverlap

        var rule: String {
            switch self {
            case .canvasChrome: "rendered-chrome"
            case .pageMargin: "rendered-margin"
            case .shapeEdge: "rendered-edge"
            case .imageControl: "rendered-overlap"
            case .nativeEscape: "rendered-escape"
            case .canvasClip, .textClip: "rendered-edge"
            case .textHead, .textMiddle, .textTail: "rendered-truncation"
            case .textOverlap: "rendered-text-geometry"
            }
        }
        var differential: Bool { self == .textHead || self == .textMiddle || self == .textTail }
    }
    private struct Observation {
        let label: String
        let image: CGImage
        let frame: CGRect
        let rectangles: [CGRect]
    }
    private struct Hosted {
        let window: NSWindow
        let defect: CGRect
        let expand: @MainActor () -> Void
    }

    func testCanvasChrome() throws { try run([.canvasChrome]) }
    func testShapeEdge() throws { try run([.shapeEdge]) }
    func testImageControlOverlap() throws { try run([.imageControl]) }
    func testNativeDrawingEscape() throws { try run([.nativeEscape]) }
    func testCanvasTextClip() throws { try run([.canvasClip]) }
    func testPageMargin() throws { try run([.pageMargin]) }
    func testTextHeadTruncation() throws { try run([.textHead]) }
    func testTextMiddleTruncation() throws { try run([.textMiddle]) }
    func testTextTailTruncation() throws { try run([.textTail]) }
    func testTextClipWithoutEllipsis() throws { try run([.textClip]) }
    func testTextOverlap() throws { try run([.textOverlap]) }

    /// Diagnose capture fidelity independently of detector acceptance. In particular, a Canvas
    /// proposed inside native chrome may receive different layout or compositing treatment.
    func testCanvasCaptureDiagnostic() async throws {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        let hosted = makeWindow(.canvasChrome, scale: 1, dark: false, broken: true)
        defer { hosted.window.close() }
        settle(hosted.window)
        let window = hosted.window
        let content = try XCTUnwrap(window.contentView)
        let frame = try XCTUnwrap(content.superview)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let reports = repository.appending(path: ".build/test-artifacts")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        var report = ["window=\(window.frame); usable=\(window.contentLayoutRect); defect=\(hosted.defect)"]
        defer {
            do {
                try report.joined(separator: "\n").appending("\n").write(
                    to: reports.appending(path: "canvas-capture-diagnostic.txt"), atomically: true, encoding: .utf8)
            } catch { XCTFail("Cannot preserve capture diagnosis: \(error)") }
        }
        func describe(_ view: NSView, depth: Int) {
            report.append("\(String(repeating: " ", count: depth))\(type(of: view)): frame=\(view.frame), bounds=\(view.bounds), safeArea=\(view.safeAreaInsets), clips=\(view.clipsToBounds), hidden=\(view.isHidden), alpha=\(view.alphaValue)")
            if let layer = view.layer {
                report.append(" layer frame=\(layer.frame), bounds=\(layer.bounds), position=\(layer.position), masks=\(layer.masksToBounds), hidden=\(layer.isHidden), opacity=\(layer.opacity), sublayers=\(layer.sublayers?.count ?? 0), contents=\(layer.contents.map { String(describing: type(of: $0)) } ?? "nil")")
            }
            for child in view.subviews { describe(child, depth: depth + 1) }
        }
        describe(frame, depth: 0)
        func save(_ image: CGImage, route: String) throws {
            let representation = NSBitmapImageRep(cgImage: image)
            try XCTUnwrap(representation.representation(using: .png, properties: [:]))
                .write(to: reports.appending(path: "canvas-capture-\(route).png"))
            report.append("\(route): \(image.width) x \(image.height)")
        }
        try save(LumenRenderedAudit.capture(in: window).image, route: "frame-bitmap")
        frame.displayIfNeeded()
        let bitmap = try XCTUnwrap(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        try save(XCTUnwrap(bitmap.cgImage), route: "bitmap")
    }

    private func run(_ mutations: [Mutation]) throws {
        _ = NSApplication.shared
        NSApp.finishLaunching()
        var observations: [Observation] = []
        var counts: [String: (mutations: Int, detected: Int)] = [:]
        var falsePositives: [String: Int] = [:]
        var timings: [Double] = []
        var report: [String] = ["mutations=\(mutations.map(\.rawValue).joined(separator: ",")); scales=1.0,1.3; appearances=light,dark; clean counterparts=\(mutations.count * 4)"]
        for mutation in mutations {
            for scale in [CGFloat(1), 1.3] {
                for dark in [false, true] {
                    for broken in [true, false] {
                        try autoreleasepool {
                            let label = "\(mutation.rawValue) / \(scale) / \(dark ? "dark" : "light") / \(broken ? "mutation" : "clean")"
                            let hosted = makeWindow(mutation, scale: scale, dark: dark, broken: broken)
                            defer { hosted.window.close() }
                            settle(hosted.window)
                            let capture = try LumenRenderedAudit.capture(in: hosted.window)
                            let result = try LumenRenderedAudit.analyze(capture)
                            timings.append(result.visionSeconds)
                            var findings = result.findings
                            var findingRects = result.findingRects
                            if mutation.differential {
                                hosted.expand()
                                settle(hosted.window)
                                let large = try LumenRenderedAudit.analyze(LumenRenderedAudit.capture(in: hosted.window))
                                timings.append(large.visionSeconds)
                                let differential = LumenRenderedAudit.differential(result, large)
                                findings += differential
                                findingRects += differential.compactMap { finding in
                                    result.lines.first { $0.text == finding.view }?.frame
                                }
                            }
                            let rules = Set(findings.map(\.rule))
                            var count = counts[mutation.rule] ?? (0, 0)
                            if broken {
                                count.mutations += 1
                                if rules.contains(mutation.rule) { count.detected += 1 }
                                XCTAssertEqual(rules, [mutation.rule], "\(label): \(findings)")
                                if !findings.isEmpty {
                                    XCTAssertEqual(findingRects.count, findings.count, label)
                                    XCTAssertTrue(findingRects.contains { !$0.isEmpty && $0.intersects(hosted.defect) },
                                                  "The finding must outline the actual defect: \(label), defect=\(hosted.defect), findings=\(findingRects)")
                                }
                            } else {
                                for finding in findings { falsePositives[finding.rule, default: 0] += 1 }
                                XCTAssertEqual(findings, [], "\(label): \(findings)")
                            }
                            counts[mutation.rule] = count
                            report.append("\(label): rules=\(rules.sorted()); lines=\(result.lines.map(\.text)); Vision=\(result.visionSeconds)s")
                            if broken && scale == 1 {
                                observations.append(.init(label: label, image: result.image, frame: result.frame,
                                                          rectangles: findingRects))
                            }
                        }
                    }
                }
            }
        }
        for (rule, value) in counts.sorted(by: { $0.key < $1.key }) {
            report.append("\(rule): detections=\(value.detected)/\(value.mutations), clean false positives=\(falsePositives[rule, default: 0])")
        }
        for rule in falsePositives.keys.sorted() where counts[rule] == nil {
            report.append("\(rule): detections=0/0, clean false positives=\(falsePositives[rule, default: 0])")
        }
        if let maximum = timings.max(), !timings.isEmpty {
            report.append("Vision windows=\(timings.count), mean=\(timings.reduce(0,+)/Double(timings.count))s, max=\(maximum)s")
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: repository.appending(path: ".build/test-artifacts"), withIntermediateDirectories: true)
        try report.joined(separator: "\n").appending("\n").write(to: repository.appending(path: ".build/test-artifacts/rendered-mutations-\(mutations.map(\.rawValue).joined(separator: "-")).txt"),
                                                                atomically: true, encoding: .utf8)
        let shots = repository.appending(path: ".build/test-artifacts/images")
        let retained = try retain(observations, in: shots.appending(path: "rendered-mutation-cells"))
        try contactSheet(retained, to: shots.appending(path: "rendered-audit.png"))
    }

    private func makeWindow(_ mutation: Mutation, scale: CGFloat, dark: Bool, broken: Bool) -> Hosted {
        let size = CGSize(width: 480, height: 240)
        let window = LumenHeadlessHost.window(contentRect: .init(x: 120, y: 120, width: size.width, height: size.height),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let root = FlatBackground(frame: NSRect(origin: .zero, size: window.contentView?.bounds.size ?? size))
        root.dark = dark
        window.contentView = root
        window.setContentSize(size)
        let foreground = dark ? Color.white : Color.black
        var defect = CGRect.zero
        var expand: @MainActor () -> Void = {}
        func attach<V: View>(_ view: V, frame: CGRect, clipped: Bool = true) -> NSHostingView<V> {
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            host.frame = frame
            host.clipsToBounds = clipped
            root.addSubview(host)
            return host
        }
        func naturalWidth(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13 * scale)]).width) + 16
        }
        switch mutation {
        case .pageMargin:
            let view = Canvas { context, _ in
                context.fill(Path(CGRect(x: broken ? 4 : 40, y: 70, width: 12, height: 16)), with: .color(.red))
            }.frame(maxWidth: .infinity, maxHeight: .infinity).lumenPaletteRoot()
            _ = attach(view, frame: root.bounds)
            defect = CGRect(x: 0, y: 0, width: 24, height: root.bounds.height)
        case .canvasChrome:
            let bandHeight = window.frame.height - window.contentLayoutRect.height
            let lineY = broken ? bandHeight / 2 : bandHeight + 40
            let host = attach(Canvas { context, _ in
                var path = Path()
                path.move(to: CGPoint(x: 160, y: lineY))
                path.addLine(to: CGPoint(x: 310, y: lineY))
                context.stroke(path, with: .color(.red), lineWidth: 3)
            }.ignoresSafeArea(), frame: root.bounds)
            // This negative fixture deliberately draws through chrome. NSHostingView's native
            // safe-area injection can collapse a tiny host before ignoresSafeArea is evaluated.
            // safeAreaRegions is public on macOS 13.3+; the package deploys to macOS 27.
            host.safeAreaRegions = []
            defect = CGRect(x: 160, y: root.bounds.maxY - lineY - 2, width: 150, height: 4)
        case .shapeEdge:
            let frame = CGRect(x: broken ? root.bounds.maxX - 12 : root.bounds.maxX - 92,
                               y: 100, width: 48, height: 40)
            _ = attach(Ellipse().fill(Color.red).frame(width: 48, height: 40), frame: frame)
            defect = frame.intersection(root.bounds)
        case .imageControl:
            let button = NSButton(title: "Open Fixture", target: nil, action: nil)
            button.font = .systemFont(ofSize: 13 * scale)
            button.frame = CGRect(x: 160, y: 105, width: 160, height: 32)
            root.addSubview(button)
            let image = NSImage(size: CGSize(width: 100, height: 28), flipped: false) { rect in
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
                return true
            }
            let imageView = NSImageView(frame: CGRect(x: broken ? 270 : 345, y: 110, width: 100, height: 28))
            imageView.image = image
            root.addSubview(imageView)
            defect = imageView.frame.intersection(button.frame)
        case .nativeEscape:
            let drawing = EscapingDrawing(frame: CGRect(x: 120, y: 105, width: 100, height: 40))
            drawing.escapes = broken
            drawing.clipsToBounds = false
            root.addSubview(drawing)
            defect = CGRect(x: drawing.frame.maxX, y: drawing.frame.minY + 8, width: 55, height: 22)
        case .canvasClip:
            let width: CGFloat = broken ? 88 : naturalWidth("Canvas lettering crosses boundary")
            let frame = CGRect(x: 90, y: 108, width: width, height: 26 * scale)
            _ = attach(Canvas { context, _ in
                context.draw(Text("Canvas lettering crosses boundary")
                    .font(.system(size: 13 * scale)).foregroundColor(foreground), at: CGPoint(x: 0, y: 2), anchor: .topLeading)
            }.clipped(), frame: frame)
            defect = frame
        case .textHead, .textMiddle, .textTail:
            let mode: Text.TruncationMode = mutation == .textHead ? .head : mutation == .textMiddle ? .middle : .tail
            let width: CGFloat = broken ? 110 : naturalWidth("An exceptionally long source string")
            let view = Text("An exceptionally long source string")
                .font(.system(size: 13 * scale)).foregroundStyle(foreground)
                .lineLimit(1).truncationMode(mode).frame(maxWidth: .infinity, alignment: .leading)
            let host = attach(view, frame: CGRect(x: 40, y: 105, width: width, height: 30))
            defect = host.frame
            expand = { host.setFrameSize(CGSize(width: 680, height: 30)); window.setContentSize(CGSize(width: 760, height: 240)) }
        case .textClip:
            let width: CGFloat = broken ? 91 : naturalWidth("Visible glyphs continue past boundary")
            let view = Text("Visible glyphs continue past boundary")
                .font(.system(size: 13 * scale)).foregroundStyle(foreground)
                .fixedSize().frame(width: width, alignment: .leading).clipped()
            let host = attach(view, frame: CGRect(x: 90, y: 106, width: width, height: 30))
            defect = host.frame
        case .textOverlap:
            let first = NSTextField(labelWithString: "First text content")
            let second = NSTextField(labelWithString: "Second text content")
            for label in [first, second] {
                label.font = .systemFont(ofSize: 13 * scale)
                label.textColor = dark ? .white : .black
                label.maximumNumberOfLines = 1
                label.sizeToFit()
                root.addSubview(label)
            }
            first.setFrameOrigin(CGPoint(x: 90, y: 110))
            second.setFrameOrigin(CGPoint(x: broken ? 130 : 270, y: broken ? 113 : 110))
            defect = first.frame.intersection(second.frame)
        }
        LumenHeadlessHost.order(window)
        return Hosted(window: window, defect: window.convertToScreen(root.convert(defect, to: nil)), expand: expand)
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<12 {
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private final class FlatBackground: NSView {
        var dark = false
        override var isOpaque: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            (dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor.white).setFill()
            bounds.fill()
        }
    }
    private final class EscapingDrawing: NSView {
        var escapes = false
        override var wantsDefaultClipping: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemRed.setFill()
            CGRect(x: 40, y: 8, width: escapes ? 115 : 45, height: 22).fill()
        }
    }

    private struct RetainedObservation: Codable {
        let label: String
        let frame: CGRect
        let rectangles: [CGRect]
    }
    /// Assemble the sheet from retained captures, so rerunning one changed detector fixture does
    /// not rerender the unchanged fixtures. Each case has its own report and stored pixels.
    private func retain(_ observations: [Observation], in directory: URL) throws -> [Observation] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for observation in observations {
            let name = observation.label.replacingOccurrences(of: " / ", with: "-").replacingOccurrences(of: " ", with: "-")
            let rep = NSBitmapImageRep(cgImage: observation.image)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: directory.appending(path: name + ".png"))
            let metadata = RetainedObservation(label: observation.label, frame: observation.frame, rectangles: observation.rectangles)
            try JSONEncoder().encode(metadata).write(to: directory.appending(path: name + ".json"))
        }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
                let metadata = try JSONDecoder().decode(RetainedObservation.self, from: Data(contentsOf: url))
                let image = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url.deletingPathExtension().appendingPathExtension("png")))?.cgImage)
                return Observation(label: metadata.label, image: image, frame: metadata.frame, rectangles: metadata.rectangles)
            }
    }

    private func contactSheet(_ observations: [Observation], to url: URL) throws {
        let columns = 4, tile = CGSize(width: 400, height: 270)
        let rows = (observations.count + columns - 1) / columns
        let size = CGSize(width: CGFloat(columns) * tile.width, height: CGFloat(rows) * tile.height)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        let font = try XCTUnwrap(NSFont(name: "Arial", size: 10))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        CGRect(origin: .zero, size: size).fill()
        for (index, observation) in observations.enumerated() {
            let origin = CGPoint(x: CGFloat(index % columns) * tile.width, y: size.height - CGFloat(index / columns + 1) * tile.height)
            let available = CGRect(x: origin.x + 8, y: origin.y + 34, width: tile.width - 16, height: tile.height - 42)
            let factor = min(available.width / observation.frame.width, available.height / observation.frame.height)
            let drawn = CGRect(x: available.minX, y: available.minY,
                               width: observation.frame.width * factor, height: observation.frame.height * factor)
            NSImage(cgImage: observation.image, size: observation.frame.size).draw(in: drawn)
            NSColor.systemRed.setStroke()
            for rect in observation.rectangles {
                let local = rect.offsetBy(dx: -observation.frame.minX, dy: -observation.frame.minY)
                let mapped = CGRect(x: drawn.minX + local.minX * factor, y: drawn.minY + local.minY * factor,
                                    width: local.width * factor, height: local.height * factor)
                let path = NSBezierPath(rect: mapped)
                path.lineWidth = 1.5
                path.stroke()
            }
            (observation.label as NSString).draw(in: CGRect(x: origin.x + 8, y: origin.y + 7, width: tile.width - 16, height: 24),
                                                  withAttributes: [.font: font, .foregroundColor: NSColor.black])
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
#endif
