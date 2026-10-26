import AppKit
import LumenTestSupport
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenTextCompositeTests: XCTestCase {
    @Observable final class Policy {
        var offscreen = false
        var appearances = 0
        var count = 0
        var increment: (() -> Void)?
    }

    private struct StatefulContent: View {
        let policy: Policy
        @State private var count = 0

        var body: some View {
            Text("Value \(count)")
                .onAppear {
                    policy.appearances += 1
                    policy.count = count
                    policy.increment = { count += 1; policy.count = count }
                }
        }
    }

    private struct Root: View {
        let policy: Policy

        var body: some View {
            StatefulContent(policy: policy)
                .lumenTextComposite()
                .environment(\.lumenRendersOffscreen, policy.offscreen)
                .frame(width: 160, height: 60)
        }
    }

    func testReporterTracksOffscreenPolicyWithoutReplacingContent() {
        let policy = Policy()
        let host = NSHostingView(rootView: Root(policy: policy))
        let window = LumenHeadlessHost.window(
            contentRect: .init(x: 0, y: 0, width: 160, height: 60),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        LumenHeadlessHost.order(window)
        defer { window.close() }

        func settle() {
            for _ in 0..<5 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            }
        }
        func reporters(_ view: NSView) -> Int {
            (view is LumenTextCompositeView ? 1 : 0) + view.subviews.reduce(0) { $0 + reporters($1) }
        }
        settle()
        XCTAssertEqual(reporters(host), 1, "Live content needs its native ownership reporter")
        func metadata(_ view: NSView) -> [LumenNonpaintingReportView] {
            (view as? LumenNonpaintingReportView).map { [$0] } ?? view.subviews.flatMap(metadata)
        }
        for reporter in metadata(host) {
            XCTAssertEqual(reporter.bounds.size, .zero, "Metadata must have no native drawing area")
            XCTAssertGreaterThan(reporter.reportedFrame(in: window).width, 0)
            XCTAssertGreaterThan(reporter.reportedFrame(in: window).height, 0)
            XCTAssertFalse(reporter.isHiddenOrHasHiddenAncestor)
        }
        policy.increment?()
        for offscreen in [true, false, true] {
            policy.offscreen = offscreen
            settle()
            XCTAssertEqual(reporters(host), offscreen ? 0 : 1,
                           "Only the native reporter should follow the offscreen policy")
            XCTAssertEqual(policy.count, 1, "Changing render policy reset content state")
            XCTAssertEqual(policy.appearances, 1, "Changing render policy replaced content")
        }
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertFalse(window.isKeyWindow)
    }

    func testOffscreenCompositeDoesNotPaintNativePlaceholderCorners() throws {
        let shape = RoundedRectangle(cornerRadius: 12).fill(Color.black)
            .frame(width: 80, height: 36)
        let plain = ImageRenderer(content: shape)
        let composite = ImageRenderer(content: shape.lumenTextComposite().lumenRendersOffscreen())
        let plainImage = try XCTUnwrap(plain.cgImage)
        let compositeImage = try XCTUnwrap(composite.cgImage)
        let expected = NSBitmapImageRep(cgImage: plainImage).representation(using: .png, properties: [:])
        let actual = NSBitmapImageRep(cgImage: compositeImage).representation(using: .png, properties: [:])
        XCTAssertNotNil(expected)
        XCTAssertEqual(actual, expected, "Offscreen ownership reporting must leave transparent corners unchanged")
    }

    func testMetadataReportersNeverPaintInImageRenderer() throws {
        let shape = RoundedRectangle(cornerRadius: 12).fill(Color.black)
            .frame(width: 80, height: 36)
        func png(_ view: some View) throws -> Data {
            let image = try XCTUnwrap(ImageRenderer(content: view).cgImage)
            return try XCTUnwrap(NSBitmapImageRep(cgImage: image)
                .representation(using: .png, properties: [:]))
        }
        let expected = try png(shape)
        XCTAssertEqual(try png(shape.lumenTextComposite()), expected)
        XCTAssertEqual(try png(shape.lumenFullBleedBackground(.clear)), expected)
        for offscreen in [false, true] {
            XCTAssertEqual(try png(shape.lumenTextComposite()
                .lumenFullBleedBackground(.clear).lumenRendersOffscreen(offscreen)), expected)
        }
    }

}
