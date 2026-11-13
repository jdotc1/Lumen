# Adopt Lumen in a small SwiftUI app

Use the `LumenUI` library product from this package, with a macOS 27 deployment target.
For a local package dependency, use the package directory containing Lumen's `Package.swift`;
add `.product(name: "LumenUI", package: "Lumen")` to your app target's dependencies.
For a remote dependency, pin a revision that contains `LumenPageHeader`; v0.60.0 does not contain it.
No app-specific theme pack is required: `.core` supplies the standard palette and metrics.

The complete example below is compiled as part of `LumenUITests` in
`Tests/LumenUITests/LumenWorkspaceExamples.swift`. Copy both blocks into one Swift file in your app
and add `@main` to `ExampleSmallApp`. The test target deliberately omits that attribute so it
can compile the app's scene declarations without launching the app. The example infers `.core`
and token roles from the component APIs; import `LumenTokens` as well when naming token types directly.

Install the store once before constructing views. Apply `.lumenPaletteRoot()` to every window,
including Settings, and `.lumenDensityRoot()` if the app exposes Lumen's density preference.
The palette root resolves theme metrics; avoid an unconditional `.lumenMetrics(.standard)` here
unless you intentionally want to override the theme's metrics.

```swift
import SwiftUI
import LumenUI

struct ExampleSmallApp: App {
    init() {
        LumenThemeStore.install(LumenThemeStore(
            registry: .core,
            configuration: .init(appName: "SmallApp")
        ))
    }

    var body: some Scene {
        WindowGroup("Small app") {
            ExampleWorkspace()
                .lumenPaletteRoot()
                .lumenDensityRoot()
        }
        .defaultSize(width: 1000, height: 660)

        Settings {
            LumenSettingsSidebarView([
                LumenSettingsCategory(id: "appearance", title: "Appearance",
                                      systemImage: "paintpalette", hue: .hueViolet) {
                    LumenAppearanceSettings()
                }
            ])
            .lumenPaletteRoot()
            .lumenDensityRoot()
        }
        .lumenSettingsScene()
    }
}

struct ExampleWorkspace: View {
    @State private var workspace = "library"
    @State private var librarySelection: String? = "library.documents"
    @State private var reviewSelection: String? = "review.inbox"
    @State private var busy = false
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                ExampleSidebar(workspace: $workspace,
                                librarySelection: $librarySelection,
                                reviewSelection: $reviewSelection)
                    .lumenSidebarColumn()
                ExampleContent(title: selectedTitle, busy: $busy)
                    .lumenColumn(min: 320)
            }
            LumenStatusBar {
                if busy {
                    ProgressView().controlSize(.small)
                    Text("Refreshing").lumenNeverTruncates("Refreshing")
                    Button("Cancel") { busy = false }
                } else {
                    Text("Ready").lumenNeverTruncates("Ready")
                }
                Spacer(minLength: metrics.spacing.s4)
                Text(workspace == "library" ? "Library" : "Review")
            }
            .padding(metrics.spacing.s4)
        }
        .background(palette[.bgCanvas])
    }

    private var selectedTitle: String {
        let items = workspace == "library" ? ExampleSidebar.libraryItems : ExampleSidebar.reviewItems
        let selected = workspace == "library" ? librarySelection : reviewSelection
        return items.first(where: { $0.id == selected })?.title ?? "Select a destination"
    }
}

struct ExampleContent: View {
    let title: String
    @Binding var busy: Bool
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s6) {
            LumenPageHeader(title, subtitle: "Your current workspace", systemImage: "folder") {
                Button("Refresh") { busy = true }
                    .disabled(busy)
            }
            LumenEmptyState(systemImage: "doc", title: "No documents",
                            message: "Import a document to get started.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(metrics.spacing.s6)
    }
}
```

The sidebar used above is also complete. Workspace and destination selections live in the window
root, so changing workspace retains the previous destination in the other workspace.

```swift
struct ExampleSidebar: View {
    @Binding var workspace: String
    @Binding var librarySelection: String?
    @Binding var reviewSelection: String?

    static let libraryItems: [LumenSourceListItem] = [
        .init(id: "library.documents", title: "Documents", systemImage: "doc"),
        .init(id: "library.recent", title: "Recent", systemImage: "clock"),
        .init(id: "library.favorites", title: "Favorites", systemImage: "star"),
        .init(id: "library.collections", title: "Collections", systemImage: "folder"),
        .init(id: "library.archive", title: "Archive", systemImage: "archivebox")
    ]
    static let reviewItems: [LumenSourceListItem] = [
        .init(id: "review.inbox", title: "Inbox", systemImage: "tray"),
        .init(id: "review.assigned", title: "Assigned", systemImage: "person"),
        .init(id: "review.completed", title: "Completed", systemImage: "checkmark.circle"),
        .init(id: "review.reports", title: "Reports", systemImage: "chart.bar")
    ]

    var body: some View {
        VStack(spacing: 0) {
            LumenSidebarSection("Workspace") {
                LumenSidebarSwitcher(selection: $workspace, items: [
                    .init(id: "library", title: "Library", systemImage: "books.vertical"),
                    .init(id: "review", title: "Review", systemImage: "checklist")
                ], shortcuts: false)
            }
            if workspace == "library" {
                LumenSidebarSection("Library") {
                    LumenSourceList(Self.libraryItems, selection: $librarySelection)
                }
            } else {
                LumenSidebarSection("Review") {
                    LumenSourceList(Self.reviewItems, selection: $reviewSelection)
                }
            }
        }
    }
}
```

## Reuse the scales and components

Read `lumenMetrics` for spacing and type. The standard grid includes `spacing.s2` = 4 pt,
`spacing.s4` = 8 pt and `spacing.s6` = 16 pt. These are roles, so avoid copying their numeric
values into every view. `lumenSidebarColumn()` resolves the shared width range for the current
text scale; its standard unscaled range is 200 / 240 / 320 pt (minimum / ideal / maximum).
If your host truly requires a 214 pt ideal, use the explicit `min:ideal:max:` overload once;
those explicit values remain points rather than scaling automatically.

`LumenPageHeader` is a plain page title with an optional subtitle, optional symbol and trailing
actions. At narrow widths its actions move below the title and primary text wraps instead of
being truncated. `LumenDetailHeader` remains the richer object-detail presentation with a tile,
metadata, categories and permissions. Use native buttons in the page header; no custom window
chrome is required.

`LumenStatusBar` already takes arbitrary view content, including an indeterminate `ProgressView`
and Cancel button. Its minimum height follows `metrics.layout.minimumHitTarget` (24 pt at the
standard scale), rather than a fixed 28 pt height. Let it grow with content and text size.
The example's boolean demonstrates state changes; in a real app, Cancel must request cancellation
of the actual task and the task must observe that request before updating completion state.

The empty state and Settings are complete Lumen components. Keep domain data and task ownership
in your app; Lumen supplies their presentation. For a smaller starting point, see
`minimal-palette.md`; for selection design, see `multi-workspace-sidebar.md`.

## About panel

Add `.commands { LumenAboutCommands() }` to your main scene to fill Apple's standard About panel.
Pass `bundle`, `copyrightHolder`, `profileURL`, or `credits` to customize its contents. App name,
marketing version and build come from the host bundle; `LumenLibrary.version` identifies the linked
library. The GitHub profile is clickable, and credits use the native small system font and label
color. For AppKit menus, call `LumenAboutPanel.show(...)` on the main actor; use
`LumenAboutPanel.options(...)` to obtain the dictionary without presenting any UI.

To credit people or projects by name, pass `credits: [LumenAboutCredit]` (and optionally
`creditsHeading:`) instead of a credits string. Each credit is its own centered line; one with a
`url` is a clickable link and one without is plain text. A nonempty heading follows a blank line;
an empty list adds no heading. The same shape works on `LumenAboutCommands`, `show` and `options`:

```swift
.commands {
    LumenAboutCommands(credits: [
        LumenAboutCredit(name: "Swift Collections", url: URL(string: "https://github.com/apple/swift-collections")),
        LumenAboutCredit(name: "The beta testers"),
    ], creditsHeading: "Acknowledgements")
}
```

To include the host's seven-character commit, add this one-line Run Script build phase after the
app's Info.plist is generated (declare the built plist as an input/output and permit Git source access):

```sh
/usr/libexec/PlistBuddy -c "Add :LumenGitCommit string $(git -C "$SRCROOT" rev-parse --short=7 HEAD)" "$TARGET_BUILD_DIR/$INFOPLIST_PATH" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :LumenGitCommit $(git -C "$SRCROOT" rev-parse --short=7 HEAD)" "$TARGET_BUILD_DIR/$INFOPLIST_PATH"
```

Omit the key to omit the commit line. The helper displays the first seven characters of a supplied
commit. `Scripts/release.sh` updates and commits the library version before its release checks.
