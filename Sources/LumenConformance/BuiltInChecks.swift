import AppKit
import LumenTokens
import LumenUI
import SwiftUI

// The compatibility entry points and protocol runner share these implementations.

struct ThemesCheck: LumenCheck {
    let id = "lumen.themes"
    let title = "Themes"
    var known: [String: [String]] = [:]

    nonisolated func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        return Self.evaluate(in: context.registry, themes: context.themes, allowing: known)
    }

    static func evaluate(in registry: LumenRegistry, themes: [LumenTheme]? = nil,
                              allowing known: [String: [String]] = [:]) -> [LumenConformance.Finding] {
        let supplied = Dictionary((themes ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (themes ?? registry.builtInThemes).flatMap { unflattened -> [LumenConformance.Finding] in
            let theme: LumenTheme
            do {
                theme = try unflattened.flattened { supplied[$0] ?? registry.theme(id: $0) }
            } catch {
                return [LumenConformance.Finding(.theme, unflattened.name, "it \(error)")]
            }
            guard !theme.supportedAppearances.isEmpty else {
                return [LumenConformance.Finding(.theme, theme.name, "declares no light or dark palette, so there is nothing to check")]
            }
            let allowed = Set(known[theme.name] ?? [])
            var findings = LumenValidator.issues(for: theme, in: registry)
                .map { "\($0.appearance): \($0.message)" }
                .filter { !allowed.contains($0) }
                .map { LumenConformance.Finding(.theme, theme.name, $0) }
            for (isDark, token) in theme.missingTokens(in: registry) {
                findings.append(LumenConformance.Finding(.theme, theme.name, "\(isDark ? "dark" : "light") leaves \(token.rawValue) undefined"))
            }
            return findings
        }
    }

}

@MainActor
struct LayoutCheck: LumenCheck {
    let id = "lumen.layout"
    let title = "Layout"
    let windowMinWidth: CGFloat
    let columns: [LumenConformance.Column]
    var dividers: CGFloat = 0

    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        return Self.evaluate(windowMinWidth: windowMinWidth, columns: columns, dividers: dividers)
    }

    static func evaluate(windowMinWidth: CGFloat, columns: [LumenConformance.Column], dividers: CGFloat = 0) -> [LumenConformance.Finding] {
        var findings: [LumenConformance.Finding] = []
        for column in columns {
            for (name, view) in column.contents {
                let width = LumenLayout.minimumWidth(of: view)
                if width > column.minWidth + 0.5 {
                    findings.append(LumenConformance.Finding(.layout, name, "needs \(Int(width.rounded(.up))) pt; its column (\(column.name)) allows \(Int(column.minWidth))"))
                }
            }
        }
        let total = columns.map(\.minWidth).reduce(dividers, +)
        if windowMinWidth + 0.5 < total {
            findings.append(LumenConformance.Finding(.layout, "window", "minimum \(Int(windowMinWidth)) pt is under its columns' \(Int(total.rounded(.up)))"))
        }
        return findings
    }

}

struct ShortcutsCheck: LumenCheck {
    let id = "lumen.shortcuts"
    let title = "Shortcuts"
    let owners: [(title: String, shortcut: KeyboardShortcut)]

    nonisolated func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        return Self.evaluate(owners)
    }

    static func evaluate(_ owners: [(title: String, shortcut: KeyboardShortcut)]) -> [LumenConformance.Finding] {
        var findings: [LumenConformance.Finding] = []
        let name = { (shortcut: KeyboardShortcut) in LumenKeycap.text(for: shortcut) }
        let grouped = Dictionary(grouping: owners) { LumenConformance.signature($0.shortcut) }
        for (_, group) in grouped.sorted(by: { $0.key < $1.key }) where group.count > 1 {
            findings.append(LumenConformance.Finding(.shortcut, name(group[0].shortcut),
                                    "has \(group.count) owners: \(group.map(\.title).joined(separator: ", "))"))
        }
        let reserved = Dictionary(LumenShortcuts.systemReserved.map { (LumenConformance.signature($0.shortcut), $0.title) }, uniquingKeysWith: { a, _ in a })
        let standard = Dictionary(LumenShortcuts.standardCommands.map { (LumenConformance.signature($0.shortcut), $0.title) }, uniquingKeysWith: { a, _ in a })
        for owner in owners {
            let key = LumenConformance.signature(owner.shortcut)
            if let system = reserved[key] {
                findings.append(LumenConformance.Finding(.shortcut, owner.title, "\(name(owner.shortcut)) is macOS's \(system)"))
            } else if let command = standard[key], !owner.title.localizedCaseInsensitiveContains(command) {
                findings.append(LumenConformance.Finding(.shortcut, owner.title, "\(name(owner.shortcut)) is every Mac app's \(command)"))
            }
        }
        return findings
    }

}

struct CoverageCheck: LumenCheck {
    let id = "lumen.coverage"
    let title = "Color coverage"
    let usedKeys: [String]

    nonisolated func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        return Self.evaluate(in: context.registry, usedKeys: usedKeys)
    }

    static func evaluate(in registry: LumenRegistry, usedKeys: [String]) -> [LumenConformance.Finding] {
        Set(usedKeys).sorted().compactMap { key in
            registry.contains(LumenToken(key)) ? nil : LumenConformance.Finding(.coverage, key, "isn't a registered color role")
        }
    }

}

@MainActor
struct WorkspaceWindowCheck: LumenCheck {
    let id = "lumen.workspaceWindow"
    let title = "Workspace window"
    let panels: [LumenWorkspacePanels]
    let window: (LumenWorkspacePanels) -> AnyView

    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        return Self.evaluate(sizes: context.sizes, panels: panels, window: window)
    }

    static func evaluate<Window: View>(sizes: [CGSize] = [CGSize(width: 900, height: 560), CGSize(width: 1440, height: 900)],
                                                     panels: [LumenWorkspacePanels] = LumenWorkspacePanels.allCombinations,
                                                     window: (LumenWorkspacePanels) -> Window) -> [LumenConformance.Finding] {
        WindowStructureCheck.evaluate(kind: .workspace, sizes: sizes, states: panels,
                                      describe: LumenConformance.describe, window: window)
    }
}

@MainActor
struct WindowStructureCheck: LumenCheck {
    let kind: LumenConformance.WindowKind
    nonisolated var id: String { "lumen.windowStructure.\(kind.identifier)" }
    nonisolated var title: String { kind.title }

    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        guard context.subject != nil else { return [context.missingSubject(for: title)] }
        return context.withRenderedSubject { view, _ in
            LumenConformance.windowStructure(kind: kind, sizes: context.sizes) { view }
        }
    }

    static func evaluate<State, Window: View>(kind: LumenConformance.WindowKind, sizes: [CGSize], states: [State],
                                              describe: (State) -> String, window: (State) -> Window) -> [LumenConformance.Finding] {
        var findings: [LumenConformance.Finding] = []
        var reference: CGRect?
        for size in sizes {
            for state in states {
                let stateDescription = describe(state)
                let subject = "\(Int(size.width))×\(Int(size.height))" + (stateDescription.isEmpty ? "" : ", " + stateDescription)
                let (recorder, top) = LumenConformance.layOut(window(state), size: size,
                                                            respectsMinimumSize: kind == .utility || kind == .library || kind == .document)
                for label in recorder.truncated.sorted() {
                    findings.append(LumenConformance.Finding(.layout, subject, "“\(label)” is cut short"))
                }
                for duplicate in LumenConformance.visibleDuplicates(recorder.visibleTexts) {
                    findings.append(LumenConformance.Finding(.layout, subject, duplicate))
                }
                for glow in LumenConformance.backlightEscapes(recorder) {
                    findings.append(LumenConformance.Finding(.layout, subject, glow))
                }
                for icon in recorder.undersizedIcons.sorted() {
                    findings.append(LumenConformance.Finding(.layout, subject, icon))
                }
                for clip in recorder.overflowing.sorted() + recorder.columnOverflowing.sorted() {
                    findings.append(LumenConformance.Finding(.layout, subject, clip))
                }
                if kind == .wizard {
                    for message in wizardMessages(recorder.wizardLayouts, size: size) {
                        findings.append(LumenConformance.Finding(.layout, subject, message))
                    }
                    findings.append(contentsOf: NarrowSizingCheck.evaluate(
                        [(subject, AnyView(window(state)))], referenceWidth: size.width))
                    continue
                }
                if kind == .menuBarPanel {
                    for message in menuBarPanelMessages(recorder.menuBarPanelLayouts, size: size) {
                        findings.append(LumenConformance.Finding(.layout, subject, message))
                    }
                    continue
                }
                if kind == .library {
                    for message in libraryCollapseMessages(recorder.libraryLayouts) {
                        findings.append(LumenConformance.Finding(.layout, subject, message))
                    }
                }
                if kind == .document {
                    for message in documentChromeMessages(recorder.documentChrome) {
                        findings.append(LumenConformance.Finding(.layout, subject, message))
                    }
                }
                guard let bar = recorder.frame else {
                    findings.append(LumenConformance.Finding(.layout, subject, "has no Lumen top bar; use \(kind.scaffold) or .lumenTopBar"))
                    continue
                }
                if kind.requiresUnifiedTopBar && recorder.placement != .unified {
                    findings.append(LumenConformance.Finding(.layout, subject, "the \(kind.identifier) top bar must share the window buttons' line; use .unified placement"))
                }
                if recorder.placement == .unified {
                    // the bar is the title bar band, so it starts at the window's top edge.
                    if abs(bar.minY) > 0.5 {
                        let moved = Int(bar.minY.rounded())
                        findings.append(LumenConformance.Finding(.layout, subject, moved > 0 ? "top bar starts \(moved) pt below the window's top" : "top bar moved \(-moved) pt up, off the top"))
                    }
                    if let buttons = recorder.windowButtons {
                        if let content = recorder.contentFrame, content.minX < buttons.maxX - 0.5,
                           content.minY < buttons.maxY, content.maxY > buttons.minY {
                            findings.append(LumenConformance.Finding(.layout, subject, "toolbar content overlaps the window buttons"))
                        }
                        if abs(buttons.midY - bar.midY) > 1.5 {
                            findings.append(LumenConformance.Finding(.layout, subject, "window buttons are \(Int(abs(buttons.midY - bar.midY).rounded())) pt off the top bar's center"))
                        }
                        // every item sits on the window buttons' center line.
                        for (index, item) in recorder.toolbarItems.enumerated() where abs(item.midY - buttons.midY) > 1 {
                            findings.append(LumenConformance.Finding(.layout, subject, "toolbar item \(index + 1) is \(Int(abs(item.midY - buttons.midY).rounded())) pt off the window buttons' center line"))
                        }
                        for (index, item) in recorder.toolbarItems.enumerated() where item.minX < buttons.maxX - 0.5 {
                            findings.append(LumenConformance.Finding(.layout, subject, "toolbar item \(index + 1) overlaps the window buttons"))
                        }
                    }
                    for name in recorder.droppedToolbarItems {
                        findings.append(LumenConformance.Finding(.layout, subject, "toolbar item “\(name)” was dropped for lack of room"))
                    }
                    if recorder.hasToolbar == false {
                        findings.append(LumenConformance.Finding(.layout, subject, "the unified top bar has no window toolbar to host its items"))
                    }
                } else if abs(bar.minY - top) > 0.5 {
                    let moved = Int((top - bar.minY).rounded())
                    findings.append(LumenConformance.Finding(.layout, subject, moved > 0 ? "top bar moved \(moved) pt up, off the top" : "top bar moved \(-moved) pt down"))
                }
                if let regionTop = recorder.regionTop, regionTop < bar.maxY - 0.5 {
                    findings.append(LumenConformance.Finding(.layout, subject, "a panel starts \(Int((bar.maxY - regionTop).rounded())) pt under the top bar"))
                }
                if bar.height < 1 {
                    findings.append(LumenConformance.Finding(.layout, subject, "top bar has no height"))
                } else if let reference, abs(reference.height - bar.height) > 0.5 {
                    findings.append(LumenConformance.Finding(.layout, subject, "top bar is \(Int(bar.height)) pt tall, not \(Int(reference.height))"))
                }
                if reference == nil { reference = bar }
            }
        }
        return findings
    }

    static func documentChromeMessages(_ entries: [LumenDocumentChromeEntry]) -> [String] {
        var messages: [String] = []
        if entries.isEmpty || entries.contains(where: { !$0.hasTitle }) {
            messages.append("document title is not reported; use LumenDocumentWindow")
        }
        if entries.isEmpty || entries.contains(where: { !$0.hasModifiedState }) {
            messages.append("document modified state is not reported; use LumenDocumentWindow")
        }
        return messages
    }

    static func libraryCollapseMessages(_ entries: [LumenLibraryLayoutEntry]) -> [String] {
        guard !entries.isEmpty else {
            return ["library collapse order is not reported; use LumenLibraryWindow"]
        }
        let violatesOrder = entries.contains { entry in
            // An explicit detail choice yields after an automatic source list. Otherwise equal
            // priority keeps the source list until after detail has collapsed (PRINCIPLES §9).
            entry.requested.sourceList && entry.requested.detail
                && entry.sourceListMinimum != nil && entry.detailMinimum != nil
                && entry.shown.detail && !entry.shown.sourceList
                && !(entry.explicit.detail && !entry.explicit.sourceList)
        }
        return violatesOrder ? ["the detail pane must collapse before the source list at equal priority"] : []
    }

}

@MainActor
struct TruncationCheck: LumenCheck {
    let id = "lumen.truncation"
    let title = "Truncation"

    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        guard context.subject != nil else { return [context.missingSubject(for: title)] }
        return context.withRenderedSubject { view, _ in
            Self.evaluate(sizes: context.sizes) { view }
        }
    }

    static func evaluate<Content: View>(sizes: [CGSize], of content: () -> Content) -> [LumenConformance.Finding] {
        sizes.flatMap { size in
            let recorder = LumenConformance.layOut(content(), size: size).0
            let subject = "\(Int(size.width))×\(Int(size.height))"
            return recorder.truncated.sorted().map { LumenConformance.Finding(.layout, subject, "“\($0)” is cut short") }
                + LumenConformance.visibleDuplicates(recorder.visibleTexts).map { LumenConformance.Finding(.layout, subject, $0) }
                + recorder.columnOverflowing.sorted().map { LumenConformance.Finding(.layout, subject, $0) }
        }
    }

}

@MainActor
struct VisibleDuplicatesCheck: LumenCheck {
    let id = "lumen.visibleDuplicates"
    let title = "Visible duplicates"
    let column: String
    let values: [String]
    let width: CGFloat
    let font: NSFont
    var truncation: Text.TruncationMode = .tail

    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        return Self.evaluate(column: column, values: values, width: width, font: font, truncation: truncation)
    }

    nonisolated static func evaluate(column: String, values: [String], width: CGFloat, font: NSFont,
                                         truncation: Text.TruncationMode = .tail) -> [LumenConformance.Finding] {
        let entries = Set(values.map {
            LumenVisibleTextEntry(column: column, text: $0, visible: LumenVisibleText.visible($0, width: width, font: font, truncation: truncation))
        })
        return LumenConformance.visibleDuplicates(entries).map { LumenConformance.Finding(.layout, column, $0) }
    }

}

@MainActor
struct IconScaleCheck: LumenCheck {
    let id = "lumen.iconScale"
    let title = "Icon scale"

    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        guard context.subject != nil else { return [context.missingSubject(for: title)] }
        return context.withRenderedSubject { view, _ in
            Self.evaluate(sizes: context.sizes) { view }
        }
    }

    static func evaluate<Content: View>(sizes: [CGSize], of content: () -> Content) -> [LumenConformance.Finding] {
        sizes.flatMap { size in
            LumenConformance.layOut(content(), size: size).0.undersizedIcons.sorted().map { LumenConformance.Finding(.layout, "\(Int(size.width))×\(Int(size.height))", $0) }
        }
    }

}

@MainActor
struct BacklightCheck: LumenCheck {
    let id = "lumen.backlight"
    let title = "Backlight"

    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        guard context.subject != nil else { return [context.missingSubject(for: title)] }
        return context.withRenderedSubject { view, _ in
            Self.evaluate(sizes: context.sizes) { view }
        }
    }

    static func evaluate<Content: View>(sizes: [CGSize], of content: () -> Content) -> [LumenConformance.Finding] {
        sizes.flatMap { size in
            LumenConformance.backlightEscapes(LumenConformance.layOut(content(), size: size).0).map { LumenConformance.Finding(.layout, "\(Int(size.width))×\(Int(size.height))", $0) }
        }
    }

}

@MainActor
struct OverflowCheck: LumenCheck {
    let id = "lumen.overflow"
    let title = "Overflow"

    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        guard context.subject != nil else { return [context.missingSubject(for: title)] }
        return context.withRenderedSubject { view, _ in
            Self.evaluate(sizes: context.sizes) { view }
        }
    }

    static func evaluate<Content: View>(sizes: [CGSize], of content: () -> Content) -> [LumenConformance.Finding] {
        sizes.flatMap { size in
            let subject = "\(Int(size.width))×\(Int(size.height))"
            let recorder = LumenConformance.layOut(content(), size: size).0
            return LumenConformance.rootOverflow(content(), size: size).map { LumenConformance.Finding(.layout, subject, $0) }
                + (recorder.overflowing.sorted() + recorder.columnOverflowing.sorted()).map { LumenConformance.Finding(.layout, subject, $0) }
        }
    }

}

@MainActor
struct NarrowSizingCheck: LumenCheck {
    let id = "lumen.narrowSizing"
    let title = "Narrow sizing"
    var referenceWidth: CGFloat = 240
    var factor: CGFloat = 4
    var slack: CGFloat = 80

    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        guard let subject = context.subject else { return [context.missingSubject(for: title)] }
        return Self.evaluate([(subject.name, subject.view)], referenceWidth: referenceWidth, factor: factor, slack: slack)
    }

    static func evaluate(_ subjects: [(name: String, view: AnyView)], referenceWidth: CGFloat = 240,
                                    factor: CGFloat = 4, slack: CGFloat = 80) -> [LumenConformance.Finding] {
        subjects.compactMap { subject in
            let host = NSHostingController(rootView: subject.view)
            let reference = host.sizeThatFits(in: CGSize(width: referenceWidth, height: 0)).height
            let narrow = host.sizeThatFits(in: CGSize(width: 1, height: 0)).height
            guard narrow > reference * factor, narrow - reference >= slack else { return nil }
            return LumenConformance.Finding(.layout, subject.name, "measured 1 pt wide it asks for \(Int(narrow.rounded())) pt, "
                           + "\(Int(reference.rounded())) pt at \(Int(referenceWidth)) pt: text that wraps without truncating "
                           + "needs a minimum measuring width (see LumenEmptyState.inlineMeasureWidth)")
        }
    }

}

@MainActor
struct SurfaceStepsCheck: LumenCheck {
    let id = "lumen.surfaceSteps"
    let title = "Surface steps"
    var headerHeight: CGFloat? = nil

    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        guard let subject = context.subject else { return [context.missingSubject(for: title)] }
        return context.variants.flatMap { variant in
            LumenConformance.surfaceScan(sizes: context.sizes, variant: variant, registry: context.registry,
                                         headerHeight: headerHeight, renderer: .window,
                                         themes: context.themes ?? []) { subject.view }
        }
    }

    static func evaluate<Content: View>(sizes: [CGSize], variant: LumenSnapshot.Variant = .init(themeID: LumenThemes.standardID, colorScheme: .dark),
                                                   registry: LumenRegistry = .core, of pane: () -> Content) -> [LumenConformance.Finding] {
        LumenConformance.surfaceScan(sizes: sizes, variant: variant, registry: registry, headerHeight: nil, renderer: .window, of: pane)
    }

    static func evaluate<Content: View>(sizes: [CGSize], variant: LumenSnapshot.Variant = .init(themeID: LumenThemes.standardID, colorScheme: .dark),
                                                   registry: LumenRegistry = .core, headerHeight: CGFloat, of pane: () -> Content) -> [LumenConformance.Finding] {
        LumenConformance.surfaceScan(sizes: sizes, variant: variant, registry: registry, headerHeight: headerHeight, renderer: .window, of: pane)
    }

}
