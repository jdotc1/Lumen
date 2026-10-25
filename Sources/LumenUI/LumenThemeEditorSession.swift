import AppKit
import LumenTokens
import Observation

/// A window-local editing transaction. Draft changes are previewed without persisting selections.
@MainActor @Observable
final class LumenThemeEditorSession {
    let base: LumenTheme
    let store: LumenThemeStore
    let editsInPlace: Bool
    var name: String {
        didSet { refreshPreview() }
    }
    private(set) var overrides: [LumenAppearance: [LumenToken: LumenColor]] = [:]
    private(set) var metricOverrides: LumenThemeMetrics
    private(set) var revision = 0
    @ObservationIgnored private let inheritedMetrics: LumenThemeMetrics?
    @ObservationIgnored private var previewing = false
    @ObservationIgnored private var manager = UndoManager()

    init(base: LumenTheme, store: LumenThemeStore, editsInPlace: Bool) {
        self.base = base
        self.store = store
        self.editsInPlace = editsInPlace && store.userThemeFile(for: base.id) != nil
        name = self.editsInPlace ? base.name : "\(base.name) Custom"
        if self.editsInPlace, let url = store.userThemeFile(for: base.id),
           let bytes = try? Data(contentsOf: url), let source = try? LumenThemeLibrary.decodeTheme(bytes) {
            metricOverrides = source.metrics ?? LumenThemeMetrics()
            inheritedMetrics = source.inherits.flatMap { parent in
                store.themes.first { $0.id == parent }?.metrics ?? store.registry.theme(id: parent)?.metrics
            }
        } else {
            metricOverrides = LumenThemeMetrics()
            inheritedMetrics = base.metrics
        }
        manager.groupsByEvent = false
    }

    var draft: LumenTheme {
        var inherited = base
        inherited.metrics = inheritedMetrics
        return LumenThemeLibrary.editorPreview(name: name, inheriting: inherited,
            overrides: colors(highContrast: false), highContrastOverrides: colors(highContrast: true),
            metrics: metricOverrides)
    }

    var canUndo: Bool { _ = revision; return manager.canUndo }
    var canRedo: Bool { _ = revision; return manager.canRedo }

    func undo() { manager.undo(); revision += 1 }
    func redo() { manager.redo(); revision += 1 }

    func beginPreview() { previewing = true; refreshPreview() }
    func endPreview() {
        manager.removeAllActions(withTarget: self)
        guard previewing else { return }
        previewing = false
        store.setEditorPreview(nil)
    }

    func isMetricLocked(_ key: LumenThemeMetrics.Key) -> Bool { store.registry.lockedMetrics.contains(key) }
    func isMetricOverridden(_ key: LumenThemeMetrics.Key) -> Bool { metricOverrides.keys.contains(key) }

    func setColor(_ color: LumenColor, for token: LumenToken, appearance: LumenAppearance) {
        edit("Change \(token.rawValue)") { overrides[appearance, default: [:]][token] = color }
    }

    func resetColor(_ token: LumenToken, appearance: LumenAppearance) {
        edit("Reset \(token.rawValue)") { overrides[appearance]?[token] = nil }
    }

    func setRadiusProfile(_ value: LumenThemeMetrics.RadiusProfile?) {
        guard !isMetricLocked(.radiusProfile) else { return }
        edit("Change radius") { metricOverrides.radiusProfile = value }
    }

    func setTypeScale(_ value: Double?) {
        guard !isMetricLocked(.typeScale) else { return }
        edit("Change type scale") { metricOverrides.typeScale = value }
    }

    func setSpacingScale(_ value: Double?) {
        guard !isMetricLocked(.spacingScale) else { return }
        edit("Change spacing scale") { metricOverrides.spacingScale = value }
    }

    func setMotion(_ value: LumenThemeMetrics.Motion?) {
        guard !isMetricLocked(.motion) else { return }
        edit("Change motion") { metricOverrides.motion = value }
    }

    func resetMetric(_ key: LumenThemeMetrics.Key) {
        switch key {
        case .radiusProfile: setRadiusProfile(nil)
        case .typeScale: setTypeScale(nil)
        case .spacingScale: setSpacingScale(nil)
        case .motion: setMotion(nil)
        case .depth:
            guard !isMetricLocked(.depth) else { return }
            edit("Reset depth") { metricOverrides.depth = nil }
        }
    }

    /// A failed fix never enters the undo history or changes the live preview.
    func fix(_ issue: LumenIssue) throws {
        let before = draft
        let fixed = try LumenValidator.fix(issue, in: before, registry: store.registry)
        edit("Fix theme issue") {
            var changedTokens: Set<LumenToken> = []
            for appearance in LumenAppearance.all {
                let old = palette(in: before, appearance: appearance)
                let new = palette(in: fixed, appearance: appearance)
                for (name, value) in new?.colors ?? [:] {
                    let token = LumenToken(name)
                    if old?[token] != value {
                        overrides[appearance, default: [:]][token] = value
                        changedTokens.insert(token)
                    }
                }
            }
            // Normal color edits intentionally cascade to contrast variants. A Fix preserves
            // the validator's candidate without materializing unrelated fallback tokens.
            let intermediate = draft
            for appearance in LumenAppearance.all where appearance.isHighContrast {
                for token in changedTokens {
                    let target = fixed.color(token, for: appearance, in: store.registry)
                    if intermediate.color(token, for: appearance, in: store.registry) != target {
                        overrides[appearance, default: [:]][token] = target
                    }
                }
            }
            if before.metrics?.radiusProfile != fixed.metrics?.radiusProfile { metricOverrides.radiusProfile = fixed.metrics?.radiusProfile }
            if before.metrics?.typeScale != fixed.metrics?.typeScale { metricOverrides.typeScale = fixed.metrics?.typeScale }
            if before.metrics?.spacingScale != fixed.metrics?.spacingScale { metricOverrides.spacingScale = fixed.metrics?.spacingScale }
            if before.metrics?.motion != fixed.metrics?.motion { metricOverrides.motion = fixed.metrics?.motion }
        }
    }

    func save() throws {
        let errors = LumenValidator.issues(for: draft, in: store.registry).filter { $0.severity == .error }
        guard errors.isEmpty else { throw LumenThemeImportError.unreadable(errors.map(\.message).joined(separator: "; ")) }
        if editsInPlace {
            try store.updateUserTheme(base.id, overrides: colors(highContrast: false),
                highContrastOverrides: colors(highContrast: true), metrics: metricOverrides)
        } else {
            _ = try store.saveUserTheme(name: name, inheriting: base, overrides: colors(highContrast: false),
                highContrastOverrides: colors(highContrast: true), metrics: metricOverrides)
        }
        endPreview()
    }

    private func palette(in theme: LumenTheme, appearance: LumenAppearance) -> LumenPalette? {
        if appearance.isHighContrast { return appearance.isDark ? theme.darkHighContrast : theme.lightHighContrast }
        return appearance.isDark ? theme.dark : theme.light
    }

    private func colors(highContrast: Bool) -> [Bool: [LumenToken: LumenColor]] {
        Dictionary(uniqueKeysWithValues: overrides.filter { $0.key.isHighContrast == highContrast }.map { ($0.key.isDark, $0.value) })
    }

    private struct Snapshot: Equatable, Sendable {
        let colors: [LumenAppearance: [LumenToken: LumenColor]]
        let metrics: LumenThemeMetrics
    }
    private var snapshot: Snapshot { Snapshot(colors: overrides, metrics: metricOverrides) }

    private func edit(_ title: String, change: () -> Void) {
        let before = snapshot
        change()
        guard before != snapshot else { return }
        register(before, title: title)
        revision += 1
        refreshPreview()
    }

    private func register(_ value: Snapshot, title: String) {
        let opensGroup = !manager.isUndoing && !manager.isRedoing
        if opensGroup { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let inverse = target.snapshot
                target.overrides = value.colors
                target.metricOverrides = value.metrics
                target.register(inverse, title: title)
                target.revision += 1
                target.refreshPreview()
            }
        }
        manager.setActionName(title)
        if opensGroup { manager.endUndoGrouping() }
    }

    private func refreshPreview() {
        if previewing { store.setEditorPreview(draft) }
    }
}
