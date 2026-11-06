import LumenTokens
import LumenUI
import SwiftUI

/// An app or Lumen rule, with stable identity and metadata for a check catalog.
/// Keep mutable UI state in the context; a check itself can cross isolation boundaries.
public protocol LumenCheck: Sendable {
    var id: String { get }
    var title: String { get }
    var owner: String { get }
    @MainActor func run(in context: LumenCheckContext) -> [LumenConformance.Finding]
}

public extension LumenCheck {
    var owner: String { "Lumen" }
}

/// Inputs shared by checks. A source-only check can ignore every rendering field.
/// This is intentionally not Sendable: the optional subject contains a SwiftUI view.
public struct LumenCheckContext {
    public var registry: LumenRegistry
    /// Nil selects the registry's built-ins; an empty array asks to check no themes.
    public var themes: [LumenTheme]?
    public var sizes: [CGSize]
    public var variants: [LumenSnapshot.Variant]
    public var subject: (name: String, view: AnyView)?

    public init(registry: LumenRegistry = .core, themes: [LumenTheme]? = nil,
                sizes: [CGSize] = [CGSize(width: 900, height: 560), CGSize(width: 1440, height: 900)],
                variants: [LumenSnapshot.Variant] = [.init(themeID: LumenThemes.standardID, colorScheme: .dark)],
                subject: (name: String, view: AnyView)? = nil) {
        self.registry = registry
        self.themes = themes
        self.sizes = sizes
        self.variants = variants
        self.subject = subject
    }

    func missingSubject(for check: String) -> LumenConformance.Finding {
        .init(.layout, check, "requires a subject")
    }

    /// Geometry and accessibility checks use the same isolated stores as snapshots.
    @MainActor
    func withRenderedSubject(_ inspect: (AnyView, LumenSnapshot.Variant) -> [LumenConformance.Finding]) -> [LumenConformance.Finding] {
        guard let subject else { return [] }
        return variants.flatMap { variant in
            let store = LumenSnapshot.store(for: variant, registry: registry, themes: themes ?? [])
            return LumenThemeStore.withActiveStore(store) {
                let view = AnyView(subject.view.lumenPaletteRoot(store: store).environment(\.colorScheme, variant.colorScheme))
                return inspect(view, variant)
            }
        }
    }
}

public extension LumenConformance {
    /// Runs each check once per context, in context order then check order. Findings retain their
    /// original area, subject and message; duplicates are preserved. Empty inputs do no work.
    /// Checks decide which sizes and variants to inspect. Source checks need just one context.
    @MainActor
    static func run(_ checks: [any LumenCheck], in contexts: [LumenCheckContext]) -> [Finding] {
        contexts.flatMap { context in checks.flatMap { $0.run(in: context) } }
    }
}
