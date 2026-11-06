import AppKit
import SwiftUI

/// Exact filled regions, in view coordinates, for owned-ink checks without a second capture.
@MainActor
protocol LumenOwnedInkSource: AnyObject {
    var ownedInkRects: [CGRect] { get }
}

/// The unified bar's separator is window geometry, independent of SwiftUI minimum-size overflow.
/// The transparent layout row remains in place so visible-toolbar content keeps its exact layout.
struct LumenMeasuredChromeSeparator: NSViewRepresentable {
    let color: NSColor
    let thickness: CGFloat

    func makeNSView(context: Context) -> Separator { Separator() }
    func updateNSView(_ view: Separator, context: Context) {
        view.color = color
        view.thickness = thickness
        view.needsDisplay = true
    }
    static func dismantleNSView(_ view: Separator, coordinator: ()) { view.detach() }

    final class Separator: NSView, LumenOwnedInkSource {
        var color = NSColor.separatorColor
        var thickness: CGFloat = 1
        private var geometryObservation: NSKeyValueObservation?
        private var toolbarObservation: NSKeyValueObservation?
        private var visibilityObservation: NSKeyValueObservation?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            geometryObservation = window.observe(\.contentLayoutRect, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.needsDisplay = true }
            }
            toolbarObservation = window.observe(\.toolbar, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.observeToolbar() }
            }
            observeToolbar()
        }
        private func observeToolbar() {
            visibilityObservation = window?.toolbar?.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.needsDisplay = true }
            }
            needsDisplay = true
        }
        func detach() {
            geometryObservation = nil
            toolbarObservation = nil
            visibilityObservation = nil
        }
        override func layout() { super.layout(); needsDisplay = true }

        var ownedInkRects: [CGRect] {
            guard let window, window.toolbar?.isVisible == true else { return [] }
            let layout = window.contentLayoutRect
            let line = CGRect(x: layout.minX, y: layout.maxY - thickness,
                              width: layout.width, height: thickness)
            let padding = 2 / max(1, window.backingScaleFactor)
            // Never paint through native buttons, even during a transient native relayout.
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window.standardWindowButton(kind), !button.isHiddenOrHasHiddenAncestor,
                   button.convert(button.bounds, to: nil).insetBy(dx: -padding, dy: -padding).intersects(line) { return [] }
            }
            let clipped = convert(line, from: nil).intersection(bounds)
            return clipped.isNull || clipped.isEmpty ? [] : [clipped]
        }
        override func draw(_ dirtyRect: NSRect) {
            color.setFill()
            for rect in ownedInkRects { rect.fill() }
        }
    }
}
