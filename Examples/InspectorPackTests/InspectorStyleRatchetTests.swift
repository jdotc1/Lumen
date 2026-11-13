import Foundation
import LumenConformance
import InspectorPack
import XCTest

@MainActor
final class InspectorStyleRatchetTests: XCTestCase {
    func testCustomCheckPassesAtBudgetAndFailsAboveItThroughRunner() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(".build/a3-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Sample.swift")
        try "Text(\"Name\").foregroundStyle(.primary)\nText(\"Detail\").foregroundStyle(.secondary)"
            .write(to: file, atomically: true, encoding: .utf8)
        let accepted = InspectorStyleRatchet(files: [file], budget: 2)
        XCTAssertEqual(accepted.owner, "Inspector example")
        XCTAssertEqual(LumenConformance.run([accepted], in: [.init()]), [])
        let exceeded = InspectorStyleRatchet(files: [file], budget: 1)
        XCTAssertEqual(LumenConformance.run([exceeded], in: [.init()]).map(\.description),
                       ["coverage · Inspector example: system foreground styles occur 2 time(s); budget is 1"])
        let unreadable = InspectorStyleRatchet(files: [directory.appendingPathComponent("missing")], budget: 120)
        XCTAssertEqual(LumenConformance.run([unreadable], in: [.init()]).count, 1)
    }
}
