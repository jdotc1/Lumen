# App Intents

`LumenIntents` is an optional library product depending on `LumenUI`. Only clients of this product link Apple's
AppIntents framework; `LumenUI`, `LumenTokens` and `LumenConformance` gain no dependency on it.
The floor remains macOS 27.0, with no availability branches.

## Configuration

Keep one factory returning `[LumenCommand]` for menus, the command palette and intents. During
app initialization, call `LumenIntentCommands.configure { appCommands() }`. Register custom
`LumenGlyph` values before configuring. Use explicit stable command IDs: title-derived default
IDs are unsuitable for shortcuts that must survive renaming or localization.

In the app target, include the package and declare the literal discovery metadata:

```swift
import AppIntents
import LumenIntents

struct MyIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [LumenIntentsPackage.self] }
}

struct MyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LumenCommandIntent(),
                    phrases: ["Run \(\.$command) in \(.applicationName)"],
                    shortTitle: "Run Command", systemImageName: "command")
    }
}
```

Call `MyShortcuts.updateAppShortcutParameters()` after configuring, and when the available command
identities or titles change. The factory must be available when the system queries entities, not
only after a view appears. The Catalog installs its factory from `App.init`: Use Lumen Theme,
Use Midnight Theme and Use Ultraviolet Theme reuse `CatalogPalette.themes(store:)`. Their menu
is in `CatalogIntentMenu`; all three use the app's theme store and work without a focused window.

## Contract and limits

- `LumenCommandIntent` is a concrete, foreground App Intent with static “Run Lumen Command”
  metadata and a `LumenCommandEntity` parameter. The entity query lists commands, searches titles
  and resolves saved IDs. No per-command intent type or `AppEnum` case is necessary.
- Entity titles and symbol names come directly from `LumenCommand`. SF Symbols stay system images.
  Lumen glyphs use the existing `LumenIconTile` renderer and travel as PNG display images, including
  their hue, in light appearance at 32 pt / 2×. These are rendered images, not dynamic vector
  symbols or appearance-adaptive tiles. A missing Lumen glyph or render fails explicitly.
- The top-level shortcut tile's title, SF Symbol and Siri phrase must be literals in the host
  provider. A runtime array cannot manufacture static shortcut tiles or per-command intent titles.
  Keep the provider declaration in the host so Apple's metadata extractor can see the literals;
  a factory helper would obscure the very metadata that must remain static.
- Entities hold metadata only. Execution looks up the current command by ID on the main actor,
  checks `isEnabled`, and calls its original `perform` closure. Disabled commands remain visible
  as choices but cannot execute. Removed, duplicate and unconfigured commands fail explicitly.
- The host owns routing, initialization and localization. A foreground intent does not promise
  that a particular document or key window exists. `LumenViewCommands` has focused bindings rather
  than an exportable list; apps must supply command entries and a deliberate window policy for
  such operations. Do not retain transient view snapshots as the command provider.
- This adapter carries no command arguments, asynchronous result payloads, dialogs, undo policy,
  keyboard shortcut registration, or semantic App Intent schemas. It does not automatically index
  each entity as an independent Spotlight item. Discovery depends on the host's extracted and
  bundled App Intents metadata and the system's registration of that host app.
## Package metadata

Apple's [AppIntentsPackage documentation](https://developer.apple.com/documentation/appintents/appintentspackage)
describes explicit package inclusion for framework intents. Extracted build metadata must be
bundled with the host application; system registration determines discovery in Siri, Spotlight
and Shortcuts.
