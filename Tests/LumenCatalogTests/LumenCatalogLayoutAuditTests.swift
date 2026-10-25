import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import LumenTokens
@_spi(LayoutAudit) @testable import LumenUI
import LumenConformance
@testable import LumenCatalog

/// One audit of each Catalog scene's content and the production presentations listed below.
/// These are AppKit hosts of production roots, not a launch of the App's scene dispatcher.
/// Scene constraints, document lifecycle, status-item attachment and the explicitly unhosted
/// presentations remain outside this test; the report preserves those coverage limits.
@MainActor
final class LumenCatalogLayoutAuditTests: XCTestCase {
    struct Subject {
        let name: String
        let source: String
        let size: CGSize
        let panel: Bool
        let compact: Bool
        let fullSize: Bool
        let outer: @MainActor (AnyView) -> AnyView
        let make: @MainActor () -> AnyView

        init(_ name: String, source: String, size: CGSize, panel: Bool = false,
             compact: Bool = true, fullSize: Bool = true,
             outer: @escaping @MainActor (AnyView) -> AnyView = { $0 },
             make: @escaping @MainActor () -> AnyView) {
            self.name = name
            self.source = source
            self.size = size
            self.panel = panel
            self.compact = compact
            self.fullSize = fullSize
            self.outer = outer
            self.make = make
        }
    }

    var subjects: [Subject] {
        [
            .init("Document", source: "CatalogDocumentWindow.swift; LumenDocumentWindow.swift", size: CatalogDocumentWindow.defaultSize) {
                AnyView(CatalogDocumentWindow(document: CatalogTextDocument(text: "A sample document.\n")))
            },
            .init("Catalog", source: "LumenCatalogApp.swift; LumenToolbar.swift", size: .init(width: 1280, height: 800), compact: false,
                  outer: { AnyView($0.modifier(CatalogWindowMinimum())) }) {
                AnyView(CatalogView())
            },
            .init("Menu bar panel", source: "CatalogMenuBarPanel.swift; LumenMenuBarPanel.swift", size: .init(width: 280, height: 480), panel: true, fullSize: false) {
                AnyView(CatalogMenuBarPanel())
            },
            .init("Workspace", source: "LumenCatalogApp.swift; LumenWorkspaceWindow.swift", size: .init(width: 1200, height: 800), compact: false,
                  outer: { AnyView($0.frame(minWidth: 1000, minHeight: 660)) }) {
                AnyView(WorkspaceDemo())
            },
            .init("Utility", source: "CatalogUtilityWindow.swift; LumenUtilityWindow.swift", size: CatalogUtilityWindow.defaultSize) {
                AnyView(CatalogUtilityWindow())
            },
            .init("Library", source: "CatalogLibraryWindow.swift; LumenLibraryWindow.swift", size: CatalogLibraryWindow.defaultSize) {
                AnyView(CatalogLibraryWindow())
            },
            .init("Wizard", source: "CatalogWizardWindow.swift; LumenWizard*.swift", size: .init(width: 640, height: 460), fullSize: false) {
                AnyView(CatalogWizardWindow())
            },
            .init("Document welcome", source: "CatalogDocumentWindow.swift; LumenWelcome.swift", size: .init(width: 760, height: 540)) {
                AnyView(CatalogDocumentWelcome())
            },
            .init("Split workspace", source: "LumenCatalogApp.swift; LumenSplitLayout.swift", size: .init(width: 1440, height: 900)) {
                AnyView(SplitWorkspaceDemo())
            },
            .init("Sample workspace", source: "SampleWorkspace.swift; LumenWorkspaceWindow.swift", size: SampleWorkspace.defaultSize) {
                AnyView(SampleWorkspace())
            },
            .init("Welcome", source: "LumenCatalogApp.swift; LumenWelcome.swift", size: .init(width: 760, height: 540)) {
                AnyView(CatalogWelcome())
            },
            .init("Settings", source: "LumenCatalogApp.swift; LumenSettings*.swift", size: .init(width: 980, height: 720)) {
                AnyView(LumenSettingsSidebarView(CatalogSettings.windowCategories, initialSelection: CatalogSettings.initialSelection))
            },
        ]
    }

    func testEveryCatalogWindowAndPresentedSheet() throws {
        try auditSubjects()
    }

    private func auditSubjects() throws {
        _ = NSApplication.shared
        LumenGlyph.register([.catalogPage])
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: .dark),
                                       registry: LumenRegistry(packs: [.core, .code, .chart]))
        var report = [
            "# Catalog headless hosted-root layout audit",
            "",
            "Fresh production scene roots hosted once in real NSWindow/NSPanel instances, dark, scale 1.0, at the sizes below.",
            "The six Lumen scaffold kinds are covered by Workspace, Utility, Menu bar panel, Wizard, Library and Document.",
            "Live-check gaps: native file/alert panels, native sheet presentation, process picker, engine importer, theme seed, theme customize, theme importer and inactive-toolbar desaturation; inactive window title/icon dimming.",
            "Hosts apply Catalog/Workspace outer minimum frames after the palette root, matching production modifier order.",
            "Native host sizing options are disabled to preserve the requested viewport. Scene resizability modifiers are not reproduced; a finding here is a hosted-root finding, not scene-lifecycle proof.",
            "This does not exercise App scene dispatch, document lifecycle or status-item attachment. It does not claim every page/state is visited.",
            "Source routes identify the view composition used for each subject.",
            "",
        ]
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appendingPathComponent(".build/test-artifacts/catalog-layout", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var failures: [String] = []
        for subject in subjects {
            let window = host(subject, store: store)
            defer { window.close() }
            let capture = try LumenRenderedAudit.capture(in: window)
            let rendered = try LumenRenderedAudit.analyze(capture)
            let findings = (LumenLayoutAudit.findings(in: window) + rendered.findings).map {
                LumenConformance.Finding(.layout, "\(subject.name) · \($0.view)", "\($0.rule): \($0.message)")
            }
            append(name: subject.name, source: subject.source, window: window, findings: findings, to: &report)
            let rootDirectory = directory.appendingPathComponent(subject.name.lowercased().replacingOccurrences(of: " ", with: "-"))
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let geometry: [String: Any] = [
                "fullBleedBackgrounds": capture.fullBleedBackgrounds.map {
                    ["frame": String(describing: $0.frame), "red": $0.red, "green": $0.green,
                     "blue": $0.blue, "cornerRadius": $0.cornerRadius] as [String: Any]
                },
                "fullBleedWashes": capture.fullBleedWashes.map {
                    ["frame": String(describing: $0.frame), "start": String(describing: $0.start),
                     "end": String(describing: $0.end), "stops": $0.stops.map { String(describing: $0) } ] as [String: Any]
                },
                "nativeControlChrome": capture.nativeControlChrome.map { String(describing: $0) },
                "nativeMaskPreservingInk": capture.nativeMaskPreservingInk.map { String(describing: $0) },
                "nativeMaskPreservingSources": capture.nativeMaskPreservingSources.map {
                    ["frame": String(describing: $0.frame), "viewClass": $0.viewClass]
                },
                "detectorRegions": rendered.detectorRegions.map {
                    ["frame": String(describing: $0.frame),
                     "characterBoxes": $0.characterBoxes.map { String(describing: $0) },
                     "rows": $0.rows.map { String(describing: $0) }] as [String: Any]
                },
                "compositeOwners": capture.compositeOwners.filter { $0.identity.hasPrefix("lumen-composite:") }.map {
                    ["identity": $0.identity, "frame": String(describing: $0.frame), "clip": String(describing: $0.clip)]
                },
                "lines": rendered.lines.map {
                    ["text": $0.text, "recognizedBox": String(describing: $0.frame),
                     "observationFrame": String(describing: $0.observationFrame), "glyphBand": String(describing: $0.glyphBand)]
                },
            ]
            try JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys])
                .write(to: rootDirectory.appendingPathComponent("geometry.json"))
            report.append("Measured native frames, composite boundaries and Vision line bands: \(rootDirectory.lastPathComponent)/geometry.json.\n")
            failures.append(contentsOf: findings.map { "\(subject.name): \($0.description)" })
            if !findings.isEmpty {
                try retain(rendered, name: subject.name, in: directory, report: &report)
            }
        }

        report.append(contentsOf: [
            "",
            "## Presentations not exercised",
            "",
            "- Theme edit-in-place, rename and trash confirmation require a user-theme/library state not created by this read-only sweep; the menu-driven export presentation is also unvisited.",
            "- Theme import/error notices and document-open error alerts require result/error states not triggered here.",
            "- Catalog share and go-to-line popovers are not hosted by this window-and-sheet sweep.",
            "- Native scene dispatch, scene resizability constraints, DocumentGroup lifecycle and MenuBarExtra attachment are not exercised.",
        ])
        report.append("")
        report.append("Total findings or attempted-presentation coverage gaps: \(failures.count).")
        try (report.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("catalog-layout-audit.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(failures, [], "Total findings: \(failures.count). See .build/test-artifacts/catalog-layout/catalog-layout-audit.md for all roots, findings and retained bitmap crops.")
    }

    /// Crop the sole audited bitmap; never recapture a failing root for its evidence.
    private func retain(_ rendered: LumenRenderedAudit.Result, name: String, in directory: URL,
                        report: inout [String]) throws {
        let rootName = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let rootDirectory = directory.appendingPathComponent(rootName, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        func write(_ image: CGImage, named filename: String) throws {
            let bitmap = NSBitmapImageRep(cgImage: image)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: rootDirectory.appendingPathComponent(filename))
        }
        try write(rendered.image, named: "bitmap.png")
        report.append("Retained sole audited bitmap: \(rootName)/bitmap.png.")
        let scaleX = CGFloat(rendered.image.width) / rendered.frame.width
        let scaleY = CGFloat(rendered.image.height) / rendered.frame.height
        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(rendered.image.width), height: CGFloat(rendered.image.height))
        for (index, pair) in zip(rendered.findings, rendered.findingRects).enumerated() {
            let (finding, frame) = pair
            let context = frame.insetBy(dx: -12, dy: -12).intersection(rendered.frame)
            let pixelFrame = CGRect(x: (context.minX - rendered.frame.minX) * scaleX,
                                    y: (rendered.frame.maxY - context.maxY) * scaleY,
                                    width: context.width * scaleX, height: context.height * scaleY)
                .integral.intersection(imageBounds)
            let filename = String(format: "%02d-%@.png", index + 1, finding.rule)
            let crop = try XCTUnwrap(rendered.image.cropping(to: pixelFrame),
                                     "Missing bitmap crop for \(name): \(finding.rule), frame=\(frame)")
            try write(crop, named: filename)
            report.append("Crop \(rootName)/\(filename): finding frame=\(frame); pixel crop=\(pixelFrame).")
        }
        if rendered.findings.isEmpty {
            report.append("Semantic-only findings have no rendered finding rectangle; the retained bitmap supplies full-root context.")
        }
        report.append("")
    }

    func host(_ subject: Subject, store: LumenThemeStore) -> NSWindow {
        let root = subject.make()
            .lumenPaletteRoot(store: store)
            .lumenDensityRoot(store: store)
            .lumenMetrics(.standard)
            .lumenTextScale(1.0)
            .lumenChromeStyle(.drawn)
        let host = NSHostingView(rootView: subject.outer(AnyView(root)))
        host.sizingOptions = []
        host.sceneBridgingOptions = [.toolbars, .title]
        var style: NSWindow.StyleMask = subject.panel ? [.borderless] : [.titled, .closable, .resizable]
        if subject.fullSize { style.insert(.fullSizeContentView) }
        let frame = CGRect(origin: .zero, size: subject.size)
        let window: NSWindow = subject.panel
            ? LumenHeadlessHost.panel(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
            : LumenHeadlessHost.window(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = subject.name
        window.titleVisibility = subject.fullSize ? .hidden : .visible
        window.titlebarAppearsTransparent = subject.fullSize
        window.toolbarStyle = subject.compact ? .unifiedCompact : .unified
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.setContentSize(subject.size)
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

    private func presentedSheet(of window: NSWindow) -> NSWindow? {
        settle(window)
        guard let sheet = window.sheets.first else { return nil }
        settle(sheet)
        return sheet
    }

    private var lastActionDiagnostic = "No production action attempted."

    /// Same-process semantic actions only; no cross-process AX API or permission changes.
    /// SwiftUI may put visible text in a static-text child while the actionable button itself
    /// has an empty label/title. Match that text and press its nearest actionable ancestor.
    private func press(_ title: String, in root: NSView?) -> Bool {
        guard let root else {
            lastActionDiagnostic = "Missing content view for ‘\(title)’."
            return false
        }
        var seen = Set<ObjectIdentifier>()
        var attempted = Set<ObjectIdentifier>()
        var namedElements: [String] = []
        var pressedName: String?
        let actionRoles: Set<NSAccessibility.Role> = [.button, .checkBox, .radioButton, .popUpButton, .menuButton]

        func names(_ element: any NSAccessibilityProtocol) -> [String] {
            [element.accessibilityLabel(), element.accessibilityTitle(), element.accessibilityValue() as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        func perform(_ object: AnyObject) -> Bool {
            guard attempted.insert(ObjectIdentifier(object)).inserted,
                  let element = object as? any NSAccessibilityProtocol,
                  let role = element.accessibilityRole(), actionRoles.contains(role) else { return false }
            if element.accessibilityPerformPress() {
                pressedName = names(element).first ?? "\(role.rawValue) containing ‘\(title)’"
                return true
            }
            // Native NSButton semantics can omit the optional press implementation. Invoke the
            // existing control action, as a click would, without changing any view properties.
            if let button = object as? NSButton, button.isEnabled {
                button.performClick(nil)
                pressedName = button.title.isEmpty ? "NSButton containing ‘\(title)’" : button.title
                return true
            }
            return false
        }

        func find(_ object: AnyObject, ancestors: [AnyObject]) -> Bool {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return false }
            if let view = object as? NSView, view.isHiddenOrHasHiddenAncestor { return false }
            if let element = object as? any NSAccessibilityProtocol {
                let values = names(element)
                if !values.isEmpty {
                    let role = element.accessibilityRole()?.rawValue ?? "semantic element"
                    namedElements.append("\(role): \(values.joined(separator: " / "))")
                }
                if values.contains(title) {
                    if perform(object) { return true }
                    for ancestor in ancestors.reversed() {
                        if perform(ancestor) { return true }
                    }
                }
                for child in element.accessibilityChildren() ?? [] {
                    if find(child as AnyObject, ancestors: ancestors + [object]) { return true }
                }
            }
            if let view = object as? NSView {
                for child in view.subviews {
                    if find(child, ancestors: ancestors + [object]) { return true }
                }
            }
            return false
        }
        let pressed = find(root, ancestors: [])
        if pressed {
            lastActionDiagnostic = "Requested ‘\(title)’; pressed \(pressedName ?? title)."
        } else {
            let available = Array(Set(namedElements)).sorted().prefix(60).joined(separator: "; ")
            lastActionDiagnostic = "Requested ‘\(title)’; no matching press action succeeded. Available semantics: \(available.isEmpty ? "none" : available)."
        }
        return pressed
    }

    private func append(name: String, source: String, window: NSWindow,
                        findings: [LumenConformance.Finding], to report: inout [String]) {
        report.append("## \(name)")
        report.append("")
        report.append("Source route: \(source). Frame: \(window.frame.size); content layout: \(window.contentLayoutRect). Findings: \(findings.count).")
        report.append("")
        if findings.isEmpty { report.append("- No findings from the live-window audit.") }
        else { report.append(contentsOf: findings.map { "- \($0.description)" }) }
        report.append("")
    }
}
