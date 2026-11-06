import AppKit
import SwiftUI

/// The selection geometry belongs to AppKit. Keep a non-rendering source-list row in the same
/// window so the themed rows follow that window's native style without a copied inset constant.
struct LumenNativeSourceListInsetReader: NSViewRepresentable {
    let onInset: (CGFloat) -> Void

    func makeNSView(context: Context) -> MeasuringView { MeasuringView(onInset: onInset) }
    func updateNSView(_ view: MeasuringView, context: Context) { view.onInset = onInset }

    final class MeasuringView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var onInset: (CGFloat) -> Void
        private let outline = NSOutlineView()
        private let scroll = NSScrollView()
        private let item = NSObject()
        private var reportedInset: CGFloat?
        private var measuring = false

        init(onInset: @escaping (CGFloat) -> Void) {
            self.onInset = onInset
            super.init(frame: .zero)
            isHidden = true
            outline.style = .sourceList
            outline.headerView = nil
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("native-selection"))
            outline.addTableColumn(column)
            outline.outlineTableColumn = column
            outline.dataSource = self
            outline.delegate = self
            scroll.documentView = outline
            addSubview(scroll)
            outline.reloadData()
            outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        required init?(coder: NSCoder) { return nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            measure()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            measure()
        }

        override func layout() {
            super.layout()
            measure()
        }

        private func measure() {
            guard window != nil, bounds.width > 0, !measuring else { return }
            measuring = true
            defer { measuring = false }
            scroll.frame = bounds
            outline.tableColumns.first?.width = bounds.width
            outline.frame.size = bounds.size
            scroll.layoutSubtreeIfNeeded()
            outline.layoutSubtreeIfNeeded()
            guard let row = outline.rowView(atRow: 0, makeIfNecessary: true),
                  let plate = row.subviews.compactMap({ $0 as? NSVisualEffectView })
                    .first(where: { $0.material == .selection }),
                  plate.frame.width > 0 else { return }
            let leading = plate.frame.minX - row.bounds.minX
            let trailing = row.bounds.maxX - plate.frame.maxX
            guard leading >= 0, trailing >= 0 else { return }
            let inset = max(leading, trailing)
            guard reportedInset != inset else { return }
            reportedInset = inset
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.onInset(inset)
            }
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? 1 : 0 }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { self.item }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            NSView(frame: .zero)
        }
    }
}
