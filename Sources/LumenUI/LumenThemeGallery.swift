import AppKit
import LumenTokens
import SwiftUI
import UniformTypeIdentifiers

/// The theme picker: one live miniature of an app window per theme, drawn from that theme's own
/// palette so every card looks like itself regardless of the active theme. Below the grid: a
/// theme picker for each extra surface the app declares, and the library actions (customize,
/// import, reveal, duplicate, reload). Cards offer export, share and Move to Trash.
public struct LumenThemeGallery: View {
    /// The store passed to `init(store:)`; `nil` uses the window's (`\.lumenStore`).
    private let explicitStore: LumenThemeStore?
    @Environment(\.lumenStore) private var environmentStore
    var store: LumenThemeStore { explicitStore ?? environmentStore }
    @State private var editingBase: LumenTheme?
    @State private var isImporting = false
    @State private var isSeeding = false
    @State private var exporting: LumenThemeFile?
    @State private var trashCandidate: LumenTheme?
    @State private var libraryError: String?
    @State private var libraryNotice: ImportNotice?
    @State private var issueCache = IssueCache()
    @State private var editingInPlace: LumenTheme?
    @State private var renaming: LumenTheme?
    @State private var renameText = ""
    @State private var isDropTargeted = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    private struct ImportNotice: Identifiable {
        let title: String
        let detail: String
        var id: String { title }
    }

    /// A gallery for the store of the window it appears in: the one `.lumenPaletteRoot(store:)`
    /// injected, so a second store's window offers and changes that store's themes.
    public init() {
        explicitStore = nil
    }

    /// A gallery for `store`. Without an argument, `init()` (the window's store, from the
    /// environment) is chosen; `init(store: .active)` reads the active store
    /// (`LumenThemeStore.active`) even under a second store's `.lumenPaletteRoot(store:)`.
    public init(store: LumenThemeStore = .active) {
        explicitStore = store
    }

    @Environment(\.fontResolutionContext) private var fontContext

    private var cards: some View {
        ForEach(store.themes) { theme in
            LumenThemeCard(
                theme: theme,
                registry: store.registry,
                appearance: previewAppearance(for: theme),
                isSelected: store.theme(for: .window).id == theme.id,
                issues: store.userThemeFile(for: theme.id) == nil ? [] : issueCache.issues(for: theme, in: store.registry)
            ) {
                store.select(theme.id)
            }
            .contextMenu { cardMenu(for: theme) }
        }
    }

    private var columns: [GridItem] {
        // Resolve the actual font, including an app's custom typography, rather than relying on
        // control height to stand in for type size.
        let font = metrics.typography.headline.resolve(in: fontContext).ctFont as NSFont
        let standard = LumenMetrics.standard.typography.headline.resolve(in: fontContext).ctFont as NSFont
        let caption = metrics.typography.caption.resolve(in: fontContext).ctFont as NSFont
        let standardCaption = LumenMetrics.standard.typography.caption.resolve(in: fontContext).ctFont as NSFont
        let growth = max(1, font.pointSize / standard.pointSize, caption.pointSize / standardCaption.pointSize)
        return [GridItem(.adaptive(minimum: 196 * growth, maximum: 260 * growth), spacing: metrics.spacing.s6)]
    }

    public var body: some View {
        let window = store.theme(for: .window)
        VStack(alignment: .leading, spacing: metrics.spacing.s5) {
            ViewThatFits(in: .horizontal) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: metrics.spacing.s6) {
                    cards
                }
                // A host narrower than one preferred card still gets a wrapping single column.
                VStack(alignment: .leading, spacing: metrics.spacing.s6) { cards }
            }
            .padding(metrics.spacing.s2)
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: metrics.radius.lg)
                        .strokeBorder(palette[.borderFocus], style: StrokeStyle(lineWidth: metrics.stroke.focus, dash: [6, 4]))
                        .accessibilityHidden(true)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                let themes = urls.filter { $0.pathExtension.lowercased() == "json" }
                importThemes(themes)
                return !themes.isEmpty
            } isTargeted: { isDropTargeted = $0 }
            if !store.themeFileProblems.isEmpty {
                fileProblems
            }
            ForEach(store.registry.surfaces.filter { $0 != .window }, id: \.self) { surface in
                surfacePicker(surface)
            }
            // Actions flow onto new rows; a label wider than the whole row wraps within it.
            LumenFlowLayout(spacing: metrics.spacing.s6, lineSpacing: metrics.spacing.s3) {
                Button {
                    editingBase = window
                } label: {
                    LumenThemeActionLabel(lumenLocalized(String(localized: "Customize %@…", defaultValue: "Customize \(window.name)…", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "paintpalette")
                }
                .accessibilityIdentifier("lumen.theme.customize")
                Button(lumenLocalized(String(localized: "New from seed…", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "sparkles") { isSeeding = true }
                Button(lumenLocalized(String(localized: "Import Theme…", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
                .accessibilityIdentifier("lumen.theme.import")
                Button(lumenLocalized(String(localized: "Reveal Themes Folder", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "folder") {
                    let directory = store.themesDirectory
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    store.watchThemesDirectory()
                    NSWorkspace.shared.activateFileViewerSelecting([directory])
                }
                Button {
                    do {
                        NSWorkspace.shared.activateFileViewerSelecting([try store.duplicate(window)])
                    } catch {
                        libraryError = error.localizedDescription
                    }
                } label: {
                    LumenThemeActionLabel(lumenLocalized(String(localized: "Duplicate %@", defaultValue: "Duplicate \(window.name)", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "plus.square.on.square")
                }
                Button(lumenLocalized(String(localized: "Reload Themes", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "arrow.clockwise") {
                    store.reloadUserThemes()
                }
            }
            .lineLimit(nil)
            // Lumen's link look (the empty state's, the tool rows'): fg.link on a bare button.
            .buttonStyle(.lumenBare)
            .foregroundStyle(palette[.fgLink])
            .lumenLinkPointer()
            .font(metrics.typography.callout)
        }
        .accessibilityIdentifier("lumen.theme.gallery")
        .sheet(isPresented: $isSeeding) { LumenThemeSeedSheet(store: store) }
        .sheet(item: $editingBase) { base in
            LumenThemeEditor(base: base, store: store)
        }
        .sheet(item: $editingInPlace) { theme in
            LumenThemeEditor(base: theme, store: store, editsInPlace: true)
        }
        .alert(lumenLocalized(String(localized: "Rename Theme", bundle: .module, comment: "ThemeGallery control text.")), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { theme in
            TextField(lumenLocalized(String(localized: "Name", bundle: .module, comment: "ThemeGallery control text.")), text: $renameText)
            Button(lumenLocalized(String(localized: "Rename", bundle: .module, comment: "ThemeGallery control text."))) {
                do { try store.renameUserTheme(theme.id, to: renameText) } catch { libraryError = error.localizedDescription }
            }
            Button(lumenLocalized(String(localized: "Cancel", bundle: .module, comment: "ThemeGallery control text.")), role: .cancel) {}
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importThemes(urls)
            case .failure(let error): libraryError = error.localizedDescription
            }
        }
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                      item: exporting, contentTypes: [.json], defaultFilename: exporting?.fileName) { result in
            if case .failure(let error) = result { libraryError = error.localizedDescription }
        }
        .confirmationDialog(lumenLocalized(String(localized: "Move “%@” to the Trash?", defaultValue: "Move “\(trashCandidate?.name ?? "")” to the Trash?", bundle: .module, comment: "ThemeGallery control text.")),
                            isPresented: Binding(get: { trashCandidate != nil }, set: { if !$0 { trashCandidate = nil } }),
                            presenting: trashCandidate) { theme in
            Button(lumenLocalized(String(localized: "Move to Trash", bundle: .module, comment: "ThemeGallery control text.")), role: .destructive) {
                do { try store.moveUserThemeToTrash(theme.id) } catch { libraryError = error.localizedDescription }
            }
        } message: { _ in
            Text(lumenLocalized(String(localized: "You can restore the theme file from the Trash in Finder.", bundle: .module, comment: "ThemeGallery control text.")))
        }
        .alert(lumenLocalized(String(localized: "Theme Problem", bundle: .module, comment: "ThemeGallery control text.")), isPresented: Binding(get: { libraryError != nil }, set: { if !$0 { libraryError = nil } })) {
            Button(lumenLocalized(String(localized: "OK", bundle: .module, comment: "ThemeGallery control text.")), role: .cancel) {}
        } message: {
            Text(libraryError ?? "")
        }
        .alert(libraryNotice?.title ?? "", isPresented: Binding(get: { libraryNotice != nil }, set: { if !$0 { libraryNotice = nil } }),
               presenting: libraryNotice) { _ in
            Button(lumenLocalized(String(localized: "Customize…", bundle: .module, comment: "ThemeGallery control text."))) { editingBase = store.theme(for: .window) }
            Button(lumenLocalized(String(localized: "OK", bundle: .module, comment: "ThemeGallery control text.")), role: .cancel) {}
        } message: { notice in
            Text(notice.detail)
        }
    }

    /// "Editor theme: Same as window / …" for one extra surface.
    private func surfacePicker(_ surface: LumenSurface) -> some View {
        let follows = store.surfaceFollowsWindow(surface)
        let current = follows ? lumenLocalized(String(localized: "Same as window", bundle: .module, comment: "ThemeGallery display text.")) : store.theme(for: surface).name
        return HStack(spacing: metrics.spacing.s4) {
            Text(lumenLocalized(String(localized: "%@ theme", defaultValue: "\(Self.title(for: surface)) theme", bundle: .module, comment: "ThemeGallery control text."))).font(metrics.typography.callout).foregroundStyle(palette[.fgPrimary])
            LumenMenuButton {
                Button { store.select(nil, for: surface) } label: {
                    if follows { Label(lumenLocalized(String(localized: "Same as window", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "checkmark") } else { Text(lumenLocalized(String(localized: "Same as window", bundle: .module, comment: "ThemeGallery control text."))) }
                }
                Divider()
                ForEach(store.themes) { theme in
                    Button { store.select(theme.id, for: surface) } label: {
                        if !follows && store.theme(for: surface).id == theme.id { Label(theme.name, systemImage: "checkmark") } else { Text(theme.name) }
                    }
                }
            } label: { LumenPopUpLabel(current) }
            .accessibilityLabel(lumenLocalized(String(localized: "%@ theme", defaultValue: "\(Self.title(for: surface)) theme", bundle: .module, comment: "ThemeGallery control text.")))
            .accessibilityValue(current)
        }
        .accessibilityIdentifier("lumen.theme.surface.\(surface.rawValue)")
    }

    /// A surface's name for display: `editor` → "Editor", `documentCanvas` → "Document canvas".
    nonisolated static func title(for surface: LumenSurface) -> String {
        var words: [String] = []
        var current = ""
        for character in surface.rawValue {
            if character.isUppercase || character == "-" || character == "_" || character == "." {
                if !current.isEmpty { words.append(current) }
                current = character.isLetter ? String(character).lowercased() : ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// Imports each file, then reports every failure and contrast warning together (one alert
    /// each), not just the last file's.
    private func importThemes(_ urls: [URL]) {
        var failures: [String] = []
        var notices: [(name: String, errors: [LumenIssue])] = []
        for url in urls {
            do {
                let imported = try store.importTheme(from: url)
                // Imports are never blocked on contrast, but the author hears about problems now
                // rather than discovering a badge later.
                let loaded = store.themes.first { $0.id == imported.id } ?? imported
                let errors = LumenValidator.issues(for: loaded, in: store.registry).filter { $0.severity == .error }
                if !errors.isEmpty { notices.append((loaded.name, errors)) }
            } catch {
                failures.append(urls.count > 1 ? "\(url.lastPathComponent): \(error.localizedDescription)" : error.localizedDescription)
            }
        }
        if !failures.isEmpty { libraryError = failures.joined(separator: "\n\n") }
        if notices.count == 1, let notice = notices.first {
            libraryNotice = ImportNotice(
                title: notice.errors.count == 1 ? lumenLocalized(String(localized: "Imported “%@” with %lld contrast problem", defaultValue: "Imported “\(notice.name)” with \(notice.errors.count) contrast problem", bundle: .module, comment: "Imported theme name and contrast problem count.")) : lumenLocalized(String(localized: "Imported “%@” with %lld contrast problems", defaultValue: "Imported “\(notice.name)” with \(notice.errors.count) contrast problems", bundle: .module, comment: "Imported theme name and contrast problem count.")),
                detail: notice.errors.prefix(5).map(\.message).joined(separator: "\n")
                    + lumenLocalized(String(localized: "\n\nSome text may be hard to read. Choose Customize… to fix the colors.", bundle: .module, comment: "ThemeGallery message; placeholders contain the related value."))
            )
        } else if notices.count > 1 {
            libraryNotice = ImportNotice(
                title: lumenLocalized(String(localized: "Imported %lld themes with contrast problems", defaultValue: "Imported \(notices.count) themes with contrast problems", bundle: .module, comment: "ThemeGallery message; placeholders contain the related value.")),
                detail: notices.map { $0.errors.count == 1 ? lumenLocalized(String(localized: "%@: %lld problem", defaultValue: "\($0.name): \($0.errors.count) problem", bundle: .module, comment: "Theme name and contrast problem count.")) : lumenLocalized(String(localized: "%@: %lld problems", defaultValue: "\($0.name): \($0.errors.count) problems", bundle: .module, comment: "Theme name and contrast problem count.")) }
                    .joined(separator: "\n") + lumenLocalized(String(localized: "\n\nSome text may be hard to read. Choose Customize… to fix the colors.", bundle: .module, comment: "ThemeGallery message; placeholders contain the related value."))
            )
        }
    }

    private func themeFile(_ theme: LumenTheme) -> LumenThemeFile {
        let registry = store.registry, themes = store.themes
        return LumenThemeFile(theme) { id in registry.theme(id: id) ?? themes.first { $0.id == id } }
    }

    @ViewBuilder
    private func cardMenu(for theme: LumenTheme) -> some View {
        let file = store.userThemeFile(for: theme.id)
        Button(lumenLocalized(String(localized: "Customize…", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "paintpalette") { editingBase = theme }
        Button(lumenLocalized(String(localized: "Duplicate", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "plus.square.on.square") {
            do { try store.duplicate(theme) } catch { libraryError = error.localizedDescription }
        }
        Divider()
        Button(lumenLocalized(String(localized: "Export…", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "square.and.arrow.up") {
            exporting = themeFile(theme)
        }
        ShareLink(item: themeFile(theme), preview: SharePreview(theme.name, image: Image(systemName: "paintpalette")))
        if let file {
            Divider()
            Button(lumenLocalized(String(localized: "Edit…", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "slider.horizontal.3") { editingInPlace = theme }
            Button(lumenLocalized(String(localized: "Rename…", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "pencil") {
                renameText = theme.name
                renaming = theme
            }
            Button(lumenLocalized(String(localized: "Show in Finder", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }
            Button(lumenLocalized(String(localized: "Move to Trash…", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "trash", role: .destructive) { trashCandidate = theme }
        }
    }

    /// Theme files that failed to load, so a theme author sees why instead of a silent omission.
    private var fileProblems: some View {
        let problems = store.themeFileProblems
        let headline = problems.count == 1 ? lumenLocalized(String(localized: "1 theme file couldn’t load", bundle: .module, comment: "ThemeGallery display text.")) : lumenLocalized(String(localized: "%lld theme files couldn’t load", defaultValue: "\(problems.count) theme files couldn’t load", bundle: .module, comment: "ThemeGallery message; placeholders contain the related value."))
        return VStack(alignment: .leading, spacing: metrics.spacing.s2) {
            LumenBadge(headline, systemImage: "exclamationmark.triangle.fill", tone: .warning)
            ForEach(problems) { problem in
                HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.s3) {
                    Text(problem.file).font(metrics.typography.monoCaption).foregroundStyle(palette[.fgPrimary])
                    Text(problem.reason).font(metrics.typography.caption).foregroundStyle(palette[.fgSecondary])
                    Spacer(minLength: metrics.spacing.s2)
                    Button(lumenLocalized(String(localized: "Move to Trash", bundle: .module, comment: "ThemeGallery control text."))) {
                        do { try store.moveProblemFileToTrash(problem) } catch { libraryError = error.localizedDescription }
                    }
                    .buttonStyle(.lumenBare)
                    .foregroundStyle(palette[.fgLink])
                    .lumenLinkPointer()
                    .font(metrics.typography.caption)
                }
                .textSelection(.enabled)
            }
        }
        // Selectable text inside: give the element its own label rather than letting VoiceOver
        // synthesize one through the selectable Text (which can recurse).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(([headline] + problems.map { "\($0.file): \($0.reason)" }).joined(separator: ". "))
        .accessibilityIdentifier("lumen.theme.problems")
    }

    private func previewAppearance(for theme: LumenTheme) -> LumenAppearance {
        LumenAppearance(isDark: theme.forcedAppearanceIsDark ?? (colorScheme == .dark), isHighContrast: contrast == .increased)
    }
}

/// Keeps long theme names readable even when one action needs the entire flow row.
struct LumenThemeActionLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title).lineLimit(nil).lumenWrapsWithoutTruncating()
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

/// One selectable theme card: the miniature, the name, an appearance badge and, for user themes,
/// a warning when the validator finds problems.
public struct LumenThemeCard: View {
    let theme: LumenTheme
    let registry: LumenRegistry
    let appearance: LumenAppearance
    let isSelected: Bool
    /// Validator findings for a user theme; built-ins pass by construction (tests enforce it).
    var issues: [LumenIssue]
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics
    @State private var isHovered = false

    public init(theme: LumenTheme, registry: LumenRegistry, appearance: LumenAppearance, isSelected: Bool,
                issues: [LumenIssue] = [], action: @escaping () -> Void) {
        self.theme = theme
        self.registry = registry
        self.appearance = appearance
        self.isSelected = isSelected
        self.issues = issues
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: metrics.spacing.s4) {
                LumenThemeMiniature(theme: theme, registry: registry, appearance: appearance)
                    .clipShape(.rect(cornerRadius: metrics.radius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: metrics.radius.md)
                            .strokeBorder(palette[isSelected ? .borderFocus : isHovered ? .borderStrong : .borderSubtle],
                                          lineWidth: isSelected ? metrics.stroke.focus : metrics.stroke.hairline)
                    }
                VStack(alignment: .leading, spacing: metrics.spacing.s1) {
                    HStack(spacing: metrics.spacing.s3) {
                        Text(theme.name).font(metrics.typography.headline).foregroundStyle(palette[.fgPrimary])
                            .lineLimit(nil).lumenWrapsWithoutTruncating()
                        if isSelected {
                            LumenSymbol("checkmark.circle.fill")
                                .foregroundStyle(palette[.accent])
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 0)
                        if !issues.isEmpty {
                            LumenSymbol("exclamationmark.triangle.fill")
                                .foregroundStyle(palette[issues.contains { $0.severity == .error } ? .statusDanger : .statusWarning])
                                .help(issues.prefix(4).map(\.message).joined(separator: "\n"))
                                .accessibilityLabel(lumenLocalized(String(localized: "%lld theme issues", defaultValue: "\(issues.count) theme issues", bundle: .module, comment: "ThemeGallery control text.")))
                        }
                        appearanceBadge
                    }
                    Text(theme.summary)
                        .font(metrics.typography.caption)
                        .foregroundStyle(palette[.fgSecondary])
                        .lineLimit(nil)
                        .lumenWrapsWithoutTruncating()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.lumenPlain).lumenFocusRing()
        .onHover { hovering in
            LumenMotion.perform(.themeHover, metrics: metrics.motion, reduceMotion: reduceMotion) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lumenLocalized(String(localized: "%@ theme", defaultValue: "\(theme.name) theme", bundle: .module, comment: "ThemeGallery control text.")))
        .accessibilityValue([isSelected ? lumenLocalized(String(localized: "Selected", bundle: .module, comment: "ThemeGallery display text.")) : nil, issues.isEmpty ? nil : lumenLocalized(String(localized: "%lld issues", defaultValue: "\(issues.count) issues", bundle: .module, comment: "ThemeGallery message; placeholders contain the related value."))]
            .compactMap(\.self).joined(separator: ", "))
        .accessibilityHint(theme.summary)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("lumen.theme.\(theme.id)")
    }

    @ViewBuilder
    private var appearanceBadge: some View {
        switch theme.forcedAppearanceIsDark {
        case true?:
            Label(lumenLocalized(String(localized: "Dark", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "moon.fill").labelStyle(.iconOnly)
                .foregroundStyle(palette[.fgTertiary]).help(lumenLocalized(String(localized: "Always dark", bundle: .module, comment: "ThemeGallery tooltip.")))
        case false?:
            Label(lumenLocalized(String(localized: "Light", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "sun.max.fill").labelStyle(.iconOnly)
                .foregroundStyle(palette[.fgTertiary]).help(lumenLocalized(String(localized: "Always light", bundle: .module, comment: "ThemeGallery tooltip.")))
        case nil:
            Label(lumenLocalized(String(localized: "Light and Dark", bundle: .module, comment: "ThemeGallery control text.")), systemImage: "circle.lefthalf.filled").labelStyle(.iconOnly)
                .foregroundStyle(palette[.fgTertiary]).help(lumenLocalized(String(localized: "Follows Light and Dark", bundle: .module, comment: "ThemeGallery tooltip.")))
        }
    }
}

/// A miniature app window in `theme`: toolbar, a sidebar with a selected row, a content area
/// with a heading, text lines, a selected row, status chips and an accent button, and a status
/// bar. It draws only core roles, so it works for any app's themes. Colors come from the theme
/// itself (not the active store), so each card looks like its own theme.
// Its sizes are a scaled-down window, not metrics: dividers are deliberate 0.5 pt sub-hairlines.
public struct LumenThemeMiniature: View {
    let theme: LumenTheme
    let registry: LumenRegistry
    let appearance: LumenAppearance

    public init(theme: LumenTheme, registry: LumenRegistry, appearance: LumenAppearance) {
        self.theme = theme
        self.registry = registry
        self.appearance = appearance
    }

    private func c(_ token: LumenToken) -> Color { Color(nsColor: theme.nsColor(token, for: appearance, in: registry)) }

    private func line(_ token: LumenToken, width: CGFloat, height: CGFloat = 3, opacity: Double = 0.85) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(c(token).opacity(opacity)).frame(width: width, height: height)
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                sidebar
                content
            }
            statusBar
        }
        .frame(height: 104)
        .environment(\.colorScheme, appearance.colorScheme)
        .accessibilityHidden(true)
    }

    private var toolbar: some View {
        HStack(spacing: 3) {
            ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                     Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) {
                Circle().fill($0).frame(width: 5, height: 5)
            }
            line(.toolbarForeground, width: 30, height: 3).padding(.leading, 8)
            Spacer()
            RoundedRectangle(cornerRadius: 2).fill(c(.accent)).frame(width: 14, height: 5)
        }
        .padding(.horizontal, 6)
        .frame(height: 14)
        .background(c(.toolbarBackground))
        .overlay(alignment: .bottom) { Rectangle().fill(c(.borderSubtle)).frame(height: 0.5) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            line(.sidebarSecondaryForeground, width: 18, height: 2, opacity: 0.7)
                .padding(.horizontal, 4)
            ForEach(0..<5, id: \.self) { index in
                let selected = index == 1
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(selected ? c(.sidebarAccent) : c(.sidebarSecondaryForeground).opacity(0.6))
                        .frame(width: 5, height: 5)
                    line(selected ? .sidebarForeground : .sidebarSecondaryForeground,
                         width: CGFloat(20 + (index * 7) % 14), opacity: selected ? 1 : 0.8)
                }
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, minHeight: 9, alignment: .leading)
                .background(selected ? c(.sidebarRowSelected) : .clear, in: .rect(cornerRadius: 2))
                .padding(.horizontal, 2)
            }
            Spacer()
        }
        .padding(.top, 5)
        .frame(width: 56)
        .background(c(.sidebarBackground))
        .overlay(alignment: .trailing) { Rectangle().fill(c(.borderDefault)).frame(width: 0.5) }
    }

    /// Whether the registry has the code pack, so the miniature can show syntax colors.
    private var showsCode: Bool { registry.tokens.contains(LumenToken.Code.keyword) }

    @ViewBuilder private var text: some View {
        line(.fgPrimary, width: 54, height: 4, opacity: 1)
        line(.fgSecondary, width: 92)
        line(.fgTertiary, width: 70)
        HStack(spacing: 4) {
            line(.fgPrimary, width: 40)
            line(.fgLink, width: 22)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, minHeight: 9, alignment: .leading)
        .background(c(.bgSelected), in: .rect(cornerRadius: 2))
    }

    /// A few lines of code: keyword, names, a string and a number, with the current line and a
    /// selection, so a theme's syntax colors show in the gallery (apps that register `.code`).
    private var code: some View {
        let rows: [[(LumenToken, CGFloat)]] = [
            [(LumenToken.Code.keyword, 14), (LumenToken.Code.function, 26), (LumenToken.Code.punctuation, 4)],
            [(LumenToken.Code.keyword, 10), (LumenToken.Code.variable, 16), (LumenToken.Code.operator, 4), (LumenToken.Code.string, 30)],
            [(LumenToken.Code.variable, 18), (LumenToken.Code.operator, 4), (LumenToken.Code.number, 10)],
            [(LumenToken.Code.comment, 44)],
        ]
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 3) {
                    line(LumenToken.Code.lineNumber, width: 5, height: 2.5, opacity: 0.8)
                    ForEach(rows[index].indices, id: \.self) { part in
                        line(rows[index][part].0, width: rows[index][part].1, height: 2.5, opacity: 1)
                    }
                }
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, minHeight: 8, alignment: .leading)
                .background(index == 1 ? c(LumenToken.Code.currentLine) : index == 2 ? c(LumenToken.Code.selection) : .clear,
                            in: .rect(cornerRadius: 1.5))
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsCode { code } else { text }
            HStack(spacing: 3) {
                ForEach([(LumenToken.statusSuccess, LumenToken.statusSuccessBackground),
                         (.statusWarning, .statusWarningBackground), (.statusDanger, .statusDangerBackground),
                         (.statusInfo, .statusInfoBackground)], id: \.0) { tone, ground in
                    line(tone, width: 10, height: 2.5, opacity: 1)
                        .padding(.horizontal, 3)
                        .frame(height: 7)
                        .background(c(ground), in: .capsule)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Spacer()
                line(.fgSecondary, width: 16, height: 2.5)
                    .padding(.horizontal, 4)
                    .frame(height: 9)
                    .background(c(.bgInset), in: .rect(cornerRadius: 2))
                line(.accentFilledForeground, width: 16, height: 2.5, opacity: 1)
                    .padding(.horizontal, 4)
                    .frame(height: 9)
                    .background(c(.accentFilled), in: .rect(cornerRadius: 2))
                    .overlay { RoundedRectangle(cornerRadius: 3).stroke(c(.borderFocus), lineWidth: 1).padding(-2) }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c(.bgCanvas))
    }

    private var statusBar: some View {
        HStack(spacing: 4) {
            Circle().fill(c(.statusSuccess)).frame(width: 4, height: 4)
            line(.fgTertiary, width: 26, height: 2.5, opacity: 0.6)
            Spacer()
            line(.fgTertiary, width: 14, height: 2.5, opacity: 0.6)
        }
        .padding(.horizontal, 6)
        .frame(height: 9)
        .background(c(.bgWindow))
        .overlay(alignment: .top) { Rectangle().fill(c(.borderDefault)).frame(height: 0.5) }
    }
}

#Preview("Theme gallery") {
    LumenThemeGallery(store: LumenThemeStore(registry: .core, configuration: .init(appName: "LumenPreview"),
                                            themes: LumenRegistry.core.galleryThemes, persistsSelection: false))
        .padding(Lumen.Space.s8)
        .frame(width: 720)
}

#Preview("Miniatures, light and dark") {
    HStack(spacing: Lumen.Space.s6) {
        ForEach(LumenRegistry.core.galleryThemes) { theme in
            VStack(spacing: Lumen.Space.s4) {
                LumenThemeMiniature(theme: theme, registry: .core, appearance: .light).frame(width: 200)
                LumenThemeMiniature(theme: theme, registry: .core, appearance: .dark).frame(width: 200)
            }
        }
    }
    .padding(Lumen.Space.s8)
}

/// Validation results per theme, so the gallery doesn't re-validate every user theme on every
/// render. Keyed by the whole theme: an edited file is a different key.
private final class IssueCache {
    private var entries: [LumenTheme: [LumenIssue]] = [:]

    func issues(for theme: LumenTheme, in registry: LumenRegistry) -> [LumenIssue] {
        if let cached = entries[theme] { return cached }
        if entries.count > 64 { entries.removeAll() }
        let found = LumenValidator.issues(for: theme, in: registry)
        entries[theme] = found
        return found
    }
}
