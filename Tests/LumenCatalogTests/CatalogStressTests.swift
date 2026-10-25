import XCTest
@testable import LumenCatalog

@MainActor
final class CatalogStressTests: XCTestCase {
    private var subjects: [CatalogStress.Subject] { CatalogStress.subjects(openWindow: { _ in }, newDocument: {}) }

    func testEveryArchetypeIsCycledAndClean() {
        XCTAssertEqual(subjects.map(\.name), ["Workspace window", "Utility window", "Library window", "Document window"])
        for subject in subjects {
            let steps = CatalogStress.headlessSteps(for: subject)
            XCTAssertEqual(steps.map(\.name), ["minimum size", "default size", "text scale 1.3 at minimum size",
                                               "chrome drawn at minimum size", "chrome glass at minimum size"])
            for step in steps {
                XCTAssertEqual(step.findings, [], "\(subject.name) · \(step.name)")
            }
        }
    }

    func testMarkdownReportListsFindingsAndFaults() {
        var window = CatalogStress.WindowResult(kind: "Library window")
        window.steps = [.init(mode: "headless", name: "minimum size", findings: ["truncation · x"]),
                        .init(mode: "live", name: "inactive", findings: [])]
        window.faults = 3
        let report = CatalogStress.Report(pid: 1, macOS: "27.2", startedAt: Date(), windows: [window], faultNote: "note")
        XCTAssertEqual(report.findingCount, 1)
        XCTAssertEqual(report.faultCount, 3)
        let text = CatalogStress.markdown(report)
        XCTAssertTrue(text.contains("1 conformance findings"))
        XCTAssertTrue(text.contains("| headless | minimum size | truncation · x |"))
        XCTAssertTrue(text.contains("| live | inactive | clean |"))
    }
}
