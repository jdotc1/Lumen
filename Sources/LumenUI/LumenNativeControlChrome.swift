#if DEBUG
import AppKit

/// AppKit owns the bezel and focus mask of a native field, but never its text.
/// Plain fields inside Lumen-drawn wells deliberately contribute no bezel frame.
@MainActor
enum LumenNativeControlChrome {
    /// Search/cancel glyphs are native buttons, not user-entered text. Their cell-provided
    /// rectangles participate in the ordinary native chrome OCR exclusion path.
    static func searchButtonFrames(in window: NSWindow) -> [CGRect] {
        var result: [CGRect] = []
        func visit(_ view: NSView) {
            guard !view.isHiddenOrHasHiddenAncestor, view.alphaValue > 0 else { return }
            if let field = view as? NSSearchField, let cell = field.cell as? NSSearchFieldCell {
                var local: [CGRect] = []
                if cell.searchButtonCell != nil { local.append(cell.searchButtonRect(forBounds: field.bounds)) }
                if cell.cancelButtonCell != nil, !field.stringValue.isEmpty {
                    local.append(cell.cancelButtonRect(forBounds: field.bounds))
                }
                result += local.filter { !$0.isEmpty }.map { window.convertToScreen(field.convert($0, to: nil)) }
            }
            for child in view.subviews { visit(child) }
        }
        if let root = window.contentView { visit(root) }
        return result
    }

    static func fields(in window: NSWindow) -> [NSTextField] {
        var fields: [NSTextField] = []
        func visit(_ view: NSView) {
            guard !view.isHiddenOrHasHiddenAncestor, view.alphaValue > 0 else { return }
            if let field = view as? NSTextField, field.isBezeled || field.isBordered { fields.append(field) }
            for child in view.subviews { visit(child) }
        }
        if let root = window.contentView { visit(root) }
        return fields
    }

    static func frames(in window: NSWindow) -> [CGRect] {
        var result: [CGRect] = []
        func visit(_ view: NSView) {
            guard !view.isHiddenOrHasHiddenAncestor, view.alphaValue > 0 else { return }
            if let field = view as? NSTextField {
                var local: [CGRect] = []
                if field.isBezeled || field.isBordered {
                    local.append(field.bounds)
                    // Native search accessories can extend beyond the field's nominal bounds.
                    // Keep each actual visible native subview, never their enclosing union.
                    func nativeParts(_ view: NSView) {
                        for child in view.subviews where !child.isHiddenOrHasHiddenAncestor && child.alphaValue > 0 {
                            guard Bundle(for: type(of: child)).bundleIdentifier?.hasPrefix("com.apple.") == true else { continue }
                            result.append(window.convertToScreen(child.convert(child.bounds, to: nil)))
                            nativeParts(child)
                        }
                    }
                    nativeParts(field)
                }
                let editor = field.currentEditor()
                let focused = window.firstResponder === field || (editor != nil && window.firstResponder === editor)
                if focused, field.focusRingType != .none {
                    let mask = field.focusRingMaskBounds
                    if !mask.isEmpty { local.append(mask) }
                    if let cell = field.cell {
                        let cellMask = cell.focusRingMaskBounds(forFrame: field.bounds, in: field)
                        if !cellMask.isEmpty { local.append(cellMask) }
                    }
                }
                for rect in local {
                    let measured = window.convertToScreen(field.convert(rect, to: nil))
                    if !result.contains(measured) { result.append(measured) }
                }
            }
            for child in view.subviews { visit(child) }
        }
        if let root = window.contentView { visit(root) }
        return result
    }
}
#endif
