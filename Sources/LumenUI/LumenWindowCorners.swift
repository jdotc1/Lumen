import AppKit
import SwiftUI

/// Window geometry, separate from the component radius ramp.
public enum LumenRadius {
    /// The approximately 16 pt continuous window radius measured on macOS 27.2.
    /// Live surfaces use system concentric geometry; see Docs/reference/window-corners.md.
    public static var window: CGFloat { 16 }
}

extension View {
    /// The system container supplies the corners; an unrounded container stays rectangular.
    func lumenWindowCornerClip() -> some View {
        compositingGroup().clipShape(ConcentricRectangle())
    }
}

/// A code editor's text view that clips to its container-relative corners.
/// Install this subclass alongside `LumenLineNumberRuler`; client-owned text views cannot
/// have their read-only `cornerConfiguration` assigned after construction.
open class LumenConcentricTextView: NSTextView {
    open override var cornerConfiguration: NSViewCornerConfiguration? {
        .corners(radius: .containerConcentric)
    }

    open override func viewDidChangeEffectiveCornerRadii() {
        super.viewDidChangeEffectiveCornerRadii()
        applyLumenCornerMask()
    }

    open override func layout() {
        super.layout()
        applyLumenCornerMask()
    }
}

/// AppKit-hosted navigation glass; content surfaces remain opaque (Docs/GLASS.md).
open class LumenConcentricGlassView: NSGlassEffectView {
    open override var cornerConfiguration: NSViewCornerConfiguration? {
        .corners(radius: .containerConcentric)
    }

    open override func viewDidChangeEffectiveCornerRadii() {
        super.viewDidChangeEffectiveCornerRadii()
        applyLumenCornerMask()
    }

    open override func layout() {
        super.layout()
        applyLumenCornerMask()
    }
}

private extension NSView {
    func applyLumenCornerMask() {
        guard let radii = effectiveCornerRadii else { return }
        wantsLayer = true
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: isFlipped ? radii.topLeft : radii.bottomLeft,
            bottomLeadingRadius: isFlipped ? radii.bottomLeft : radii.topLeft,
            bottomTrailingRadius: isFlipped ? radii.bottomRight : radii.topRight,
            topTrailingRadius: isFlipped ? radii.topRight : radii.bottomRight)
        let mask = (layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bounds
        mask.path = shape.path(in: CGRect(origin: .zero, size: bounds.size)).cgPath
        layer?.mask = mask
        CATransaction.commit()
    }
}
