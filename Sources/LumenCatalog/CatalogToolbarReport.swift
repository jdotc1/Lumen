import AppKit
import SwiftUI

/// Optional live geometry measurements for the preview. This measures the actual SDK-stamped app;
/// an NSHostingView in an XCTest process can use a different native toolbar design.
struct CatalogToolbarReport: NSViewRepresentable {
    func makeNSView(context: Context) -> ReportView { ReportView() }
    func updateNSView(_ view: ReportView, context: Context) {}

    final class ReportView: NSView {
        private var report: Task<Void, Never>?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report?.cancel()
            guard let window,
                  let path = ProcessInfo.processInfo.environment["LUMEN_CATALOG_TOOLBAR_REPORT"] else { return }
            report = Task { @MainActor [weak window] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let window else { return }
                Self.write(window, to: path)
            }
        }

        private static func write(_ window: NSWindow, to path: String) {
            var lines = ["window=\(window.windowNumber) frame=\(window.frame) mouse=\(window.mouseLocationOutsideOfEventStream)"]
            let visible = Set(window.toolbar?.visibleItems?.map(\.itemIdentifier) ?? [])
            for item in window.toolbar?.items ?? [] {
                let frame = item.view.map { $0.convert($0.bounds, to: nil) } ?? .zero
                lines.append("item=\(item.itemIdentifier.rawValue) visible=\(visible.contains(item.itemIdentifier)) frame=\(frame) fitting=\(item.view?.fittingSize ?? .zero)")
            }
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window.standardWindowButton(type) {
                    lines.append("windowButton=\(type.rawValue) hidden=\(button.isHiddenOrHasHiddenAncestor) frame=\(button.convert(button.bounds, to: nil))")
                }
            }
            func collect(_ view: NSView, depth: Int) {
                let frame = view.convert(view.bounds, to: nil)
                guard frame.maxY >= window.frame.height - 65 else { return }
                let button = view as? NSButton
                lines.append("\(String(repeating: " ", count: depth))\(type(of: view)) frame=\(frame) hidden=\(view.isHidden) title=\(button?.title ?? "") tooltip=\(view.toolTip ?? "")")
                view.subviews.forEach { collect($0, depth: depth + 1) }
            }
            if let frameView = window.contentView?.superview { collect(frameView, depth: 0) }
            do { try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8) }
            catch { NSLog("Catalog toolbar report: %@", String(describing: error)) }
        }
    }
}
