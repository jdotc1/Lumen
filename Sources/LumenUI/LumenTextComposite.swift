import AppKit
import SwiftUI

extension View {
    /// Reports the actual shared component boundary when native/semantic text descendants
    /// omit decorative prefixes or symbols. This is ownership, never a pixel exclusion.
    func lumenTextComposite() -> some View {
        modifier(LumenTextCompositeModifier())
    }
}

private struct LumenTextCompositeModifier: ViewModifier {
    @Environment(\.lumenRendersOffscreen) private var rendersOffscreen

    func body(content: Content) -> some View {
        content.background {
            if !rendersOffscreen {
                GeometryReader { geometry in
                    LumenTextCompositeReporter(size: geometry.size)
                        .frame(width: 0, height: 0)
                }
            }
        }
    }
}

private struct LumenTextCompositeReporter: NSViewRepresentable {
    let size: CGSize
    func makeNSView(context: Context) -> LumenTextCompositeView { LumenTextCompositeView() }
    func updateNSView(_ view: LumenTextCompositeView, context: Context) { view.reportedSize = size }
}

/// Metadata lives at a zero-size anchor, so even ImageRenderer without an offscreen policy
/// has no native drawing area. The measured SwiftUI boundary remains available to live audits.
@MainActor class LumenNonpaintingReportView: NSView, LumenOwnedInkSource {
    var reportedSize = CGSize.zero
    var ownedInkRects: [CGRect] { [] }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func reportedFrame(in window: NSWindow) -> CGRect {
        window.convertToScreen(convert(CGRect(origin: .zero, size: reportedSize), to: nil))
    }
}

@MainActor final class LumenTextCompositeView: LumenNonpaintingReportView {}
