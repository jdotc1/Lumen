import Foundation
import XCTest
@testable import LumenTokens

final class LumenMetricsExportTests: XCTestCase {
    func testSchemaDescribesMetricBoundsAndPresets() throws {
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(LumenExport.themeSchemaJSON(.core).utf8)) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
        XCTAssertEqual(properties["schemaVersion"]?["maximum"] as? Int, 2)
        XCTAssertEqual(properties["metrics"]?["$ref"] as? String, "#/$defs/metrics")
        let definitions = try XCTUnwrap(schema["$defs"] as? [String: [String: Any]])
        let metrics = try XCTUnwrap(definitions["metrics"])
        XCTAssertEqual(metrics["additionalProperties"] as? Bool, false)
        let members = try XCTUnwrap(metrics["properties"] as? [String: [String: Any]])
        XCTAssertEqual(Set(members.keys), ["radiusProfile", "typeScale", "spacingScale", "motion", "depth"])
        XCTAssertEqual(members["typeScale"]?["minimum"] as? Double, 0.9)
        XCTAssertEqual(members["typeScale"]?["maximum"] as? Double, 1.3)
        XCTAssertEqual(members["spacingScale"]?["minimum"] as? Double, 1.0)
        XCTAssertEqual(members["spacingScale"]?["maximum"] as? Double, 1.25)
        XCTAssertEqual(members["motion"]?["enum"] as? [String], ["standard", "reduced", "none"])
        let radii = try XCTUnwrap(members["radiusProfile"]?["oneOf"] as? [[String: Any]])
        XCTAssertEqual(radii[0]["enum"] as? [String], ["standard", "rounded"])
        XCTAssertEqual(radii[1]["minimum"] as? Double, 0)
        XCTAssertEqual(radii[1]["maximum"] as? Double, 12)
        XCTAssertFalse((schema["required"] as? [String] ?? []).contains("metrics"))
        XCTAssertNotNil(schema["anyOf"], "Metrics do not replace required colors or inheritance")
    }

    func testDepthSchemaHasOptionalFieldsBoundsAndDefaults() throws {
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(LumenExport.themeSchemaJSON(.core).utf8)) as? [String: Any])
        let definitions = try XCTUnwrap(schema["$defs"] as? [String: [String: Any]])
        let metricMembers = try XCTUnwrap(definitions["metrics"]?["properties"] as? [String: [String: Any]])
        let depth = try XCTUnwrap(metricMembers["depth"])
        let members = try optionalObjectMembers(depth)
        XCTAssertEqual(Set(members.keys), ["menu", "popover", "glow"])
        for (name, light, dark, radius, y) in [("menu", 0.12, 0.40, 10.0, 4.0), ("popover", 0.14, 0.45, 16.0, 6.0)] {
            let effect = try optionalObjectMembers(XCTUnwrap(members[name]))
            XCTAssertEqual(Set(effect.keys), ["opacity", "radius", "y"])
            let opacity = try optionalObjectMembers(XCTUnwrap(effect["opacity"]))
            XCTAssertEqual(Set(opacity.keys), ["light", "dark"])
            try assertNumber(opacity["light"], maximum: 0.6, default: light)
            try assertNumber(opacity["dark"], maximum: 0.6, default: dark)
            try assertNumber(effect["radius"], maximum: 32, default: radius)
            try assertNumber(effect["y"], maximum: 32, default: y)
            XCTAssertTrue((effect["y"]?["description"] as? String ?? "").contains("resolved radius"))
        }
        let glows = try optionalObjectMembers(XCTUnwrap(members["glow"]))
        XCTAssertEqual(Set(glows.keys), ["hero", "selection"])
        for (name, opacity, radius, y) in [("hero", 0.4, 20.0, 4.0), ("selection", 0.45, 8.0, 0.0)] {
            let effect = try optionalObjectMembers(XCTUnwrap(glows[name]))
            XCTAssertEqual(Set(effect.keys), ["opacity", "radius", "y"])
            try assertNumber(effect["opacity"], maximum: 0.6, default: opacity)
            try assertNumber(effect["radius"], maximum: 32, default: radius)
            try assertNumber(effect["y"], maximum: 32, default: y)
        }
        XCTAssertTrue((depth["description"] as? String ?? "").contains("at least menu's"))
    }

    func testReferenceDocumentsDepthInheritanceAndValidation() {
        let reference = LumenExport.tokenReferenceMarkdown(.core)
        XCTAssertTrue(reference.contains("### Depth"))
        XCTAssertTrue(reference.contains("including `opacity.light` and `opacity.dark`"))
        XCTAssertTrue(reference.contains("| `menu` | `light`: 0.12; `dark`: 0.40 | 10 pt | 4 pt |"))
        XCTAssertTrue(reference.contains("| `popover` | `light`: 0.14; `dark`: 0.45 | 16 pt | 6 pt |"))
        XCTAssertTrue(reference.contains("| `glow.hero` | 0.4 | 20 pt | 4 pt |"))
        XCTAssertTrue(reference.contains("| `glow.selection` | 0.45 | 8 pt | 0 pt |"))
        XCTAssertTrue(reference.contains("y is 0–radius"))
        XCTAssertTrue(reference.contains("LumenPack.lockedMetrics = [.depth]"))
    }

    private func optionalObjectMembers(_ object: [String: Any]) throws -> [String: [String: Any]] {
        XCTAssertEqual(object["type"] as? String, "object")
        XCTAssertEqual(object["additionalProperties"] as? Bool, false)
        XCTAssertNil(object["required"], "Every nested depth field must be optional")
        return try XCTUnwrap(object["properties"] as? [String: [String: Any]])
    }

    private func assertNumber(_ value: [String: Any]?, maximum: Double, default defaultValue: Double) throws {
        let value = try XCTUnwrap(value)
        XCTAssertEqual(value["type"] as? String, "number")
        XCTAssertEqual(value["minimum"] as? Double, 0)
        XCTAssertEqual(value["maximum"] as? Double, maximum)
        XCTAssertEqual(value["default"] as? Double, defaultValue)
    }

    func testRegistryLocksAppearInSchemaAndReference() throws {
        var pack = LumenPack(id: "test.locks", tokens: [])
        pack.lockedMetrics = [.typeScale, .motion]
        let registry = LumenRegistry(packs: [.core, pack])
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(LumenExport.themeSchemaJSON(registry).utf8)) as? [String: Any])
        let definitions = try XCTUnwrap(schema["$defs"] as? [String: [String: Any]])
        let members = try XCTUnwrap(definitions["metrics"]?["properties"] as? [String: Any])
        XCTAssertEqual(members["typeScale"] as? Bool, false)
        XCTAssertEqual(members["motion"] as? Bool, false)
        XCTAssertNotNil(members["spacingScale"] as? [String: Any])
        XCTAssertTrue(LumenExport.tokenReferenceMarkdown(registry).contains("Locked by this registry: `motion`, `typeScale`."))
    }

    func testBuiltInExportCarriesOnlyContrastMetrics() throws {
        let themes = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(LumenExport.builtInThemesJSON(.core).utf8)) as? [[String: Any]])
        for theme in themes {
            if theme["id"] as? String == LumenThemes.contrastID {
                XCTAssertEqual(theme["schemaVersion"] as? Int, 2)
                XCTAssertEqual((theme["metrics"] as? [String: Double])?["typeScale"], 1.1)
            } else {
                XCTAssertEqual(theme["schemaVersion"] as? Int, 1)
                XCTAssertNil(theme["metrics"])
            }
        }
        let reference = LumenExport.tokenReferenceMarkdown(.core)
        XCTAssertTrue(reference.contains("## Theme metrics"))
        XCTAssertTrue(reference.contains("| Contrast | `{\"typeScale\":1.1}` |"))
        XCTAssertTrue(reference.contains("24 pt minimum hit target"))
    }
}

/// Invokes the already-built CLI. The focused test command follows `swift build --build-tests`.
final class LumenMetricsCLITests: XCTestCase {
    func testValidateRejectsTypeScaleOutsideBounds() throws {
        let result = try validate(#"{"schemaVersion":2,"id":"test.large","name":"Large","inherits":"lumen.standard","metrics":{"typeScale":1.4}}"#)
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("error"), result.output)
        XCTAssertTrue(result.output.contains("typeScale"), result.output)
    }

    func testValidateRejectsRadiusAboveHalfControlHeight() throws {
        let result = try validate(#"{"schemaVersion":2,"id":"test.round","name":"Round","inherits":"lumen.standard","metrics":{"radiusProfile":12.1}}"#)
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("error"), result.output)
        XCTAssertTrue(result.output.contains("radiusProfile"), result.output)
    }

    func testValidateReportsNewerAppForVersionThree() throws {
        let result = try validate(#"{"schemaVersion":3,"id":"test.future","name":"Future"}"#)
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("needs a newer Lumen (theme format 3)"), result.output)
    }

    func testValidateAcceptsSchemaTwoMetricsWithoutUnknownFieldWarnings() throws {
        let result = try validate(#"{"schemaVersion":2,"id":"test.valid","name":"Valid","inherits":"lumen.standard","metrics":{"typeScale":1.1,"spacingScale":1.25,"radiusProfile":"rounded","motion":"reduced"}}"#)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("0 errors, 0 warnings"), result.output)
    }

    func testValidateAcceptsPartialDepthWithoutUnknownFieldWarnings() throws {
        let result = try validate(#"{"schemaVersion":2,"id":"test.depth","name":"Depth","inherits":"lumen.midnight","metrics":{"depth":{"menu":{"opacity":{"dark":0.42}},"popover":{"radius":20},"glow":{"hero":{"opacity":0.5},"selection":{"y":2}}}}}"#)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("0 errors, 0 warnings"), result.output)
    }

    func testValidateRejectsDepthBoundsAndHierarchy() throws {
        let invalidDepths = [
            #"{"menu":{"opacity":{"light":0.61}}}"#,
            #"{"popover":{"opacity":{"dark":-0.1}}}"#,
            #"{"popover":{"radius":33}}"#,
            #"{"menu":{"y":11}}"#,
            #"{"glow":{"hero":{"y":-1}}}"#,
            #"{"popover":{"opacity":{"light":0.11}}}"#,
            #"{"popover":{"opacity":{"dark":0.39}}}"#,
            #"{"popover":{"radius":9}}"#,
            #"{"glow":{"hero":{"opacity":0.61}}}"#,
            #"{"glow":{"selection":{"radius":33}}}"#,
            #"{"glow":{"selection":{"y":9}}}"#,
        ]
        for depth in invalidDepths {
            let json = "{\"schemaVersion\":2,\"id\":\"test.depth\",\"name\":\"Depth\",\"inherits\":\"lumen.midnight\",\"metrics\":{\"depth\":\(depth)}}"
            let result = try validate(json)
            XCTAssertEqual(result.status, 1, "\(depth): \(result.output)")
            XCTAssertTrue(result.output.contains("error"), result.output)
            XCTAssertTrue(result.output.contains("depth"), result.output)
        }
    }

    private func validate(_ json: String) throws -> (status: Int32, output: String) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appending(path: ".build/metrics-cli-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "theme.json")
        try json.write(to: input, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appending(path: "lumen-theme")
        process.arguments = ["validate", input.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
