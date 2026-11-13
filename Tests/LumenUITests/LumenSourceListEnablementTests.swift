import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenSourceListEnablementTests: XCTestCase {
    func testItemsAreEnabledByDefaultAndEnabledReturnsACopy() {
        let item = LumenSourceListItem(id: "a", title: "A")
        XCTAssertTrue(item.isEnabled)
        let off = item.enabled(false)
        XCTAssertFalse(off.isEnabled)
        XCTAssertTrue(item.isEnabled)
        XCTAssertEqual(off.id, item.id)
        XCTAssertNotEqual(off, item)
        XCTAssertTrue(off.enabled(true) == item)
    }

    func testDropZoneIntrinsicHeightIsOptIn() {
        let host = NSHostingView(rootView: LumenDropZone("Drop here").intrinsicHeight().frame(width: 300, height: 600))
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 600)
        XCTAssertLessThan(LumenDropZone("Drop here").intrinsicHeight().frame(width: 300).fittingHeight(), 300)
        XCTAssertNotNil(host)
    }
}

private extension View {
    @MainActor func fittingHeight() -> CGFloat {
        NSHostingView(rootView: self).fittingSize.height
    }
}
