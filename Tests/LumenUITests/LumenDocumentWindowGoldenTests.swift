import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI
import LumenConformance


/// One new subject, in the six gallery variants. A test-local document fixture is captured with its
/// native title bar; recording reports review-required failures, never an automatic acceptance.
@MainActor
final class LumenDocumentWindowGoldenTests: XCTestCase {
    private let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens")

    func testHeadlessControlStateDiagnostic() throws {
        _ = try render(.init(themeID: LumenThemes.standardID, colorScheme: .light))
    }

    func testDocumentWindow() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["LUMEN_SKIP_GOLDENS"] == "1",
                      "Golden images are checked on the recording Mac")
        let variants = LumenSnapshot.Variant.all(for: LumenRegistry.core.galleryThemes)
        XCTAssertEqual(variants.count, 6)
        let selection = ProcessInfo.processInfo.environment["LUMEN_DOCUMENT_GOLDEN_VARIANTS"]
            .map { Set($0.split(separator: ",").map(String.init)) }
        if let selection {
            let known = Set(variants.map(\.label))
            guard !selection.isEmpty, selection.isSubset(of: known) else {
                XCTFail("Unknown document golden variant selection"); return
            }
        }
        for variant in variants where selection?.contains(variant.label) ?? true {
            let name = "document-window@\(variant.label).png"
            let actual = try render(variant)
            let url = directory.appending(path: name)
            try LumenFilterConfinedGolden.verify(actual, at: url)
        }
    }

    private var conformanceSizes: [CGSize] {
        [DocumentWindowFixture.minimumSize, CGSize(width: 1440, height: 900)]
    }

    func testDocumentStructureAtMinimumAndLargeSizes() {
        for modified in [false, true] {
            for chrome in [LumenChromeStyle.drawn, .glass] {
                let findings = LumenConformance.windowStructure(kind: .document, sizes: conformanceSizes) {
                    DocumentWindowFixture(modified: modified).lumenChromeStyle(chrome)
                }
                XCTAssertEqual(findings.map(\.description), [], "modified=\(modified), chrome=\(chrome)")
            }
        }
    }

    func testDocumentTruncationAtMinimumAndLargeSizes() {
        XCTAssertEqual(LumenConformance.truncation(sizes: conformanceSizes) {
            DocumentWindowFixture()
        }.map(\.description), [])
    }

    func testDocumentNarrowSizingAtMinimumAndLargeWidths() {
        for size in conformanceSizes {
            XCTAssertEqual(LumenConformance.narrowSizing([
                ("Document window", AnyView(DocumentWindowFixture())),
            ], referenceWidth: size.width).map(\.description), [])
        }
    }

    private func render(_ variant: LumenSnapshot.Variant) throws -> Data {
        let store = LumenSnapshot.store(for: variant, registry: .core)
        return try LumenThemeStore.withActiveStore(store) {
            try MainActor.assumeIsolated {

                let root = DocumentWindowFixture()
                    .lumenPaletteRoot(store: store)
                    .lumenMetrics(.standard)
                    .lumenChromeStyle(.drawn)
                    .environment(\.colorScheme, variant.colorScheme)
                    .environment(\.displayScale, 2)
                    .environment(\.appearsActive, true)
                    .environment(\.controlActiveState, LumenHeadlessHost.snapshotControlActiveState)

                let host = NSHostingView(rootView: root)
                host.sizingOptions = []
                host.sceneBridgingOptions = [.toolbars]
                let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: DocumentWindowFixture.defaultSize),
                                      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                      backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: variant.colorScheme == .dark ? .darkAqua : .aqua)
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.toolbarStyle = .unifiedCompact
                window.contentView = host
                LumenHeadlessHost.prepare(window)
                LumenHeadlessHost.order(window)
                defer { window.close() }
                for _ in 0..<20 {
                    (host.superview ?? host).layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
                }


                XCTAssertNotNil(window.toolbar, "A document golden includes its native toolbar")
                let frameView = try XCTUnwrap(host.superview)
                XCTAssertGreaterThan(frameView.bounds.height, window.contentLayoutRect.height)
                let captures = directory.deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().appending(path: ".build/document-captures")
                try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
                let captureURL = captures.appending(path: "document-\(variant.label).png")
                let png = try LumenHeadlessHost.png(of: window)
                try png.write(to: captureURL)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
                print("DOCUMENT GEOMETRY: \(variant.label); requested=\(DocumentWindowFixture.defaultSize); window=\(window.frame); content=\(window.contentLayoutRect); hostFrame=\(host.frame); hostBounds=\(host.bounds); frameBounds=\(frameView.bounds); minimum=\(window.contentMinSize); backing=\(window.backingScaleFactor); bitmap=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
                return png
            }
        }
    }
}

struct DocumentWindowFixture: View {
    static let minimumSize = CGSize(width: 640, height: 400)
    static let defaultSize = CGSize(width: 1200, height: 720)

    @State private var title = "Field Notes.txt"
    @State private var inspectorPresented = true
    @State private var text = """
    Field Notes

    Morning light along the coast.
    The tide has left a narrow line of shells above the water.

    Next visit
    Return at sunrise and sketch the northern headland.
    """
    let modified: Bool

    init(modified: Bool = true) { self.modified = modified }

    var body: some View {
        LumenDocumentWindow(title: $title, isModified: modified,
                            inspectorPresented: $inspectorPresented, minimumSize: Self.minimumSize) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(20)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .lumenColumnContent("Document text")
        } inspector: {
            VStack(alignment: .leading, spacing: 20) {
                LumenInspectorHeader("Document", subtitle: "Plain text", systemImage: "doc.text", hue: .hueTeal)
                LumenInspectorSection("Text Properties") {
                    LumenInspectorRow("Format") { Text("Plain text") }
                    LumenInspectorRow("Encoding") { Text("UTF-8") }
                    LumenInspectorRow("Line endings") { Text("LF") }
                }
            }
        } statusBar: {
            Text("Plain Text")
            Spacer(minLength: 8)
            Text("UTF-8")
        }
        .inspectorWidth((240, 280, 380))
    }
}
