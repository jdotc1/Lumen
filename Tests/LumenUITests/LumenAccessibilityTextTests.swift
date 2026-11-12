import AppKit
import ObjectiveC
import XCTest
@_spi(LayoutAudit) @testable import LumenUI

/// SwiftUI on macOS 27 can answer accessibilityLabel/accessibilityTitle with an NSAttributedString.
/// Reading that through the `String?` overlay raised an Objective-C exception inside the DEBUG
/// layout-audit walk and crashed the debug Catalog at launch (2026-11-12).
@MainActor
final class LumenAccessibilityTextTests: XCTestCase {
    func testAttributedLabelTitleAndValueReadAsPlainStrings() {
        let element = AttributedTextElement()
        XCTAssertEqual(LumenAccessibilityText.label(of: element), "Rich label")
        XCTAssertEqual(LumenAccessibilityText.title(of: element), "Rich title")
        XCTAssertEqual(LumenAccessibilityText.value(of: element), "Rich value")
        XCTAssertEqual(LumenAccessibilityText.candidates(of: element), ["Rich label", "Rich title", "Rich value"])
        XCTAssertEqual(LumenAccessibilityText.candidates(of: NSObject()), [])
    }

    func testLayoutAuditWalksAnElementWithAnAttributedLabel() {
        AttributedLabelButton.installAttributedLabel()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let content = ChildExposingView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        window.contentView = content
        let button = AttributedLabelButton()
        button.setAccessibilityRole(.button)
        button.setAccessibilityElement(true)
        button.setAccessibilityParent(content)
        button.setAccessibilityFrame(window.convertToScreen(CGRect(x: 40, y: 80, width: 120, height: 28)))
        content.exposed = [button]
        // Never call button.accessibilityLabel() here: that is the bridging this test guards against.
        XCTAssertEqual(LumenAccessibilityText.label(of: button), "Attributed button")
        // Before the fix this raised -[NSConcreteAttributedString _fastCStringContents:].
        _ = LumenLayoutAudit.findings(in: window)
    }
}

private final class AttributedTextElement: NSObject {
    @objc func accessibilityLabel() -> Any? { NSAttributedString(string: "Rich label") }
    @objc func accessibilityTitle() -> Any? { NSAttributedString(string: "Rich title") }
    @objc func accessibilityValue() -> Any? { NSAttributedString(string: "Rich value") }
}

/// An accessibility element whose label getter returns an NSAttributedString, as SwiftUI's can.
private final class AttributedLabelButton: NSAccessibilityElement {
    static func installAttributedLabel() {
        let block: @convention(block) (AnyObject) -> AnyObject = { _ in NSAttributedString(string: "Attributed button") }
        class_replaceMethod(AttributedLabelButton.self, NSSelectorFromString("accessibilityLabel"),
                            imp_implementationWithBlock(block), "@@:")
    }
}

private final class ChildExposingView: NSView {
    var exposed: [Any] = []
    override func accessibilityChildren() -> [Any]? { exposed }
}
