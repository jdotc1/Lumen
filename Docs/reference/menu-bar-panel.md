# Menu bar panel

The menu bar and expanded-window lifecycle belong to macOS. Lumen draws the panel inside a
SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`. Deployment is macOS 27.0.

## Native expanded interfaces

Inspected the installed macOS 27.2 SDK (Xcode build 27B5019j), AppKit's `NSStatusItem.h` and
`NSStatusItemExpandedInterfaceSession.h`, its exported Swift symbol graph, and SwiftUI's
`MenuBarExtra` interface. The exact imported Swift declarations are:

```swift
// All introduced in macOS 27.0.
weak var expandedInterfaceDelegate: (any NSStatusItemExpandedInterfaceDelegate)? { get set }
var expandedInterfaceSession: NSStatusItemExpandedInterfaceSession? { get }

protocol NSStatusItemExpandedInterfaceDelegate : NSObjectProtocol
func statusItem(_ statusItem: NSStatusItem, didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession)
func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool)

class NSStatusItemExpandedInterfaceSession
func cancel()
```

The delegate must show its expanded interface when the session begins and dismiss it when the
session ends. Calling `cancel()` ends tracking when another action closes the interface. These
APIs let a custom status-item window participate in system menu tracking and navigation; an
item with an `NSMenu` does not receive the delegate callbacks.

`MenuBarExtra` exposes content/label builders and an optional `isInserted: Binding<Bool>`, but no
public `NSStatusItem` handle or delegate bridge. These AppKit APIs therefore cannot be used
through the supported SwiftUI interface without replacing or reaching into its presentation.
Lumen does neither: no custom status item, window positioning, event monitor or presentation.

Apple references: https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate
and https://developer.apple.com/documentation/swiftui/menubarextra.

## Panel and glyph APIs

`LumenMenuBarPanel` accepts an optional title, trailing `accessory` builder, scrolling `content`
builder, optional `footer` builder and `showsFooter`. Its standard footer invokes the environment's
`openSettings` action and terminates the host application on Quit. It does not create a window.
The width defaults to `LumenLayout.popoverWidth` (280 pt, matching the existing popovers).
`maximumHeight` defaults to `LumenLayout.panelMaxHeight` (480 pt) and bounds the whole panel;
the panel hugs its measured header, content and footer below that limit. The scrolling viewport
is capped at the supplied maximum minus the measured header and footer (including dividers).
Header and footer stay outside the scroll view; a smaller host can further constrain the viewport.
The existing popover initializer defaults remain unchanged.

`LumenStatusGlyph("lumen.lens", attention: .badge).image` supplies the extra's label image.
`templateImage()` also returns the AppKit template, or nil for an unknown symbol. Attention is
`.none`, `.badge` (dot), or `.attention` (exclamation mark); all marks are monochrome.

`WindowKind.menuBarPanel` uses the shared truncation/overflow findings, checks that supplied
header/footer regions exist and fit, and permits vertical overflow only inside scrolling content.
It does not apply native title-bar or traffic-light rules to a menu bar panel.

## Catalog

The Catalog installs a `MenuBarExtra` while it runs, labeled Lumen Agent. It uses the same
`CatalogMenuBarPanel` as the Menu Bar Panel page: sync status, two local demo toggles and recent
file activity. The demo does not watch or modify files. The system owns presentation and dismissal.
