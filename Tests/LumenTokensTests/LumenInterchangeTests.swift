import Foundation
import XCTest
@testable import LumenTokens

final class LumenInterchangeTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func source(_ name: String) throws -> Data { try Data(contentsOf: root.appending(path: name)) }
    private func builtin() throws -> LumenTheme { try XCTUnwrap(LumenRegistry.core.theme(id: "lumen.standard")) }
    private func document(_ theme: LumenTheme? = nil) throws -> [String: Any] {
        try LumenDTCG.object(LumenDTCG.export(theme ?? builtin(), in: .core))
    }
    private func imported(_ document: [String: Any], registry: LumenRegistry = .core) throws -> LumenDTCG.ImportResult {
        try LumenDTCG.importTheme(LumenDTCG.json(document), in: registry)
    }
    private func colorPath(_ token: LumenToken, appearance: String = "light") throws -> [String] {
        let spec = try XCTUnwrap(LumenRegistry.core.spec(for: token))
        return [appearance, LumenDTCG.escaped(spec.group), LumenDTCG.escaped(token.rawValue)]
    }

    func testEveryBuiltInRoundTripsByteIdentically() throws {
        for theme in LumenRegistry.core.builtInThemes {
            let original = try LumenDTCG.encode(theme)
            let result = try LumenDTCG.importTheme(LumenDTCG.export(theme, in: .core), in: .core)
            XCTAssertEqual(result.themeJSON, original, theme.id)
            XCTAssertEqual(result.theme, theme, theme.id)
            XCTAssertTrue(result.issues.isEmpty, "\(theme.id): \(result.issues)")
        }
    }

    func testV1V2AndMidnightDeepFixtureBytesSurvive() throws {
        for name in ["Tests/Fixtures/dtcg-v1.json", "Tests/Fixtures/dtcg-v2.json", "Tests/Fixtures/midnight-deep.json", "Docs/examples/slate-sidebar.json"] {
            let bytes = try source(name)
            let dtcg = try LumenDTCG.export(themeJSON: bytes, in: .core)
            let result = try LumenDTCG.importTheme(dtcg, in: .core)
            XCTAssertEqual(result.themeJSON, bytes, name)
            XCTAssertEqual(try LumenDTCG.importTheme(LumenDTCG.export(result.theme, in: .core), in: .core).themeJSON, bytes, name)
        }
    }

    func testUnknownPathAndUnsupportedTypeAreWarnings() throws {
        var doc = try document()
        LumenDTCG.set(["$type": "number", "$value": 7], at: ["foreign", "token"], in: &doc)
        LumenDTCG.set(["$type": "fontFamily", "$value": "Example"], at: try colorPath(.bgCanvas), in: &doc)
        let result = try imported(doc)
        XCTAssertFalse(result.issues.contains { $0.severity == .error })
        XCTAssertEqual(result.issues.filter { $0.message.contains("unknown token path") && $0.severity == .warning }.count, 1)
        XCTAssertEqual(result.issues.filter { $0.message.contains("unsupported type fontFamily") && $0.severity == .warning }.count, 1)
    }

    func testEditedColorReachesValidatorAndSourceBytesChange() throws {
        var doc = try document()
        LumenDTCG.set(LumenDTCG.colorValue("#FFFFFF", space: .sRGB), at: try colorPath(.fgPrimary) + ["$value"], in: &doc)
        let result = try imported(doc)
        XCTAssertEqual(result.theme.light?[.fgPrimary], "#FFFFFF")
        XCTAssertNotEqual(result.themeJSON, try LumenDTCG.encode(builtin()))
        XCTAssertTrue(result.issues.contains { $0.severity == .error && $0.token == .fgPrimary && $0.message.contains("needs") })
        let decoded = try JSONDecoder().decode(LumenTheme.self, from: result.themeJSON)
        XCTAssertEqual(decoded, result.theme)
    }

    func testSparseDepthEditsPreserveInheritanceAndUnknownSourceFields() throws {
        var bytes = try LumenDTCG.object(source("Tests/Fixtures/midnight-deep.json"))
        bytes["futureMetadata"] = ["retained": true]
        var doc = try LumenDTCG.object(LumenDTCG.export(themeJSON: LumenDTCG.json(bytes), in: .core))
        LumenDTCG.set(0.5, at: ["depth", "menu", "dark", "$value", "color", "alpha"], in: &doc)
        let result = try imported(doc)
        XCTAssertEqual(result.theme.inherits, "lumen.midnight")
        XCTAssertNil(result.theme.light)
        XCTAssertNil(result.theme.metrics?.typeScale)
        XCTAssertEqual(result.theme.metrics?.depth?.menu?.opacity?.dark, 0.5)
        XCTAssertEqual(result.theme.metrics?.depth?.menu?.opacity?.light, 0.18)
        XCTAssertNotNil(try LumenDTCG.object(result.themeJSON)["futureMetadata"])
    }

    func testMetricPresetEditsAndConflictingShadowGeometry() throws {
        var doc = try document()
        for name in LumenDTCG.radiusNames {
            LumenDTCG.set(["value": 7, "unit": "px"], at: ["metrics", "radius", name, "$value"], in: &doc)
        }
        for name in LumenDTCG.motionNames {
            LumenDTCG.set(["value": 0, "unit": "ms"], at: ["metrics", "motion", name, "$value"], in: &doc)
        }
        LumenDTCG.set(1.2, at: ["metrics", "typeScale", "$value"], in: &doc)
        LumenDTCG.set(12, at: ["depth", "menu", "light", "$value", "blur", "value"], in: &doc)
        LumenDTCG.set(14, at: ["depth", "menu", "dark", "$value", "blur", "value"], in: &doc)
        let result = try imported(doc)
        XCTAssertEqual(result.theme.metrics?.radiusProfile, .uniform(7))
        XCTAssertEqual(result.theme.metrics?.motion, LumenThemeMetrics.Motion.none)
        XCTAssertEqual(result.theme.metrics?.typeScale, 1.2)
        XCTAssertNil(result.theme.metrics?.depth?.menu?.radius)
        XCTAssertTrue(result.issues.contains { $0.severity == .warning && $0.message.contains("conflicting appearance values") })
    }

    func testUnsupportedRampSiblingCannotBeApplied() throws {
        var doc = try document()
        for name in LumenDTCG.motionNames {
            LumenDTCG.set(["value": 0, "unit": "s"], at: ["metrics", "motion", name, "$value"], in: &doc)
        }
        LumenDTCG.set("number", at: ["metrics", "motion", "fast", "$type"], in: &doc)
        let result = try imported(doc)
        XCTAssertNil(result.theme.metrics?.motion)
        XCTAssertTrue(result.issues.contains { $0.message.contains("unsupported type number") })
        XCTAssertTrue(result.issues.contains { $0.message.contains("durations must match") })
    }

    func testEquivalentDurationUnitsKeepSourceBytes() throws {
        let bytes = try source("Tests/Fixtures/dtcg-v2.json")
        var doc = try LumenDTCG.object(LumenDTCG.export(themeJSON: bytes, in: .core))
        LumenDTCG.set(["value": 70, "unit": "ms"], at: ["metrics", "motion", "fast", "$value"], in: &doc)
        XCTAssertEqual(try imported(doc).themeJSON, bytes)
    }

    func testGroupTypeAliasesAndCycles() throws {
        var doc = try document()
        let canvasPath = try colorPath(.bgCanvas)
        LumenDTCG.set(["$type": "color", "$value": "{\(canvasPath.joined(separator: "."))}"], at: try colorPath(.bgWindow), in: &doc)
        LumenDTCG.set(["$type": "number", "typeScale": ["$value": 1.1]], at: ["metrics"], in: &doc)
        let result = try imported(doc)
        XCTAssertEqual(result.theme.metrics?.typeScale, 1.1)
        XCTAssertEqual(result.theme.light?[.bgWindow], try builtin().light?[.bgCanvas])
        LumenDTCG.set("{\(canvasPath.joined(separator: "."))}", at: canvasPath + ["$value"], in: &doc)
        XCTAssertTrue(try imported(doc).issues.contains { $0.severity == .warning && $0.message.contains("cyclic") })
    }

    func testMalformedColorAndUnsupportedGeometryDoNotCrashOrOverwrite() throws {
        var doc = try document()
        LumenDTCG.set(["colorSpace": "srgb", "components": [2, 0, 0]], at: try colorPath(.bgCanvas) + ["$value"], in: &doc)
        LumenDTCG.set(2, at: ["depth", "glow", "hero", "$value", "offsetX", "value"], in: &doc)
        LumenDTCG.set(true, at: ["metrics", "typeScale", "$value"], in: &doc)
        let result = try imported(doc)
        XCTAssertEqual(result.theme, try builtin())
        XCTAssertEqual(result.issues.filter { $0.severity == .warning }.count, 3)
    }

    func testSourceLocksAreRecordedAndDestinationLocksValidate() throws {
        var pack = LumenPack(id: "test.lock")
        pack.lockedMetrics = [.typeScale]
        let locked = LumenRegistry(packs: [.core, pack])
        let doc = try LumenDTCG.object(LumenDTCG.export(builtin(), in: locked))
        let metadata = try XCTUnwrap((doc["$extensions"] as? [String: Any])?[LumenDTCG.extensionKey] as? [String: Any])
        let packs = try XCTUnwrap(metadata["packs"] as? [[String: Any]])
        XCTAssertTrue(packs.contains { ($0["lockedMetrics"] as? [String]) == ["typeScale"] })
        var edited = doc
        LumenDTCG.set(1.1, at: ["metrics", "typeScale", "$value"], in: &edited)
        XCTAssertTrue(try imported(edited, registry: locked).issues.contains { $0.severity == .error && $0.message.contains("locked") })
    }

    func testCSSMatchesExpectedLightDarkAndContrastFile() throws {
        let theme = LumenTheme(id: "test.css", name: "CSS", light: [.bgCanvas: "#FFFFFF", .fgPrimary: "#111111"],
                               dark: [.bgCanvas: "#111111", .fgPrimary: "#EEEEEE"],
                               lightHighContrast: [.fgPrimary: "#000000"], darkHighContrast: [.fgPrimary: "#FFFFFF"])
        let registry = LumenRegistry(packs: [LumenPack(id: "css", tokens: [
            LumenTokenSpec(.bgCanvas, group: "Backgrounds"), LumenTokenSpec(.fgPrimary, group: "Text and Lines"),
        ], themes: [theme])], defaultThemeID: theme.id)
        let actual = try LumenCSS.export(theme, in: registry)
        XCTAssertEqual(actual, String(decoding: try source("Tests/Fixtures/dtcg-appearances.css"), as: UTF8.self))
    }

    func testDisplayP3AndDarkOnlyCSSAndRoundTrip() throws {
        let bytes = Data(##"{"id":"p3","name":"P3","colorSpace":"display-p3","dark":{"bg.canvas":"#12345678"}}"##.utf8)
        let result = try LumenDTCG.importTheme(LumenDTCG.export(themeJSON: bytes, in: .core), in: .core)
        XCTAssertEqual(result.themeJSON, bytes)
        let css = try LumenCSS.export(result.theme, in: .core)
        XCTAssertTrue(css.contains("--lumen-bg-canvas: color(display-p3"))
        XCTAssertTrue(css.contains("@media (prefers-color-scheme: dark)"))
        XCTAssertFalse(css.contains("prefers-color-scheme: light"))
    }
}

final class LumenInterchangeCLITests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func run(_ args: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appending(path: "lumen-theme")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
    private func folder() throws -> URL {
        let folder = root.appending(path: ".build/interchange-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testExportAllDTCGAndCSSAndPlainExport() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let dtcg = folder.appending(path: "dtcg")
        let result = try run(["export", "--all", dtcg.path, "--format", "dtcg"])
        XCTAssertEqual(result.0, 0, result.1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dtcg.path).count, LumenRegistry.core.builtInThemes.count)
        let css = folder.appending(path: "theme.css")
        XCTAssertEqual(try run(["export", "lumen.standard", css.path, "--format", "css"]).0, 0)
        XCTAssertTrue(try String(contentsOf: css, encoding: .utf8).contains("--lumen-bg-canvas:"))
        let plain = folder.appending(path: "plain")
        XCTAssertEqual(try run(["export", plain.path]).0, 0)
        for (name, expected) in try [
            (LumenExport.fileNames.themes, LumenExport.builtInThemesJSON(.core)),
            (LumenExport.fileNames.schema, LumenExport.themeSchemaJSON(.core)),
            (LumenExport.fileNames.reference, LumenExport.tokenReferenceMarkdown(.core)),
        ] {
            XCTAssertEqual(try Data(contentsOf: plain.appending(path: name)), Data(expected.utf8))
        }
    }

    func testFixtureImportWritesOriginalBytesAndStdout() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = root.appending(path: "Tests/Fixtures/midnight-deep.json")
        XCTAssertEqual(try run(["export", "--format", "dtcg", fixture.path, folder.path]).0, 0)
        let input = folder.appending(path: "test.midnight-deep.tokens.json")
        let output = folder.appending(path: "imported.json")
        let result = try run(["import", input.path, "-o", output.path, "--format", "dtcg"])
        XCTAssertEqual(result.0, 0, result.1)
        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: fixture))
        let stdout = try run(["import", "--format", "dtcg", input.path])
        XCTAssertEqual(stdout.0, 0, stdout.1)
        XCTAssertEqual(Data(stdout.1.utf8), try Data(contentsOf: fixture))
    }

    func testImportValidationFailureDoesNotOverwriteOutput() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var theme = try XCTUnwrap(LumenRegistry.core.theme(id: "lumen.standard"))
        theme.light?[.fgPrimary] = "#FFFFFF"
        let input = folder.appending(path: "bad.tokens.json"), output = folder.appending(path: "keep.json")
        try LumenDTCG.export(theme, in: .core).write(to: input)
        try Data("keep".utf8).write(to: output)
        let result = try run(["import", "--format", "dtcg", input.path, "-o", output.path])
        XCTAssertEqual(result.0, 1)
        XCTAssertTrue(result.1.contains("needs"), result.1)
        XCTAssertEqual(try Data(contentsOf: output), Data("keep".utf8))
    }

    func testBadFormatsArgumentsAndTraversalFail() throws {
        for args in [["export", "--format", "yaml", "x"], ["export", "--format", "css", "--all", "x"],
                     ["import", "--format", "css", "x"], ["export", "--format", "dtcg", "--format", "dtcg", "x"],
                     ["import", "--format"], ["export", "--unknown", "x"]] {
            XCTAssertNotEqual(try run(args).0, 0, args.joined(separator: " "))
        }
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "unsafe.json")
        try Data(#"{"id":"../escape","name":"Escape","inherits":"lumen.standard"}"#.utf8).write(to: input)
        let result = try run(["export", "--format", "dtcg", input.path, folder.path])
        XCTAssertEqual(result.0, 1)
        XCTAssertTrue(result.1.contains("filename"), result.1)
    }
}
