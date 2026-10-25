import AppKit
import XCTest
import LumenUI

final class LumenAboutPanelTests: XCTestCase {
    private func bundle(_ info: [String: String]) throws -> Bundle {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".build/about-tests/\(UUID().uuidString).bundle")
        let contents = root.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return try XCTUnwrap(Bundle(url: root))
    }

    func testOptionsIncludeHostMetadataAndAttributedCredits() throws {
        let host = try bundle([
            "CFBundleName": "TestApp", "CFBundleDisplayName": "Test App",
            "CFBundleShortVersionString": "2.3.4", "CFBundleVersion": "56",
            "LumenGitCommit": "abcdef1234567890"
        ])
        let url = try XCTUnwrap(URL(string: "https://github.com/example"))
        let options = LumenAboutPanel.options(bundle: host, copyrightHolder: "Test Owner",
                                              profileURL: url, credits: "Thanks to the team\nAnd contributors")
        XCTAssertEqual(options[.applicationName] as? String, "Test App")
        XCTAssertEqual(options[.applicationVersion] as? String, "2.3.4")
        XCTAssertEqual(options[.version] as? String, "56")
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        XCTAssertEqual(options[.init(rawValue: "Copyright")] as? String, "© \(year) Test Owner")
        let text = try XCTUnwrap(options[.credits] as? NSAttributedString)
        XCTAssertEqual(text.string, "github.com/jdotc1/LumenUI\nBuilt with Lumen \(LumenLibrary.version)\nCommit abcdef1\nThanks to the team\nAnd contributors")
        var range = NSRange()
        XCTAssertEqual(text.attribute(.link, at: 0, effectiveRange: &range) as? URL, url)
        XCTAssertEqual(range, NSRange(location: 0, length: "github.com/jdotc1/LumenUI".utf16.count))
        XCTAssertNil(text.attribute(.link, at: text.length - 1, effectiveRange: nil))
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, _ in
            XCTAssertEqual(attributes[.font] as? NSFont, NSFont.systemFont(ofSize: NSFont.smallSystemFontSize))
            XCTAssertEqual(attributes[.foregroundColor] as? NSColor, NSColor.labelColor)
            XCTAssertEqual((attributes[.paragraphStyle] as? NSParagraphStyle)?.alignment, .center)
        }
    }

    func testDefaultsWithoutCommitOrExtraCredits() throws {
        let options = LumenAboutPanel.options(bundle: try bundle(["CFBundleName": "FallbackName"]))
        XCTAssertEqual(options[.applicationName] as? String, "FallbackName")
        XCTAssertNil(options[.applicationVersion])
        XCTAssertNil(options[.version])
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        XCTAssertEqual(options[.init(rawValue: "Copyright")] as? String, "© \(year) Lumen contributors")
        let text = try XCTUnwrap(options[.credits] as? NSAttributedString)
        XCTAssertEqual(text.string, "github.com/jdotc1/LumenUI\nBuilt with Lumen \(LumenLibrary.version)")
        XCTAssertEqual(text.attribute(.link, at: 0, effectiveRange: nil) as? URL,
                       URL(string: "https://github.com/jdotc1/LumenUI"))
    }

    func testEmptyCommitAndCreditsAreOmitted() throws {
        let options = LumenAboutPanel.options(bundle: try bundle(["LumenGitCommit": " \n"]), credits: "")
        XCTAssertEqual(options[.applicationName] as? String, ProcessInfo.processInfo.processName)
        let text = try XCTUnwrap(options[.credits] as? NSAttributedString)
        XCTAssertEqual(text.string, "github.com/jdotc1/LumenUI\nBuilt with Lumen \(LumenLibrary.version)")
    }
}
