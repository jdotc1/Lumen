import AppKit
import SwiftUI

extension View {
    /// Reports the actual shared component boundary when native/semantic text descendants
    /// omit decorative prefixes or symbols. This is ownership, never a pixel exclusion.
    func lumenTextComposite() -> some View {
        background(LumenTextCompositeReporter())
    }
}

private struct LumenTextCompositeReporter: NSViewRepresentable {
    func makeNSView(context: Context) -> LumenTextCompositeView { LumenTextCompositeView() }
    func updateNSView(_ view: LumenTextCompositeView, context: Context) {}
}

@MainActor final class LumenTextCompositeView: NSView, LumenOwnedInkSource {
    var ownedInkRects: [CGRect] { [] }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
