import AppKit
import LumenTokens
import LumenUI
import SwiftUI
import XCTest
@testable import LumenConformance

@MainActor
final class LumenCheckTests: XCTestCase {
    private struct EchoCheck: LumenCheck {
        let id: String
        var title: String { id }
        func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
            [.init(.coverage, context.subject?.name ?? "source", id)]
        }
    }

    func testRunnerPreservesContextCheckOrderDuplicatesAndFormat() {
        let checks: [any LumenCheck] = [EchoCheck(id: "first"), EchoCheck(id: "second"), EchoCheck(id: "first")]
        XCTAssertEqual(checks[0].owner, "Lumen")
        let contexts = ["one", "two"].map { LumenCheckContext(subject: ($0, AnyView(EmptyView()))) }
        XCTAssertEqual(LumenConformance.run(checks, in: contexts).map(\.description), [
            "coverage · one: first", "coverage · one: second", "coverage · one: first",
            "coverage · two: first", "coverage · two: second", "coverage · two: first",
        ])
        XCTAssertEqual(LumenConformance.run([], in: contexts), [])
        XCTAssertEqual(LumenConformance.run(checks, in: []), [])
    }

    func testContextDefaultsAndExplicitEmptyThemes() {
        let context = LumenCheckContext()
        XCTAssertNil(context.subject)
        XCTAssertNil(context.themes)
        XCTAssertEqual(context.sizes.count, 2)
        XCTAssertEqual(context.variants.count, 1)
        XCTAssertEqual(LumenConformance.run([ThemesCheck()], in: [.init(themes: [])]), [])
    }

    func testThemeAndCoverageProtocolUseContextRegistry() {
        let orphan = LumenTheme(id: "test.orphan", name: "Orphan", inherits: "absent", light: nil, dark: nil)
        let checks: [any LumenCheck] = [ThemesCheck(), CoverageCheck(usedKeys: ["absent", "absent"])]
        XCTAssertEqual(LumenConformance.run(checks, in: [.init(themes: [orphan])]),
                       LumenConformance.themes(in: .core, themes: [orphan])
                       + LumenConformance.coverage(in: .core, usedKeys: ["absent"]))
    }

    func testShortcutAndVisibleDuplicateCompatibility() {
        let shortcuts = [(title: "Toggle", shortcut: KeyboardShortcut("s"))]
        let duplicate = VisibleDuplicatesCheck(column: "Names", values: ["abcdef-one", "abcdef-two"],
                                               width: 30, font: .systemFont(ofSize: 12))
        let result = LumenConformance.run([ShortcutsCheck(owners: shortcuts), duplicate], in: [.init()])
        XCTAssertEqual(result, LumenConformance.shortcuts(shortcuts)
                       + LumenConformance.visibleDuplicates(column: duplicate.column, values: duplicate.values,
                           width: duplicate.width, font: duplicate.font))
        XCTAssertFalse(result.isEmpty)
    }

    func testLayoutProtocolPreservesColumnAndWindowFindings() {
        let columns = [LumenConformance.Column("Detail", minWidth: 50) { Color.clear.frame(width: 100) }]
        let check = LayoutCheck(windowMinWidth: 40, columns: columns)
        XCTAssertEqual(LumenConformance.run([check], in: [.init()]),
                       LumenConformance.layout(windowMinWidth: 40, columns: columns))
    }

    func testRenderedChecksRequireASubject() {
        let checks: [any LumenCheck] = [TruncationCheck(), IconScaleCheck(), BacklightCheck(), OverflowCheck(),
                                      NarrowSizingCheck(), SurfaceStepsCheck()]
        XCTAssertEqual(LumenConformance.run(checks, in: [.init()]).map(\.message),
                       Array(repeating: "requires a subject", count: checks.count))
    }

    func testGeometryChecksUseSizesAndSnapshotVariants() {
        let context = LumenCheckContext(sizes: [CGSize(width: 80, height: 60)], variants: [
            .init(themeID: LumenThemes.standardID, colorScheme: .light),
            .init(themeID: LumenThemes.midnightID, colorScheme: .dark),
        ], subject: ("Wide", AnyView(Color.clear.frame(width: 140, height: 20))))
        let findings = LumenConformance.run([OverflowCheck()], in: [context])
        XCTAssertEqual(findings.count, 2)
        XCTAssertTrue(findings.allSatisfy { $0.message == "the content is 60 pt wider than its 80 pt frame" })
    }

    func testSourcePatternsReadLiteralOccurrencesAndDeduplicateInputs() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("View.swift")
        try ".primary .primary\n.secondary\n.PRIMARY".write(to: file, atomically: true, encoding: .utf8)
        let check = LumenConformance.forbiddenSourcePatterns([".secondary", ".primary", ".primary"], in: [file, file])
        XCTAssertEqual(LumenConformance.run([check], in: [.init()]).map(\.message), [
            "forbidden pattern “.primary” occurs 2 time(s)", "forbidden pattern “.secondary” occurs 1 time(s)",
        ])
        XCTAssertEqual(LumenConformance.run([LumenConformance.forbiddenSourcePatterns([".tertiary"], in: [file])], in: [.init()]), [])
    }

    func testSourcePatternsReportUnreadableFilesAndInvalidPatterns() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let check = LumenConformance.forbiddenSourcePatterns([""], in: [directory.appendingPathComponent("missing.swift")])
        let findings = LumenConformance.run([check], in: [.init()])
        XCTAssertEqual(findings.count, 2)
        XCTAssertEqual(findings.first?.message, "an empty source pattern is not valid")
        XCTAssertTrue(findings.last?.message.hasPrefix("could not read UTF-8 source:") == true)
    }

    private func fixtureDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(".build/conformance-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
