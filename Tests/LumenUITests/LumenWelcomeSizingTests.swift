import LumenTestSupport
import AppKit
import SwiftUI
import XCTest
@testable import LumenUI

@MainActor
final class LumenWelcomeSizingTests: XCTestCase {
    func testWelcomeHonorsLargerHostAndExplicitSmallerMinimum() {
        let host = NSHostingController(rootView: welcome(recents: 3)
            .lumenWelcomeMinimumSize(CGSize(width: 500, height: 240))
            .lumenRendersOffscreen())
        XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 1100, height: 800)), CGSize(width: 1100, height: 800))
        XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 600, height: 260)), CGSize(width: 600, height: 260))
    }

    func testRecentColumnGrowsWithHostAndTextAndHonorsHostWidth() {
        let baseline = LumenWelcomeSizing.recentWidth(available: 760, growth: 1, preferred: nil)
        XCTAssertEqual(baseline, 300)
        XCTAssertGreaterThan(LumenWelcomeSizing.recentWidth(available: 1100, growth: 1, preferred: nil), baseline)
        let metrics = LumenMetrics.resolving(nil, textScale: 1.3)
        let growth = metrics.layout.controlHeight / LumenMetrics.standard.layout.controlHeight
        XCTAssertEqual(LumenWelcomeSizing.recentWidth(available: 900, growth: growth, preferred: nil), 390, accuracy: 0.01)
        XCTAssertEqual(LumenWelcomeSizing.recentWidth(available: 1100, growth: growth, preferred: 500), 500)
    }

    func testShortHeightScrollsHeroAndEightRecentsAtLargerText() {
        withHost(size: CGSize(width: 800, height: 260), recents: 8, scale: 1.3) { host in
            let overflowing = scrollViews(in: host).filter {
                ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 1
            }
            XCTAssertEqual(overflowing.count, 2, "Both hero actions and eight recents must remain reachable in a short host")
            for scroll in overflowing {
                guard let document = scroll.documentView else { continue }
                let bottom = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
                scroll.contentView.scroll(to: CGPoint(x: 0, y: bottom))
                scroll.reflectScrolledClipView(scroll.contentView)
                XCTAssertEqual(scroll.contentView.bounds.origin.y, bottom, accuracy: 1)
            }
        }
    }

    func testNineRecentsNeedNoScrollingWhenHeightFits() {
        withHost(size: CGSize(width: 760, height: 1000), recents: 9, scale: 1) { host in
            XCTAssertTrue(scrollViews(in: host).isEmpty, "Available height, not the ninth item, chooses the scroll fallback")
        }
    }

    private func welcome(recents: Int) -> some View {
        LumenWelcomeView(appName: "Lumen", tagline: "Choose a project to begin.", markSymbol: "folder.fill", actions: [
            LumenWelcomeAction("New Project", subtitle: "Create a workspace", systemImage: "plus", hue: .hueBlue) {},
            LumenWelcomeAction("Open Project", subtitle: "Browse for a workspace", systemImage: "folder.fill", hue: .hueTeal) {},
            LumenWelcomeAction("Clone Repository", subtitle: "Start from a repository", systemImage: "arrow.down", hue: .hueViolet) {}
        ], recents: (0..<recents).map {
            LumenRecentItem(title: "Project \($0)", detail: "~/Projects/Project\($0)", date: Date(timeIntervalSince1970: 0))
        })
    }

    private func withHost(size: CGSize, recents: Int, scale: Double, inspect: (NSView) -> Void) {
        let host = NSHostingView(rootView: welcome(recents: recents)
            .lumenWelcomeMinimumSize(.zero)
            .lumenMetrics(.resolving(nil, textScale: scale))
            .environment(\.lumenDensity, .comfortable)
            .lumenRendersOffscreen())
        host.sizingOptions = []
        let window = LumenHeadlessHost.window(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        defer { window.close() }
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            window.update()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        inspect(host)
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        if let scroll = view as? NSScrollView { return [scroll] }
        return view.subviews.flatMap { scrollViews(in: $0) }
    }
}
