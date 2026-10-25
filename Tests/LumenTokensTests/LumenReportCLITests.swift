import Foundation
import XCTest
@testable import LumenTokens

final class LumenReportCLITests: XCTestCase {
    private let registry = LumenRegistry.core
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func run(_ arguments: [String], files: [String: String] = [:]) throws -> (Int32, String) {
        let folder = root.appending(path: ".build/report-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (name, content) in files { try content.write(to: folder.appending(path: name), atomically: true, encoding: .utf8) }
        let process = Process()
        // Use the executable built beside this test bundle, including --scratch-path builds.
        process.executableURL = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appending(path: "lumen-theme")
        process.arguments = arguments.map { files[$0] == nil ? $0 : folder.appending(path: $0).path }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func json(_ theme: LumenTheme) throws -> String { String(decoding: try JSONEncoder().encode(theme), as: UTF8.self) }
    private func rows(_ output: String) throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]])
    }

    func testIdenticalInputsAreEmpty() throws {
        let result = try run(["diff", "lumen.standard", "lumen.standard"])
        XCTAssertEqual(result.0, 0); XCTAssertEqual(result.1, "")
        let markdown = try run(["diff", "lumen.midnight", "lumen.midnight", "--format", "markdown"])
        XCTAssertEqual(markdown.1, "")
        let json = try run(["diff", "lumen.standard", "lumen.standard", "--format", "json"])
        XCTAssertTrue(try rows(json.1).isEmpty)
    }

    func testChangedColorAndEveryAffectedPairDelta() throws {
        let old = try XCTUnwrap(registry.theme(id: "lumen.standard"))
        var new = old
        new.light?[.fgPrimary] = "#FFFFFF"
        let files = try ["a.json": json(old), "b.json": json(new)]
        let result = try run(["diff", "a.json", "b.json"], files: files)
        XCTAssertEqual(result.0, 0)
        XCTAssertTrue(result.1.contains("\(try XCTUnwrap(old.light?[.fgPrimary]).hexString) → #FFFFFF"), result.1)
        let data = try run(["diff", "a.json", "b.json", "--format", "json"], files: files)
        let report = try XCTUnwrap(rows(data.1).first)
        let contrast = try XCTUnwrap(report["contrast"] as? [[String: Any]])
        let expected = LumenValidator.contrastMeasurements(for: new, appearance: .light, in: registry)
            .filter { $0.foreground == .fgPrimary || $0.ground == .fgPrimary }
        XCTAssertFalse(expected.isEmpty)
        for measurement in expected {
            let row = try XCTUnwrap(contrast.first { $0["rule"] as? String == measurement.key && $0["appearance"] as? String == "light" })
            let after = try XCTUnwrap(row["after"] as? [String: Any])
            XCTAssertEqual(after["ratio"] as? Double, measurement.ratio)
            XCTAssertEqual(after["passes"] as? Bool, measurement.passes)
            XCTAssertNotNil(row["before"])
        }
    }

    func testAddedAndRemovedTokens() throws {
        let a = ##"{"id":"a","name":"A","light":{"custom.old":"#112233","fg.primary":"#000000"}}"##
        let b = ##"{"id":"b","name":"B","light":{"custom.new":"#445566","fg.primary":"#000000"}}"##
        let result = try run(["diff", "a", "b"], files: ["a": a, "b": b])
        XCTAssertEqual(result.0, 0)
        XCTAssertTrue(result.1.contains("custom.old (removed): #112233 → absent"))
        XCTAssertTrue(result.1.contains("custom.new (added): absent → #445566"))
    }

    func testMetricsDepthAndMarkdownShape() throws {
        let a = #"{"id":"a","name":"A","inherits":"lumen.standard","metrics":{"typeScale":1.0,"depth":{"menu":{"radius":10}}}}"#
        let b = #"{"id":"a","name":"A","inherits":"lumen.standard","metrics":{"typeScale":1.1,"depth":{"menu":{"radius":12}}}}"#
        let result = try run(["diff", "a", "b", "--format", "markdown"], files: ["a": a, "b": b])
        XCTAssertEqual(result.0, 0)
        XCTAssertTrue(result.1.hasPrefix("##### a (changed)\n"), result.1)
        XCTAssertTrue(result.1.contains("metrics.typeScale (changed): 1 → 1.1"), result.1)
        XCTAssertTrue(result.1.contains("metrics.depth.menu.radius (changed): 10 → 12"), result.1)
    }

    func testCollectionUnionAndInheritance() throws {
        let a = ##"[{"id":"parent","name":"Parent","light":{"fg.primary":"#000000"}},{"id":"gone","name":"Gone","light":{}}]"##
        let b = ##"[{"id":"parent","name":"Parent","light":{"fg.primary":"#FFFFFF"}},{"id":"child","name":"Child","inherits":"parent"}]"##
        let result = try run(["diff", "a", "b", "--format", "json"], files: ["a": a, "b": b])
        XCTAssertEqual(result.0, 0)
        let reports = try rows(result.1)
        XCTAssertEqual(reports.compactMap { $0["theme"] as? String }, ["child", "gone", "parent"])
        XCTAssertEqual(reports.compactMap { $0["status"] as? String }, ["added", "removed", "changed"])
    }

    func testContrastAgreesWithValidatorOnFailingFixtureAndSortsFailuresFirst() throws {
        var theme = try XCTUnwrap(registry.theme(id: "lumen.standard"))
        theme.light?[.fgPrimary] = "#FFFFFF"
        let result = try run(["contrast", "theme", "--format", "json"], files: ["theme": try json(theme)])
        XCTAssertEqual(result.0, 0)
        let report = try XCTUnwrap(rows(result.1).first)
        let contrast = try XCTUnwrap(report["contrast"] as? [[String: Any]])
        var sawPass = false
        for row in contrast {
            let after = try XCTUnwrap(row["after"] as? [String: Any])
            let passes = try XCTUnwrap(after["passes"] as? Bool)
            if passes { sawPass = true } else { XCTAssertFalse(sawPass) }
        }
        let measurements = LumenValidator.contrastMeasurements(for: theme, appearance: .light, in: registry)
        let failing = try XCTUnwrap(measurements.first { $0.foreground == .fgPrimary && !$0.passes && $0.context == "normal" })
        let issue = try XCTUnwrap(LumenValidator.contrastIssue(failing.foreground,
            LumenContrast(on: failing.ground, minimum: failing.minimum), in: theme, appearance: .light, registry: registry))
        let row = try XCTUnwrap(contrast.first { $0["rule"] as? String == failing.key && $0["appearance"] as? String == "light" })
        XCTAssertEqual((row["after"] as? [String: Any])?["ratio"] as? Double, failing.ratio)
        XCTAssertTrue(issue.message.contains(String(format: "%.2f:1", failing.ratio)))
        XCTAssertTrue(LumenValidator.issues(for: theme, in: registry).contains { $0.message == issue.message })
    }

    func testHighContrastAndAppearanceRemoval() throws {
        let a = ##"{"id":"a","name":"A","light":{"fg.primary":"#000000"},"dark":{},"lightHighContrast":{"fg.primary":"#112233"}}"##
        let b = ##"{"id":"a","name":"A","light":{"fg.primary":"#000000"},"lightHighContrast":{"fg.primary":"#445566"}}"##
        let result = try run(["diff", "a", "b"], files: ["a": a, "b": b])
        XCTAssertTrue(result.1.contains("[light+contrast] fg.primary (changed): #112233 → #445566"))
        XCTAssertTrue(result.1.contains("[dark]"))
        XCTAssertTrue(result.1.contains("(removed)"))
    }

    func testUnreadableMalformedDuplicateAndFutureInputsFail() throws {
        for source in ["not json", #"[{"id":"a","name":"A","light":{}},{"id":"a","name":"B","light":{}}]"#,
                       #"{"schemaVersion":3,"id":"a","name":"A"}"#,
                       #"{"id":"a","name":"A","inherits":"missing"}"#] {
            let result = try run(["diff", "a", "lumen.standard"], files: ["a": source])
            XCTAssertNotEqual(result.0, 0)
        }
        XCTAssertNotEqual(try run(["contrast", "/nonexistent/lumen-theme-fixture.json"]).0, 0)
    }
}
