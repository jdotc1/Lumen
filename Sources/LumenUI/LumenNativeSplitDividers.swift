#if DEBUG
import AppKit

/// Native split chrome uses the same measured exclusion path as native toolbar items.
/// Only an actual separator view or a positive gap reserved by AppKit is owned.
/// Overlay inspectors can overlap the main pane; that overlap is never chrome.
@MainActor
enum LumenNativeSplitDividers {
    static func frames(in window: NSWindow) -> [CGRect] {
        var result: [CGRect] = []
        func visit(_ view: NSView) {
            guard !view.isHiddenOrHasHiddenAncestor, view.alphaValue > 0 else { return }
            if let split = view as? NSSplitView, split.dividerThickness > 0 {
                let panes = split.arrangedSubviews.filter {
                    !$0.isHiddenOrHasHiddenAncestor && !split.isSubviewCollapsed($0)
                }.sorted {
                    split.isVertical ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY
                }
                var localFrames: [CGRect] = []
                // Overlay split items need not leave a gap: AppKit supplies a separate
                // separator subview. Identify its measured geometry and ownership without
                // depending on a private AppKit class name or treating the shadow as ink.
                for chrome in split.subviews where !split.arrangedSubviews.contains(where: { $0 === chrome }) {
                    guard !chrome.isHiddenOrHasHiddenAncestor, chrome.alphaValue > 0,
                          Bundle(for: type(of: chrome)).bundleIdentifier?.hasPrefix("com.apple.") == true else { continue }
                    let rect = chrome.convert(chrome.bounds, to: split)
                    let thickness = split.isVertical ? rect.size.width : rect.size.height
                    let fillsAxis = split.isVertical
                        ? rect.minY == split.bounds.minY && rect.maxY == split.bounds.maxY
                        : rect.minX == split.bounds.minX && rect.maxX == split.bounds.maxX
                    let atPaneBoundary = panes.contains { pane in
                        split.isVertical
                            ? rect.minX == pane.frame.minX || rect.maxX == pane.frame.maxX
                            : rect.minY == pane.frame.minY || rect.maxY == pane.frame.maxY
                    }
                    guard thickness > 0, thickness <= split.dividerThickness,
                          fillsAxis, atPaneBoundary else { continue }
                    localFrames.append(rect)
                }
                for (first, second) in zip(panes, panes.dropFirst()) {
                    let gap: CGRect
                    if split.isVertical {
                        let width = second.frame.minX - first.frame.maxX
                        guard width > 0 else { continue }
                        gap = CGRect(x: first.frame.maxX, y: split.bounds.minY,
                                     width: min(split.dividerThickness, width),
                                     height: split.bounds.height)
                    } else {
                        let height = second.frame.minY - first.frame.maxY
                        guard height > 0 else { continue }
                        gap = CGRect(x: split.bounds.minX, y: first.frame.maxY,
                                     width: split.bounds.width,
                                     height: min(split.dividerThickness, height))
                    }
                    guard !localFrames.contains(where: { $0.intersects(gap) }) else { continue }
                    localFrames.append(gap)
                }
                result += localFrames.map { window.convertToScreen(split.convert($0, to: nil)) }
            }
            for child in view.subviews { visit(child) }
        }
        if let root = window.contentView { visit(root) }
        return result
    }
}
#endif
