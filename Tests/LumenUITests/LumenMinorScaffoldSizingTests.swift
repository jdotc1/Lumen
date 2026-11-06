import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenMinorScaffoldSizingTests: XCTestCase {
    func testBreadcrumbActivityCanCompressAtDefaultAndLargerText() {
        for scale in [1.0, 1.3] {
            let breadcrumb = LumenToolbarBreadcrumb(
                ["Research workspace", "Sources", "production-configuration.swift"],
                systemImage: "folder",
                activity: .working("Indexing every configuration and dependency in the research workspace", progress: 0.5),
                onCancel: {}
            )
            .lumenTextScale(scale)
            let host = NSHostingController(rootView: breadcrumb.lumenPaletteRoot())
            XCTAssertLessThan(host.sizeThatFits(in: CGSize(width: 1, height: 10_000)).width, 220,
                              "The final fallback must not reserve the activity label's intrinsic width at scale \(scale)")
        }
    }
}
