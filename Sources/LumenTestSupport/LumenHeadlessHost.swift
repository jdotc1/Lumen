import AppKit
import LumenHeadlessCore
import SwiftUI

/// Shared hosting for tests and conformance checks. It never activates or fronts a window.
/// The embedding app owns its activation policy; only the test-only process guard prohibits it.
@MainActor
package enum LumenHeadlessHost {
    /// Whole-window goldens were recorded with inactive controls. Keep this independent of
    /// process focus; no capture is permitted to activate a window to establish appearance.
    package static let snapshotControlActiveState = ControlActiveState.inactive

    package static func window(contentRect: NSRect, styleMask: NSWindow.StyleMask,
                               backing: NSWindow.BackingStoreType, defer flag: Bool) -> NSWindow {
        let window = HeadlessWindow(contentRect: offscreen(contentRect), styleMask: styleMask,
                                    backing: backing, defer: flag)
        prepare(window)
        return window
    }

    package static func panel(contentRect: NSRect, styleMask: NSWindow.StyleMask,
                              backing: NSWindow.BackingStoreType, defer flag: Bool) -> NSPanel {
        let panel = HeadlessPanel(contentRect: offscreen(contentRect), styleMask: styleMask,
                                  backing: backing, defer: flag)
        prepare(panel)
        return panel
    }

    package static func window() -> NSWindow {
        window(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    }

    package static func window(contentViewController controller: NSViewController) -> NSWindow {
        let window = window(contentRect: controller.view.frame, styleMask: [.titled, .closable, .resizable],
                            backing: .buffered, defer: false)
        window.contentViewController = controller
        prepare(window)
        return window
    }

    package static func prepare(_ window: NSWindow) {
        LumenHeadlessPrepareWindow(window)
    }

    /// Some SwiftUI native layout bridges require membership in the ordered window list.
    /// Ordering behind does not make zero-alpha, offscreen windows visually present.
    package static func order(_ window: NSWindow) {
        prepare(window)
        window.orderBack(nil)
        precondition(!NSApp.isActive && !window.isKeyWindow && !window.isMainWindow)
        precondition(window.alphaValue == 0 && !NSScreen.screens.contains { $0.frame.intersects(window.frame) })
    }

    /// Sole whole-window capture route: cacheDisplay, native measured corner mask, inactive controls.
    package static func png(of window: NSWindow) throws -> Data {
        prepare(window)
        guard let view = window.contentView?.superview ?? window.contentView else {
            throw CaptureError.missingView
        }
        view.layoutSubtreeIfNeeded()
        prepare(window)
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CaptureError.missingBitmap
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        prepare(window)
        let regions = filteredRegions(in: view, bitmap: bitmap)
        try applyWindowCorners(window, frameView: view, bitmap: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.missingPNG
        }
        lastCapture = Capture(png: png, filteredLayers: regions, backingScale: CGFloat(bitmap.pixelsWide) / view.bounds.width)
        return png
    }

    package struct FilteredLayer: Codable {
        package let layerClass: String
        package let localFrame: CGRect
        package let frameInRoot: CGRect
        /// Top-left-origin bitmap coordinates, expanded by exactly two pixels.
        package let pixelFrame: CGRect
    }
    package struct Capture {
        package let png: Data
        package let filteredLayers: [FilteredLayer]
        package let backingScale: CGFloat
    }
    package private(set) static var lastCapture: Capture?

    /// Only explicit CA filters entries qualify, never opacity or compositingFilter alone.
    private static func filteredRegions(in view: NSView, bitmap: NSBitmapImageRep) -> [FilteredLayer] {
        guard let root = view.layer else { return [] }
        let sx = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let sy = CGFloat(bitmap.pixelsHigh) / view.bounds.height
        var result: [FilteredLayer] = []
        func visit(_ layer: CALayer) {
            if !(layer.filters ?? []).isEmpty {
                let frame = layer.convert(layer.bounds, to: root)
                let y = view.isFlipped ? frame.minY - view.bounds.minY : view.bounds.maxY - frame.maxY
                let pixels = CGRect(x: (frame.minX - view.bounds.minX) * sx, y: y * sy,
                                    width: frame.width * sx, height: frame.height * sy)
                    .insetBy(dx: -2, dy: -2)
                result.append(.init(layerClass: String(describing: type(of: layer)),
                                    localFrame: layer.frame, frameInRoot: frame, pixelFrame: pixels))
                print("HEADLESS FILTER: local=\(layer.frame) root=\(frame) pixelsPlus2=\(pixels) viewFlipped=\(view.isFlipped) rootFlipped=\(root.isGeometryFlipped)")
            }
            for child in layer.sublayers ?? [] { visit(child) }
        }
        visit(root)
        return result
    }

    /// Frame-view caching bypasses the compositor mask. Read the native container's resolved
    /// radii for this window/style and remove only the pixels outside its continuous corners.
    private static func applyWindowCorners(_ window: NSWindow, frameView: NSView,
                                           bitmap: NSBitmapImageRep) throws {
        let radii = frameView.effectiveCornerRadii ?? window.contentView?.effectiveCornerRadii
        print("HEADLESS CAPTURE: style=\(window.styleMask.rawValue) frameRadii=\(String(describing: frameView.effectiveCornerRadii)) contentRadii=\(String(describing: window.contentView?.effectiveCornerRadii)) controls=inactive")
        guard let radii else {
            // Borderless windows have no native window mask.
            if window.styleMask.contains(.titled) { throw CaptureError.missingCornerRadii }
            return
        }
        guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CaptureError.missingBitmap
        }
        let context = graphics.cgContext
        context.saveGState()
        defer { context.restoreGState() }
        context.concatenate(context.ctm.inverted())
        context.scaleBy(x: CGFloat(bitmap.pixelsWide) / frameView.bounds.width,
                        y: CGFloat(bitmap.pixelsHigh) / frameView.bounds.height)
        let bounds = CGRect(origin: .zero, size: frameView.bounds.size)
        let shape = UnevenRoundedRectangle(topLeadingRadius: radii.bottomLeft,
                                           bottomLeadingRadius: radii.topLeft,
                                           bottomTrailingRadius: radii.topRight,
                                           topTrailingRadius: radii.bottomRight,
                                           style: .continuous)
        context.addRect(bounds)
        context.addPath(shape.path(in: bounds).cgPath)
        context.setBlendMode(.clear)
        context.drawPath(using: .eoFill)
    }

    fileprivate static func offscreen(_ rect: NSRect) -> NSRect {
        LumenHeadlessOffscreenRect(rect)
    }

    private enum CaptureError: Error { case missingView, missingBitmap, missingPNG, missingCornerRadii }
}

@MainActor
private final class HeadlessWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
    override func update() {
        super.update()
        LumenHeadlessHost.prepare(self)
    }
    override func setContentSize(_ size: NSSize) {
        super.setContentSize(size)
        LumenHeadlessHost.prepare(self)
    }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(LumenHeadlessHost.offscreen(frameRect), display: flag)
        LumenHeadlessHost.prepare(self)
    }
}

@MainActor
private final class HeadlessPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
    override func update() {
        super.update()
        LumenHeadlessHost.prepare(self)
    }
    override func setContentSize(_ size: NSSize) {
        super.setContentSize(size)
        LumenHeadlessHost.prepare(self)
    }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(LumenHeadlessHost.offscreen(frameRect), display: flag)
        LumenHeadlessHost.prepare(self)
    }
}
