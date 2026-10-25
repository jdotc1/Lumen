import Foundation
import XCTest
import LumenTokens
@testable import LumenUI

final class LumenThemeMetricsLibraryTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testEveryPublishedThemeAndVersionOneExampleRoundTripsByteIdentically() throws {
        let published = try String(contentsOf: root.appending(path: "Docs/reference/builtin-themes.json"), encoding: .utf8)
        // Keep each published object's original whitespace rather than reserializing the array.
        let pattern = try NSRegularExpression(pattern: #"(?ms)^  \{\n.*?^  \}(?=,?$)"#)
        let matches = pattern.matches(in: published, range: NSRange(published.startIndex..., in: published))
        XCTAssertEqual(matches.count, LumenRegistry.core.builtInThemes.count)
        var versionOneCount = 0
        var versionTwoCount = 0
        for match in matches {
            let range = try XCTUnwrap(Range(match.range, in: published))
            let original = Data(published[range].utf8)
            let theme = try LumenThemeLibrary.decodeTheme(original)
            XCTAssertEqual(try LumenThemeLibrary.encodeTheme(theme), original, theme.id)
            XCTAssertNil(theme.metrics?.depth, theme.id)
            if theme.schemaVersion == 1 {
                versionOneCount += 1
            } else if theme.schemaVersion == 2 {
                versionTwoCount += 1
            }
        }
        XCTAssertGreaterThan(versionOneCount, 0)
        XCTAssertGreaterThan(versionTwoCount, 0)
        let examples = try FileManager.default.contentsOfDirectory(at: root.appending(path: "Docs/examples"), includingPropertiesForKeys: nil)
        for url in examples where url.pathExtension == "json" {
            let original = try Data(contentsOf: url)
            let theme = try LumenThemeLibrary.decodeTheme(original)
            if theme.schemaVersion == 1 {
                XCTAssertEqual(try LumenThemeLibrary.encodeTheme(theme), original, url.lastPathComponent)
            }
        }
    }

    func testMidnightDeepFileRoundTripsAndResolvesInheritedPaletteAndDepth() throws {
        let original = try Data(contentsOf: root.appending(path: "Tests/Fixtures/midnight-deep.json"))
        let theme = try LumenThemeLibrary.decodeTheme(original)
        XCTAssertEqual(theme.name, "Midnight Deep")
        XCTAssertEqual(theme.inherits, LumenThemes.midnightID)
        XCTAssertEqual(theme.schemaVersion, 2)
        XCTAssertEqual(try LumenThemeLibrary.encodeTheme(theme), original)
        let flattened = try theme.flattened { LumenRegistry.core.theme(id: $0) }
        let midnight = try XCTUnwrap(LumenRegistry.core.theme(id: LumenThemes.midnightID))
        XCTAssertEqual(flattened.dark, midnight.dark)
        XCTAssertNil(midnight.metrics?.depth)
        let depth = LumenDepth.resolving(flattened.metrics?.depth)
        XCTAssertEqual(depth.menu, .init(opacity: .init(light: 0.18, dark: 0.48), radius: 14, y: 5))
        XCTAssertEqual(depth.popover, .init(opacity: .init(light: 0.22, dark: 0.55), radius: 24, y: 8))
        XCTAssertEqual(depth.glow, LumenDepth.standard.glow)
        XCTAssertTrue(LumenValidator.metricIssues(in: flattened, registry: .core).isEmpty)
    }

    func testVersionOneFixturesPreserveOptionalKeysWhitespaceHexCaseAndUnknownKeys() throws {
        let fixtures = [
            ##"{"id":"user.minimal","name":"Minimal","inherits":"lumen.standard"}"##,
            ##" { "schemaVersion": 1, "name": "Mixed", "id": "user.mixed", "light": { "accent.default": "#abcdef" }, "futureNote": "kept" } "##,
            "\n\t{\"id\":\"user.spaced\", \"name\":\"Spaced\", \"summary\":\"\", \"colorSpace\":\"srgb\", \"inherits\":\"lumen.standard\"}\n",
        ]
        for fixture in fixtures {
            let bytes = Data(fixture.utf8)
            let theme = try LumenThemeLibrary.decodeTheme(bytes)
            XCTAssertEqual(theme.schemaVersion, 1)
            XCTAssertNil(theme.metrics)
            XCTAssertEqual(try LumenThemeLibrary.encodeTheme(theme), bytes)
        }
        // The previous Contrast format remains supported even after Contrast gains v2 metrics.
        for var theme in LumenRegistry.core.builtInThemes {
            theme.metrics = nil
            theme.schemaVersion = 1
            let bytes = try LumenThemeLibrary.encodeTheme(theme)
            XCTAssertEqual(try LumenThemeLibrary.encodeTheme(LumenThemeLibrary.decodeTheme(bytes)), bytes, theme.id)
        }
    }

    func testOriginalBytesDoNotAffectThemeIdentityOrHideEdits() throws {
        let compact = Data(##"{"id":"user.x","name":"X","inherits":"lumen.standard"}"##.utf8)
        let spaced = Data(##"{ "name" : "X", "inherits" : "lumen.standard", "id" : "user.x" }"##.utf8)
        var theme = try LumenThemeLibrary.decodeTheme(compact)
        let equivalent = try LumenThemeLibrary.decodeTheme(spaced)
        XCTAssertEqual(theme, equivalent)
        XCTAssertEqual(Set([theme, equivalent]).count, 1)
        theme.name = "Changed"
        var encoded = try LumenThemeLibrary.encodeTheme(theme)
        XCTAssertNotEqual(encoded, compact)
        XCTAssertEqual(try LumenThemeLibrary.decodeTheme(encoded).name, "Changed")
        XCTAssertEqual(try LumenThemeLibrary.decodeTheme(encoded).schemaVersion, 1)
        theme.light = [.accent: "#123456"]
        encoded = try LumenThemeLibrary.encodeTheme(theme)
        XCTAssertEqual(try LumenThemeLibrary.decodeTheme(encoded).light?[.accent], "#123456")
        theme.metrics = LumenThemeMetrics(typeScale: 1.1)
        encoded = try LumenThemeLibrary.encodeTheme(theme)
        XCTAssertEqual(try LumenThemeLibrary.decodeTheme(encoded).schemaVersion, 2)
        XCTAssertEqual(try LumenThemeLibrary.decodeTheme(encoded).metrics?.typeScale, 1.1)
    }

    func testVersionTwoMetricsRoundTripAndVersionThreeUsesNewerAppError() throws {
        let bytes = Data(##"{"schemaVersion":2,"id":"user.metrics","name":"Metrics","inherits":"lumen.standard","metrics":{"radiusProfile":6,"typeScale":1.1,"spacingScale":1.2,"motion":"reduced"}}"##.utf8)
        let theme = try LumenThemeLibrary.decodeTheme(bytes)
        XCTAssertEqual(theme.metrics, LumenThemeMetrics(radiusProfile: .uniform(6), typeScale: 1.1, spacingScale: 1.2, motion: .reduced))
        XCTAssertEqual(try LumenThemeLibrary.encodeTheme(theme), bytes)
        // Even shapes this app cannot parse belong to the newer-app path once the version says 3.
        let future = Data(#"{"schemaVersion":3,"id":{},"metrics":{"typeScale":"future"}}"#.utf8)
        XCTAssertThrowsError(try LumenThemeLibrary.decodeTheme(future)) {
            XCTAssertEqual($0 as? LumenThemeImportError, .newerSchema(3))
        }
        let mislabeled = Data(##"{"schemaVersion":1,"id":"user.metrics","name":"Metrics","inherits":"lumen.standard","metrics":{"typeScale":1.1}}"##.utf8)
        XCTAssertEqual(try LumenThemeLibrary.decodeTheme(LumenThemeLibrary.encodeTheme(LumenThemeLibrary.decodeTheme(mislabeled))).schemaVersion, 2)
    }

    func testInvalidAndLockedMetricsAreReportedAndImportsWriteNothing() throws {
        var pack = LumenPack(id: "test.lock")
        pack.lockedMetrics = [.typeScale]
        let registry = LumenRegistry(packs: [.core, pack])
        let folder = try temporaryFolder(), downloads = try temporaryFolder()
        let store = TestPack.store(registry: registry, folder: folder)
        let fixtures = [
            (#"{"typeScale":1.1}"#, "typeScale"),
            (#"{"spacingScale":1.3}"#, "spacingScale"),
            (#"{"radiusProfile":13}"#, "radiusProfile"),
            (#"{"depth":{"menu":{"opacity":{"light":0.7}}}}"#, "depth.menu.opacity.light"),
            (#"{"depth":{"glow":{"hero":{"radius":33}}}}"#, "depth.glow.hero.radius"),
        ]
        for (index, fixture) in fixtures.enumerated() {
            let json = #"{"schemaVersion":2,"id":"user.metrics\#(index)","name":"Metrics","inherits":"lumen.standard","metrics":\#(fixture.0)}"#
            let filename = "metrics\(index).json"
            try write(json, filename, in: downloads)
            XCTAssertThrowsError(try store.importTheme(from: downloads.appending(path: filename))) {
                guard case .unreadable(let reason) = $0 as? LumenThemeImportError else { return XCTFail("\($0)") }
                XCTAssertTrue(reason.contains(fixture.1), reason)
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
        let library = LumenThemeLibrary.load(from: downloads, registry: registry)
        XCTAssertTrue(library.themes.isEmpty)
        XCTAssertEqual(library.problems.count, fixtures.count)
        XCTAssertEqual(store.theme().id, LumenThemes.standardID)
    }

    func testDepthLockRefusesDirectAndInheritedImportsAndSavePaths() throws {
        var parent = LumenTheme(id: "test.deep", name: "Deep", inherits: LumenThemes.midnightID,
                                light: nil, dark: nil)
        parent.metrics = .init(depth: .init(glow: .init(selection: .init(y: 0))))
        var pack = LumenPack(id: "test.depth-lock", themes: [parent])
        pack.lockedMetrics = [.depth]
        let registry = LumenRegistry(packs: [.core, pack])
        let folder = try temporaryFolder(), downloads = try temporaryFolder()
        let store = TestPack.store(registry: registry, folder: folder)
        for (index, declaration) in [
            #""inherits":"lumen.standard","metrics":{"depth":{}}"#,
            #""inherits":"lumen.standard","metrics":{"depth":{"menu":{"radius":10}}}"#,
            #""inherits":"test.deep""#,
            #""inherits":"test.deep","metrics":{"depth":{}}"#,
        ].enumerated() {
            let json = #"{"schemaVersion":2,"id":"user.depth\#(index)","name":"Depth",\#(declaration)}"#
            let filename = "depth\(index).json"
            try write(json, filename, in: downloads)
            XCTAssertThrowsError(try store.importTheme(from: downloads.appending(path: filename))) {
                guard case .unreadable(let reason) = $0 as? LumenThemeImportError else { return XCTFail("\($0)") }
                XCTAssertTrue(reason.contains("metrics.depth is locked"), reason)
            }
        }
        let inherited = try XCTUnwrap(registry.theme(id: parent.id))
        XCTAssertThrowsError(try store.duplicate(inherited))
        XCTAssertThrowsError(try store.saveUserTheme(name: "Child", inheriting: inherited, overrides: [:]))
        XCTAssertThrowsError(try store.writeNewTheme(inherited))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
        let library = LumenThemeLibrary.load(from: downloads, registry: registry)
        XCTAssertTrue(library.themes.isEmpty)
        XCTAssertEqual(library.problems.count, 4)
    }

    func testInheritedLockedMetricsCannotBypassValidationOrSavePaths() throws {
        var pack = LumenPack(id: "test.lock")
        pack.lockedMetrics = [.typeScale]
        let registry = LumenRegistry(packs: [.core, pack])
        let folder = try temporaryFolder(), downloads = try temporaryFolder()
        let store = TestPack.store(registry: registry, folder: folder)
        try write(#"{"id":"user.child","name":"Child","inherits":"lumen.contrast"}"#, "child.json", in: downloads)
        XCTAssertThrowsError(try store.importTheme(from: downloads.appending(path: "child.json"))) {
            guard case .unreadable(let reason) = $0 as? LumenThemeImportError else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("typeScale"), reason)
        }
        let contrast = try XCTUnwrap(registry.theme(id: LumenThemes.contrastID))
        XCTAssertThrowsError(try store.duplicate(contrast))
        XCTAssertThrowsError(try store.saveUserTheme(name: "Child", inheriting: contrast, overrides: [:]))
        XCTAssertThrowsError(try store.writeNewTheme(contrast))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }
}
