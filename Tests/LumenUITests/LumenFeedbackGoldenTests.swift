import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
import LumenTokens
@testable import LumenUI

/// Feedback and shortcut subjects. Recording deliberately reports review-required failures;
/// do not repeat unchanged checks merely to turn the recording run green.
@MainActor final class LumenFeedbackGoldenTests: XCTestCase {
    private let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens")
    private var variants: [LumenSnapshot.Variant] { LumenSnapshot.Variant.all(for: LumenRegistry.core.galleryThemes) }

    private func includes(_ variant: LumenSnapshot.Variant) -> Bool {
        guard let selection = ProcessInfo.processInfo.environment["LUMEN_GOLDEN_THEME"], !selection.isEmpty else { return true }
        if selection == "non-contrast" { return variant.themeID != LumenThemes.contrastID }
        return variant.themeID == selection || variant.label == selection
            || variant.themeID.split(separator: ".").last.map(String.init) == selection
    }

    func testToastInfo() { checkToast(.info, name: "feedback-toast-info") }
    func testToastSuccess() { checkToast(.success, name: "feedback-toast-success") }
    func testToastWarning() { checkToast(.warning, name: "feedback-toast-warning") }
    func testToastDanger() { checkToast(.danger, name: "feedback-toast-danger") }
    func testToastCollapse() { check(stack, name: "feedback-toast-collapse", size: CGSize(width: 420, height: 440)) }
    func testShortcutsSheet() { check(sheet, name: "feedback-shortcuts", size: CGSize(width: 680, height: 440)) }
    func testToastGlass() {
        check(stack.lumenChromeStyle(.glass), name: "feedback-toast-glass", size: CGSize(width: 420, height: 440), glass: true)
    }
    func testShortcutsGlass() {
        check(sheet.lumenChromeStyle(.glass), name: "feedback-shortcuts-glass", size: CGSize(width: 680, height: 440), glass: true)
    }

    private var sheet: some View {
        LumenShortcutsSheet(groups: LumenViewCommands().shortcutGroups + LumenShortcutsCommands.shortcutGroups)
    }

    private var stack: some View {
        let center = LumenToastCenter(now: { 0 }, schedulesTimers: false)
        for (index, tone) in LumenTone.allCases.enumerated() {
            center.post(LumenToast(title: ["Analysis started", "Export complete", "Source changed on disk", "Connection interrupted"][index],
                                   message: ["Results are arriving.", "Your report is ready.", "Review before continuing.", "Your local changes are safe."][index],
                                   tone: tone, action: tone == .danger ? .init("Retry", perform: {}) : nil, duration: nil))
        }
        return LumenToastStack(center: center).padding(24)
    }

    private func checkToast(_ tone: LumenTone, name: String) {
        let center = LumenToastCenter(now: { 0 }, schedulesTimers: false)
        center.post(LumenToast(title: "A notification title that wraps without losing its meaning", message: "The complete message remains readable.",
                               tone: tone, action: .init("Review", perform: {}), duration: nil))
        check(LumenToastStack(center: center).padding(24), name: name, size: CGSize(width: 420, height: 240))
    }

    private func check<V: View>(_ view: V, name: String, size: CGSize, glass: Bool = false) {
        if glass {
            do { try checkGlass(view, name: name, size: size) }
            catch { XCTFail("\(name): \(error)") }
            return
        }
        let selected = variants.filter(includes)
        guard !selected.isEmpty else { XCTFail("Unknown feedback golden theme selection"); return }
        for variant in selected {
            // Grow the canvas with theme type scale without changing unscaled captures.
            let scale = LumenRegistry.core.theme(id: variant.themeID)?.metrics?.typeScale ?? 1
            let captureSize = CGSize(width: size.width, height: ceil(size.height * max(1, scale)))
            let outcome = LumenSnapshot.verify(view, named: name, size: captureSize, variant: variant,
                                               registry: .core, goldenDirectory: directory,
                                               renderer: .image)
            if let message = outcome.failureMessage { XCTFail("\(name)@\(variant.label): \(message)") }
        }
    }

    /// Compare offscreen material rendering with the existing golden; differences remain failures.
    private func checkGlass<V: View>(_ view: V, name: String, size: CGSize) throws {
        let store = LumenSnapshot.store(for: .init(themeID: LumenThemes.standardID, colorScheme: .dark), registry: .core)
        let root = view.frame(width: size.width, height: size.height)
            .background(store.resolvedPalette()[.bgCanvas])
            .lumenPaletteRoot(store: store).lumenMetrics(.standard)
            .environment(\.colorScheme, .dark).environment(\.displayScale, 2)
            .environment(\.appearsActive, true)
            .environment(\.controlActiveState, LumenHeadlessHost.snapshotControlActiveState)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.setContentSize(size)
        LumenHeadlessHost.prepare(window)
        LumenHeadlessHost.order(window)
        defer { window.close() }
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        let captureDirectory = ProcessInfo.processInfo.environment["LUMEN_CAPTURE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? directory.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: ".build/feedback-captures")
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        let captured = captureDirectory.appending(path: "\(name).png")
        try LumenHeadlessHost.png(of: window).write(to: captured)
        let actual = try Data(contentsOf: captured)
        let golden = directory.appending(path: "\(name)@standard-dark.png")
        try LumenFilterConfinedGolden.verify(actual, at: golden)
    }

}
