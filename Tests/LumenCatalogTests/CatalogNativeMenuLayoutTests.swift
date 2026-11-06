import AppKit
import SwiftUI
import XCTest
@testable import LumenCatalog

@MainActor
final class CatalogNativeMenuLayoutTests: XCTestCase {
    func testNativeMenuExamplesFitDefaultContentColumn() {
        let host = NSHostingController(rootView: MenusPage())
        let size = host.sizeThatFits(in: CGSize(width: 480, height: 900))
        XCTAssertLessThanOrEqual(size.width, 480)
    }
}
