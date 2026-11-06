import AppKit
import LumenTokens
import XCTest
@testable import LumenUI

@MainActor
final class LumenThemeEditorSessionTests: XCTestCase {
    func testMetricEditRoundTripsSchemaTwoAndUndoRestoresInheritance() throws {
        let folder = try temporaryFolder()
        let store = TestPack.store(registry: .core, folder: folder)
        let session = LumenThemeEditorSession(base: LumenThemes.standard, store: store, editsInPlace: false)
        session.setTypeScale(1.2)
        XCTAssertEqual(session.draft.metrics?.typeScale, 1.2)
        XCTAssertTrue(session.isMetricOverridden(.typeScale))
        session.undo()
        XCTAssertNil(session.draft.metrics)
        session.redo()
        try session.save()
        let url = try XCTUnwrap(store.userThemeFile(for: store.theme().id))
        let file = try LumenThemeLibrary.decodeTheme(Data(contentsOf: url))
        XCTAssertEqual(file.schemaVersion, 2)
        XCTAssertEqual(file.metrics?.typeScale, 1.2)
    }

    func testUnchangedColorOnlyFileStaysByteIdenticalAndSchemaOne() throws {
        let folder = try temporaryFolder()
        let bytes = Data(##"{"id":"user.exact","name":"Exact","inherits":"lumen.standard","light":{"accent.default":"#793acb"}}"##.utf8)
        let url = folder.appending(path: "exact.json")
        try bytes.write(to: url)
        let store = TestPack.store(registry: .core, folder: folder)
        let base = try XCTUnwrap(store.themes.first { $0.id == "user.exact" })
        let session = LumenThemeEditorSession(base: base, store: store, editsInPlace: true)
        // Saving unchanged uses the store operation directly: the arbitrary original color may
        // have a contrast warning, unrelated to byte preservation.
        try store.updateUserTheme(base.id, overrides: [:], highContrastOverrides: [:], metrics: session.metricOverrides)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try LumenThemeLibrary.decodeTheme(Data(contentsOf: url)).schemaVersion, 1)
    }

    func testInPlaceMetricResetReturnsToParentAndRemovesOwnDeclaration() throws {
        let folder = try temporaryFolder()
        let source = #"{"schemaVersion":2,"id":"user.metric","name":"Metric","inherits":"lumen.contrast","metrics":{"typeScale":1.2}}"#
        try write(source, "metric.json", in: folder)
        let store = TestPack.store(registry: .core, folder: folder)
        let base = try XCTUnwrap(store.themes.first { $0.id == "user.metric" })
        let session = LumenThemeEditorSession(base: base, store: store, editsInPlace: true)
        session.resetMetric(.typeScale)
        XCTAssertEqual(session.draft.metrics?.typeScale, 1.1)
        XCTAssertFalse(session.isMetricOverridden(.typeScale))
        try session.save()
        let url = try XCTUnwrap(store.userThemeFile(for: base.id))
        XCTAssertNil(try LumenThemeLibrary.decodeTheme(Data(contentsOf: url)).metrics)
        XCTAssertEqual(store.themes.first { $0.id == base.id }?.metrics?.typeScale, 1.1)
    }

    func testLockedMetricCannotBeEditedAndDoesNotCreateUndo() {
        var pack = LumenPack(id: "test.locks")
        pack.lockedMetrics = [.radiusProfile, .typeScale, .spacingScale, .motion]
        let store = TestPack.store(registry: LumenRegistry(packs: [.core, pack]))
        let session = LumenThemeEditorSession(base: LumenThemes.standard, store: store, editsInPlace: false)
        session.setRadiusProfile(.rounded)
        session.setTypeScale(1.2)
        session.setSpacingScale(1.2)
        session.setMotion(LumenThemeMetrics.Motion.none)
        XCTAssertNil(session.draft.metrics)
        XCTAssertFalse(session.canUndo)
    }

    func testSessionUndoHistoryStartsEmptyAndCancelClearsIt() {
        let store = TestPack.store(registry: .core)
        let first = LumenThemeEditorSession(base: LumenThemes.standard, store: store, editsInPlace: false)
        first.setTypeScale(1.2)
        XCTAssertTrue(first.canUndo)
        let second = LumenThemeEditorSession(base: LumenThemes.standard, store: store, editsInPlace: false)
        XCTAssertFalse(second.canUndo)
        XCTAssertFalse(second.canRedo)
        second.undo()
        XCTAssertNil(second.draft.metrics)
        XCTAssertEqual(first.draft.metrics?.typeScale, 1.2)
        first.beginPreview()
        first.endPreview()
        XCTAssertFalse(first.canUndo)
        XCTAssertFalse(first.canRedo)
        first.undo()
        XCTAssertEqual(first.draft.metrics?.typeScale, 1.2)
    }

    func testLivePreviewRestoresSelectedThemeOnCancel() {
        let store = TestPack.store(registry: .core)
        let selected = store.theme()
        let session = LumenThemeEditorSession(base: selected, store: store, editsInPlace: false)
        session.beginPreview()
        session.setTypeScale(1.2)
        session.setColor("#224466", for: .accent, appearance: .light)
        XCTAssertEqual(store.theme().metrics?.typeScale, 1.2)
        XCTAssertEqual(store.resolvedColor(.accent, for: .light).hexString, "#224466")
        session.undo()
        XCTAssertEqual(store.resolvedColor(.accent, for: .light), selected.color(.accent, for: .light, in: .core))
        session.endPreview()
        XCTAssertEqual(store.theme(), selected)
    }

    func testEachFixIsOneUndoableEditAndImpossibleFixIsAtomic() throws {
        let store = TestPack.store(registry: .core)
        var contrast = LumenThemes.standard
        contrast.light?[.fgPrimary] = "#FFFFFF"
        var opacity = LumenThemes.standard
        let original = opacity.color(.fgPrimary, for: .light, in: .core)
        opacity.light?[.fgPrimary] = LumenColor(red: original.red, green: original.green, blue: original.blue, alpha: 0.5)
        var metric = LumenThemes.standard
        metric.metrics = LumenThemeMetrics(typeScale: 1.8)
        for (base, match) in [(contrast, "contrast"), (opacity, "opaque"), (metric, "metrics.typeScale")] {
            let session = LumenThemeEditorSession(base: base, store: store, editsInPlace: false)
            let before = session.draft
            let issue = try XCTUnwrap(LumenValidator.issues(for: before, in: .core).first {
                $0.appearance == .light && $0.fix != nil && (match == "contrast"
                    ? $0.token == .fgPrimary && $0.message.contains("needs") : $0.message.contains(match))
            })
            try session.fix(issue)
            XCTAssertFalse(LumenValidator.issues(for: session.draft, in: .core).contains { $0.appearance == issue.appearance && $0.fix == issue.fix })
            XCTAssertTrue(session.canUndo)
            session.undo()
            XCTAssertEqual(session.draft, before)
            XCTAssertFalse(session.canUndo)
            session.redo()
            XCTAssertNotEqual(session.draft, before)
        }
        let session = LumenThemeEditorSession(base: LumenThemes.standard, store: store, editsInPlace: false)
        let before = session.draft
        let impossible = LumenIssue(.error, .light, token: .fgPrimary, "Impossible contrast",
            fix: .contrast(foreground: .fgPrimary, ground: .bgCanvas, minimum: 22,
                           raised: false, foregroundOpacity: 1, groundOverlayOpacity: 0))
        XCTAssertThrowsError(try session.fix(impossible))
        XCTAssertEqual(session.draft, before)
        XCTAssertFalse(session.canUndo)
    }

    func testHighContrastFixSurvivesSaveWithoutChangingOrdinaryColor() throws {
        let folder = try temporaryFolder()
        let store = TestPack.store(registry: .core, folder: folder)
        let session = LumenThemeEditorSession(base: LumenThemes.standard, store: store, editsInPlace: false)
        let appearance = LumenAppearance(isDark: false, isHighContrast: true)
        session.setColor("#FFFFFF", for: .fgPrimary, appearance: appearance)
        let issue = try XCTUnwrap(LumenValidator.issues(for: session.draft, in: .core).first {
            $0.appearance == appearance && $0.token == .fgPrimary && $0.fix != nil
        })
        try session.fix(issue)
        let fixed = session.draft.color(.fgPrimary, for: appearance, in: .core)
        try session.save()
        XCTAssertEqual(store.theme().color(.fgPrimary, for: appearance, in: .core), LumenColor(hex: fixed.hexString))
        XCTAssertTrue(LumenValidator.issues(for: store.theme(), in: .core).isEmpty)
        XCTAssertEqual(store.theme().color(.fgPrimary, for: .light, in: .core), LumenThemes.standard.color(.fgPrimary, for: .light, in: .core))
    }
}
