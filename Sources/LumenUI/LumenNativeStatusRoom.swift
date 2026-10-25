import AppKit
import SwiftUI

/// Reads the native allocation around a status item. The item viewer includes AppKit's platter
/// insets and spacing; subtracting peer allocations leaves the space the status may consume.
/// No window-width breakpoints or estimates of neighboring controls enter this measurement.
struct LumenNativeStatusRoom: NSViewRepresentable {
    let minimum: CGFloat
    let trailingGutter: CGFloat
    @Binding var room: CGFloat?

    func makeNSView(context: Context) -> RoomView { RoomView() }
    func updateNSView(_ view: RoomView, context: Context) {
        view.minimum = minimum
        view.trailingGutter = trailingGutter
        view.publish = { if room != $0 { room = $0 } }
        view.schedule()
    }
    static func dismantleNSView(_ view: RoomView, coordinator: ()) { view.stop() }

    final class RoomView: NSView {
        var minimum: CGFloat = 0
        var trailingGutter: CGFloat = 0
        var publish: ((CGFloat) -> Void)?
        private weak var observedWindow: NSWindow?
        private var statusIdentifier: NSToolbarItem.Identifier?
        private var pending = false
        private var stopped = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Keep observing when AppKit temporarily removes an overflowing item. Its smaller
            // width must be published so the native toolbar can bring it back.
            if let window, window !== observedWindow {
                NotificationCenter.default.removeObserver(self)
                observedWindow = window
                statusIdentifier = nil
                for name in [NSWindow.didResizeNotification, NSWindow.didUpdateNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: name, object: window)
                }
            }
            schedule()
        }
        override func layout() { super.layout(); schedule() }
        @objc private func changed(_ note: Notification) { schedule() }

        func stop() {
            stopped = true
            publish = nil
            NotificationCenter.default.removeObserver(self)
        }

        func schedule() {
            guard !pending, !stopped else { return }
            pending = true
            // Never write SwiftUI state during AppKit/SwiftUI layout.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopped else { return }
                self.pending = false
                self.measure()
            }
        }

        private func measure() {
            guard let window = observedWindow, let toolbar = window.toolbar else { return }
            if let item = toolbar.items.first(where: { item in
                item.view.map { self === $0 || self.isDescendant(of: $0) } ?? false
            }) { statusIdentifier = item.itemIdentifier }
            guard let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == statusIdentifier }),
                  let host = toolbar.items[index].view else { return }
            let visible = Set((toolbar.visibleItems ?? []).map(\.itemIdentifier))
            let peers = toolbar.items.filter {
                $0.view != nil && $0.itemIdentifier != .flexibleSpace && !($0 is NSTrackingSeparatorToolbarItem)
            }
            guard peers.allSatisfy({ visible.contains($0.itemIdentifier) }), host.window === window,
                  let allocation = host.superview else {
                publish?(minimum)
                return
            }
            let frame = allocation.convert(allocation.bounds, to: nil)
            guard frame.width > 0 else { return }
            let following = toolbar.items.dropFirst(index + 1).compactMap { item -> CGRect? in
                guard item.itemIdentifier != .flexibleSpace, let view = item.view,
                      view.window === window, let container = view.superview else { return nil }
                let rect = container.convert(container.bounds, to: nil)
                return rect.minX >= frame.maxX - 0.5 ? rect : nil
            }
            // The bar is the live window width. Leading items (including a sidebar tracking
            // separator and window buttons) are already accounted for by this allocation's x.
            // Sum the real trailing allocations, including their native per-item spacing, rather
            // than relying on their current x positions: AppKit can pack them left before display.
            // Reserve Lumen's trailing gutter in addition to the native viewer insets.
            let occupiedAfter = following.reduce(CGFloat.zero) { $0 + $1.width }
            let ownInsets = max(0, frame.width - host.bounds.width)
            let available = window.frame.width - frame.minX - occupiedAfter - ownInsets - trailingGutter
            publish?(max(minimum, available.rounded(.down)))
        }
    }
}
