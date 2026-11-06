import AppKit
import SwiftUI

// Native layout-only probes preserve the first leaf's actual column ownership.
// They add no ink, intrinsic size, hit target, or accessibility element.
#if DEBUG
final class CatalogFirstContentProbeView: NSView {
    var role = ""
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private struct CatalogFirstContentProbe: NSViewRepresentable {
    let role: String
    func makeNSView(context: Context) -> CatalogFirstContentProbeView {
        let view = CatalogFirstContentProbeView()
        view.setAccessibilityElement(false)
        view.role = role
        return view
    }
    func updateNSView(_ view: CatalogFirstContentProbeView, context: Context) { view.role = role }
}
#endif
extension View {
    func catalogFirstContent(_ role: String) -> some View {
        #if DEBUG
        background {
            if ProcessInfo.processInfo.environment["LUMEN_SETTINGS_MATRIX_NATIVE_PROBES"] == "1" {
                CatalogFirstContentProbe(role: role)
            }
        }
        #else
        self
        #endif
    }
}
