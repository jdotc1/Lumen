import Foundation
import XCTest
@testable import LumenCatalog

@MainActor
final class LumenScaleTimingTests: XCTestCase {
    func testRecordsFirstLayoutAtTenTimesReferenceSize() throws {
        let reportURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/lumen-scale-report.json")
        var records: [LumenScaleTimingRecord] = []
        for component in LumenScaleComponent.allCases {
            let record = autoreleasepool { LumenScaleTiming.measure(component).record }
            records.append(record)
            print("SCALE \(component.title): \(record.size) \(record.unit), \(String(format: "%.2f", record.firstLayoutMilliseconds)) ms; \(component.budgetDescription)")
            // Persist each completed sample as well, so a later interruption does not lose it.
            let report = Report(recordedAt: Date(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                                method: LumenScaleTiming.method, records: records)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(report).write(to: reportURL, options: .atomic)
        }
    }

    private struct Report: Encodable {
        let recordedAt: Date
        let operatingSystem: String
        let method: String
        let records: [LumenScaleTimingRecord]
    }
}
