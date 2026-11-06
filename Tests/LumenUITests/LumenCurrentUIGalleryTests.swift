import AppKit
import SwiftUI
import XCTest
import LumenTokens
import LumenTestSupport
@testable import LumenUI
@testable import LumenCatalog

/// Review artifacts only: no golden comparisons, product mutations or onscreen presentation.
/// Run this test alone, after building, with LUMEN_GALLERY_OUT set to an empty destination.
@MainActor
final class LumenCurrentUIGalleryTests: XCTestCase {
    private struct Entry: Encodable {
        let file: String
        let window: String
        let pane: String
        let appearance: String
        let chrome: String
        var width = 0
        var height = 0
        var missing: String?
        var note: String?
    }
    private var entries: [Entry] = []
    private var destination = URL(fileURLWithPath: ".")

    func testCurrentUIGallery() throws {
        guard let output = ProcessInfo.processInfo.environment["LUMEN_GALLERY_OUT"], !output.isEmpty else {
            throw XCTSkip("Set LUMEN_GALLERY_OUT to capture the review gallery")
        }
        destination = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: destination.appending(path: "index.json").path) else {
            throw XCTSkip("Existing gallery preserved; do not rerun unchanged inputs")
        }
        _ = NSApplication.shared
        NSApp.finishLaunching()
        LumenGlyph.register([.catalogPage])
        let keys = ["LUMEN_CATALOG_PAGE", "LUMEN_CATALOG_SCROLL", "LUMEN_CATALOG_WELCOME",
                    "LUMEN_CATALOG_WORKSPACE", "LUMEN_CATALOG_SPLIT", "LUMEN_CATALOG_PALETTE",
                    "LUMEN_CATALOG_COMMANDS", "LUMEN_CATALOG_POPOVER", "LUMEN_STRESS"]
        let saved = keys.map { ($0, ProcessInfo.processInfo.environment[$0]) }
        for key in keys { unsetenv(key) }
        defer {
            for (key, value) in saved {
                if let value { setenv(key, value, 1) } else { unsetenv(key) }
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            for chrome in [LumenChromeStyle.drawn, .glass] {
                let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: scheme),
                                               registry: LumenRegistry(packs: [.core, .code, .chart]))
                try LumenThemeStore.withActiveStore(store) {
                    try MainActor.assumeIsolated {
                        try matrix(store: store, scheme: scheme, chrome: chrome)
                    }
                }
            }
        }
        print("GALLERY COMPLETE: \(entries.filter { $0.missing == nil }.count) PNGs; \(entries.filter { $0.missing != nil }.count) missing entries")
    }

    private func matrix(store: LumenThemeStore, scheme: ColorScheme, chrome: LumenChromeStyle) throws {
        func shot<V: View>(_ window: String, _ pane: String, _ width: CGFloat, _ height: CGFloat,
                           borderless: Bool = false, crop: Bool = false, note: String? = nil,
                           @ViewBuilder content: () -> V) throws {
            try capture(window, pane, size: CGSize(width: width, height: height), store: store,
                        scheme: scheme, chrome: chrome, borderless: borderless, crop: crop,
                        note: note, content: content())
        }
        for page in CatalogPage.allCases {
            setenv("LUMEN_CATALOG_PAGE", page.rawValue, 1)
            try shot("catalog", String(describing: page), 1440, 960) { CatalogView() }
        }
        setenv("LUMEN_CATALOG_PAGE", "workspace", 1)
        try shot("catalog", "narrowest", CatalogLayout.windowMinWidth, 760) { CatalogView() }
        try shot("workspace", "bottom-panel", 1440, 900) { WorkspaceDemo() }
        try shot("workspace", "narrowest", 1000, 660) { WorkspaceDemo() }
        for category in CatalogSettings.categories {
            try shot("settings", category.id, LumenSettingsSidebarView.windowIdealWidth, 760) {
                LumenSettingsSidebarView(CatalogSettings.categories, initialSelection: category.id)
                    .environment(\.lumenSettingsSizesWindow, false)
            }
        }
        try shot("settings", "general-tab-content", 620, 460, note: "General is an additional pane in the tabbed Settings example.") { GeneralSettings() }
        try shot("welcome", "main", 760, 460) { CatalogWelcome() }
        try shot("document", "main", 1120, 680) { CatalogDocumentWindow(document: CatalogTextDocument()) }
        try shot("document", "welcome", 760, 460) { CatalogDocumentWelcome() }
        try shot("library", "main", 1200, 720) { CatalogLibraryWindow() }
        try shot("utility", "main", 1120, 680) { CatalogUtilityWindow() }
        for (index, page) in CatalogWizardWindow.pages.enumerated() {
            try shot("wizard", page.id, 640, 460) { CatalogWizardWindow(current: index) }
        }
        try shot("menu-bar", "panel", LumenLayout.popoverWidth, LumenLayout.panelMaxHeight, borderless: true,
                 note: "Real panel content in a guarded offscreen host; menu-bar attachment is not presented.") { CatalogMenuBarPanel() }
        try shot("theme", "editor", 1000, 760) { LumenThemeEditor(base: store.theme(), store: store) }
        try shot("theme", "gallery", 1000, 900) { LumenThemeGallery(store: store) }
        try shot("theme", "seed-sheet-content", 560, 600, borderless: true,
                 note: "Actual sheet content; native sheet attachment is not presented.") { LumenThemeSeedSheet(store: store) }
        try shot("shortcuts", "sheet-content", 640, 560, borderless: true,
                 note: "Actual sheet content; native sheet attachment is not presented.") {
            LumenShortcutsSheet(groups: CatalogShortcutDefinitions.groups)
        }
        try shot("command", "palette", 680, 600, borderless: true,
                 note: "Actual palette content with Catalog commands; no popup attachment.") {
            LumenCommandPalette(CatalogView().paletteCommands, scopes: CatalogPalette.scopes,
                                query: "", recentsKey: nil)
        }
        try shot("command", "menu", 360, 600, borderless: true) { LumenCommandMenu(MenusPage.entries) }
        let center = LumenToastCenter(now: { 0 }, schedulesTimers: false)
        center.post(LumenToast(title: "Build succeeded", message: "The project is ready.", tone: .success))
        center.post(LumenToast(title: "Indexing complete", message: "All symbols are available.", tone: .info))
        center.post(LumenToast(title: "Review needed", message: "Two items need attention.", tone: .warning))
        try shot("toast", "stack", 400, 420, borderless: true,
                 note: "Real toast stack with test notices; timers disabled to preserve the review state.") { LumenToastStack(center: center).padding(20) }
        for compact in [false, true] {
            try shot("crop", compact ? "identity-compact" : "identity-regular", 380, 90, crop: true,
                     note: "Native-resolution content crop of the real identity component; compact environment matches the toolbar.") {
                LumenToolbarIdentity("Lumen Catalog", subtitle: "Catalog", systemImage: "lumen.lens", hue: .hueViolet)
                    .environment(\.lumenToolbarCompact, compact)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(12)
            }
        }
        try shot("crop", "chips-pills-segmented", 640, 170, crop: true,
                 note: "Native-resolution content crop of real controls with Catalog sample values.") {
            VStack(alignment: .leading, spacing: 16) {
                LumenFilterChips(selection: .constant("All"), options: ["All", "Favorites", "Recent"], title: { $0 })
                HStack {
                    LumenPill(label: "version", value: "2.4.1")
                    LumenPill(label: "items", value: "1,284", style: .metric)
                    LumenTag("pinned", token: .accent)
                    LumenTag("review", token: .hueOrange)
                }
                LumenSegmentedControl(selection: .constant("Regular"), options: ["Compact", "Regular"], title: { $0 })
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        for (window, pane, reason) in [
            ("about", "panel", "AppKit standard About panel only exposes orderFrontStandardAboutPanel; visible presentation is prohibited."),
            ("sheet", "attached", "Catalog sheet presentation state is private; detached content is not an attached native sheet. No product hooks or presentation calls added."),
            ("popover", "attached", "Catalog native popover requires presentation from its anchor; no guarded offscreen presentation seam exists. No substitute image generated.")
        ] {
            var entry = entry(window, pane, scheme, chrome)
            entry.missing = reason
            entries.append(entry)
            try saveIndex()
        }
    }

    private func entry(_ window: String, _ pane: String, _ scheme: ColorScheme, _ chrome: LumenChromeStyle) -> Entry {
        let appearance = scheme == .dark ? "dark" : "light"
        return Entry(file: "\(window)-\(pane)-\(appearance)-\(chrome.rawValue).png", window: window,
                     pane: pane, appearance: appearance, chrome: chrome.rawValue)
    }

    private func saveIndex() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: destination.appending(path: "index.json"), options: .atomic)
    }

    private func capture<V: View>(_ name: String, _ pane: String, size: CGSize, store: LumenThemeStore,
                                 scheme: ColorScheme, chrome: LumenChromeStyle, borderless: Bool,
                                 crop: Bool, note: String?, content: V) throws {
        var record = entry(name, pane, scheme, chrome)
        record.note = note
        print("GALLERY BEGIN: \(record.file)")
        let root = content.lumenPaletteRoot(store: store).lumenDensityRoot(store: store)
            .lumenMetrics(.standard).lumenChromeStyle(chrome)
            .environment(\.colorScheme, scheme).environment(\.displayScale, 2)
            .environment(\.controlActiveState, LumenHeadlessHost.snapshotControlActiveState)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.sceneBridgingOptions = [.toolbars, .title]
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size),
            styleMask: borderless ? [.borderless] : [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        defer { window.close() }
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.title = name.capitalized
        window.toolbarStyle = .unified
        if name == "welcome" || (name == "document" && pane == "welcome") { window.titleVisibility = .hidden }
        window.contentView = host
        window.setContentSize(size)
        LumenHeadlessHost.order(window)
        for _ in 0..<20 {
            (host.superview ?? host).layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        do {
            let png = try LumenHeadlessHost.png(of: window)
            guard let capture = LumenHeadlessHost.lastCapture, abs(capture.backingScale - 2) < 0.001 else {
                record.missing = "Offscreen host did not supply native 2x backing; no upscaled substitute saved."
                entries.append(record)
                try saveIndex()
                return
            }
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
            var image = try XCTUnwrap(bitmap.cgImage)
            if crop, let frame = host.superview {
                let rect = host.convert(host.bounds, to: frame)
                let y = frame.isFlipped ? rect.minY : frame.bounds.maxY - rect.maxY
                image = try XCTUnwrap(image.cropping(to: CGRect(x: rect.minX * 2, y: y * 2,
                                                               width: rect.width * 2, height: rect.height * 2)))
            }
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: destination.appending(path: record.file), options: .atomic)
            record.width = image.width
            record.height = image.height
            print("GALLERY SAVED: \(record.file) \(image.width)x\(image.height)")
        } catch {
            record.missing = "Guarded bitmap capture failed (\(String(describing: type(of: error)))); no substitute saved."
            print("GALLERY MISSING: \(record.file)")
        }
        entries.append(record)
        try saveIndex()
    }
}
