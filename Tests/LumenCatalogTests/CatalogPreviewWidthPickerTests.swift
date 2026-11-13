import AppKit
import SwiftUI
import XCTest
import LumenUI
@testable import LumenCatalog

/// Design review 2026-11 #2: the segmented picker's own label compressed beside its segments and
/// wrapped "Preview width" into a column of letters. The label stays on one line at every width.
@MainActor final class CatalogPreviewWidthPickerTests: XCTestCase {
    private func height(atWidth width: CGFloat) -> CGFloat {
        let host = NSHostingView(rootView: CatalogPreviewWidthPicker(width: .constant(440))
            .frame(width: width, alignment: .leading).lumenPaletteRoot())
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    func testLabelNeverWrapsBesideOrAboveTheSegments() {
        let line = NSHostingView(rootView: Text("Preview width")).fittingSize.height
        let segments = NSSegmentedControl(labels: ["a"], trackingMode: .selectOne, target: nil, action: nil).fittingSize.height
        let wide = height(atWidth: 900)
        let narrow = height(atWidth: 320)
        print("PREVIEW-WIDTH line=\(line) segments=\(segments) wide=\(wide) narrow=\(narrow)")
        // One row beside the segments when they fit; label line + segments when stacked. A wrapped
        // label (one line per letter group) is several times either.
        XCTAssertLessThanOrEqual(wide, max(line, segments) + 2)
        XCTAssertLessThanOrEqual(narrow, line + segments + 12)
    }
}
