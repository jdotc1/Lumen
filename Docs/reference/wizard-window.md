# Wizard / first-run window

`LumenWizardWindow` is the macOS Installer / Setup Assistant shape: a titled window, a leading
step list, the current page's title and body, and a full-width bottom bar. The body hugs its
content first and scrolls vertically when it exceeds the available space. Pair the root with
`.lumenPaletteRoot()` and the scene with `.lumenWizardScene()`, which uses a titled window and
`.windowResizability(.contentSize)`. The natural content size is about 640 × 460 at standard
density and grows with text scale.

Supply `[LumenWizardPage]` (`id`, `title`, optional `systemImage`) and a `Binding<Int>` named
`current`. Indices are clamped into the page array; an empty array draws an empty state. Each
completed page has a checkmark and can be clicked to go back. The current page is emphasized;
future pages are tertiary and cannot be selected. `LumenWizardStep` remains the separate,
unchanged single-step sheet picker.

Cancel is the leading quiet action with `.cancelAction`. Go Back is quiet and disabled on the
first page. Continue is the trailing primary `.defaultAction`, disabled by `canContinue: false`.
On the final page it reads `finishTitle` (default `"Done"`) and calls `onFinish`. The host supplies
both `onCancel` and `onFinish`, including any persistence or window dismissal.

`LumenWizardSummary([(label: String, value: String)])` lays out review rows on a settings-style
card, labels leading and values trailing. Values wrap instead of truncating.

`WindowKind.wizard` checks for the leading step list, exactly one current page for a nonempty
wizard, the full-width bottom bar and its trailing default Continue/finish action. It also
checks region bounds and overlaps, uses the shared truncation/overflow diagnostics, and includes
`narrowSizing` at the requested width. Run it at the natural content size and 1.3 text scale.

The Catalog's Wizard Window page follows Menu Bar Panel. It opens the real scene and embeds
the same wizard in a preview scaled to fit the column, preserving its aspect ratio and never
exceeding native size. The preview has no horizontal scroll. Welcome, Choose a Folder, Options
and Summary demonstrate local sample choices; no folders are read or modified. Cancel and Done dismiss the real window. In the inline demo,
Cancel returns to Welcome, and Done returns there with a completion message.
