# Reordering on macOS 27

## SDK declarations

Package.swift requires macOS 27.0. Reordering uses these APIs directly without
availability branches.

Source: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`.

The declarations below describe the platform APIs used by the shared behavior, which uses
the single-collection Identifiable overload. Note that
`ReorderDifference` exposes sources and a destination but no public initializer.
Tests can construct a `Destination` and exercise the shared move calculation with
source IDs without inventing a difference initializer.

### DynamicViewContent and View reorder modifiers

SDK lines 13122–13149:

```swift
extension SwiftUICore.DynamicViewContent {
  @available(iOS 27.0, macOS 27.0, watchOS 27.0, visionOS 27.0, *)
  @available(tvOS, unavailable)
  nonisolated public func reorderable() -> some SwiftUICore.DynamicViewContent<Self.Data>
  
  @available(iOS 27.0, macOS 27.0, watchOS 27.0, visionOS 27.0, *)
  @available(tvOS, unavailable)
  nonisolated public func reorderable(collectionID: some Hashable & Sendable) -> some SwiftUICore.DynamicViewContent<Self.Data>
  
}
extension SwiftUICore.View {
  @available(iOS 27.0, macOS 27.0, watchOS 27.0, visionOS 27.0, *)
  @available(tvOS, unavailable)
  nonisolated public func reorderContainer<Item>(for item: Item.Type, isEnabled: Swift.Bool = true, move: @escaping (_ difference: SwiftUI.ReorderDifference<Item.ID, SwiftUI.ReorderableSingleCollectionIdentifier>) -> ()) -> some SwiftUICore.View where Item : Swift.Identifiable, Item.ID : Swift.Sendable
  
  @available(iOS 27.0, macOS 27.0, watchOS 27.0, visionOS 27.0, *)
  @available(tvOS, unavailable)
  nonisolated public func reorderContainer<Item, CollectionID>(for item: Item.Type, in collectionID: CollectionID.Type, isEnabled: Swift.Bool = true, move: @escaping (_ difference: SwiftUI.ReorderDifference<Item.ID, CollectionID>) -> ()) -> some SwiftUICore.View where Item : Swift.Identifiable, CollectionID : Swift.Hashable, CollectionID : Swift.Sendable, Item.ID : Swift.Sendable
  
  @available(iOS 27.0, macOS 27.0, watchOS 27.0, visionOS 27.0, *)
  @available(tvOS, unavailable)
  nonisolated public func reorderContainer<Item, ItemID>(for item: Item.Type, itemID: Swift.KeyPath<Item, ItemID>, isEnabled: Swift.Bool = true, move: @escaping (_ difference: SwiftUI.ReorderDifference<ItemID, SwiftUI.ReorderableSingleCollectionIdentifier>) -> ()) -> some SwiftUICore.View where ItemID : Swift.Hashable, ItemID : Swift.Sendable
  
  @available(iOS 27.0, macOS 27.0, watchOS 27.0, visionOS 27.0, *)
  @available(tvOS, unavailable)
  nonisolated public func reorderContainer<Item, ItemID, CollectionID>(for item: Item.Type, itemID: Swift.KeyPath<Item, ItemID>, in collectionID: CollectionID.Type, isEnabled: Swift.Bool = true, move: @escaping (_ difference: SwiftUI.ReorderDifference<ItemID, CollectionID>) -> ()) -> some SwiftUICore.View where ItemID : Swift.Hashable, ItemID : Swift.Sendable, CollectionID : Swift.Hashable, CollectionID : Swift.Sendable
  
}
```

### Difference and destination model

SDK lines 13150–13172:

```swift
@available(anyAppleOS 27.0, *)
public struct ReorderableSingleCollectionIdentifier : Swift.Hashable, Swift.Sendable {
  public static func == (a: SwiftUI.ReorderableSingleCollectionIdentifier, b: SwiftUI.ReorderableSingleCollectionIdentifier) -> Swift.Bool
  public func hash(into hasher: inout Swift.Hasher)
  public var hashValue: Swift.Int {
    get
  }
}
@available(anyAppleOS 27.0, *)
public struct ReorderDifference<ItemID, CollectionID> {
  public struct Destination {
    @frozen public enum Position {
      case before(ItemID)
      case end
    }
    public var collectionID: CollectionID
    public var position: SwiftUI.ReorderDifference<ItemID, CollectionID>.Destination.Position
    public init(position: SwiftUI.ReorderDifference<ItemID, CollectionID>.Destination.Position, collectionID: CollectionID)
    public init(position: SwiftUI.ReorderDifference<ItemID, CollectionID>.Destination.Position) where CollectionID == SwiftUI.ReorderableSingleCollectionIdentifier
  }
  public var sources: [ItemID]
  public var destination: SwiftUI.ReorderDifference<ItemID, CollectionID>.Destination
}
```

### DropSession destination lookup

SDK lines 13215–13226:

```swift
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension SwiftUI.DropSession {
  @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
  @available(tvOS, unavailable)
  @available(watchOS, unavailable)
  nonisolated public func reorderDestination<Item, CollectionID>(for item: Item.Type, in collectionID: CollectionID.Type = ReorderableSingleCollectionIdentifier.self) -> SwiftUI.ReorderDifference<Item.ID, CollectionID>.Destination? where Item : Swift.Identifiable
  @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
  @available(tvOS, unavailable)
  @available(watchOS, unavailable)
  nonisolated public func reorderDestination<Item, ItemID, CollectionID>(for item: Item.Type, itemID: Swift.KeyPath<Item, ItemID>, in collectionID: CollectionID.Type = ReorderableSingleCollectionIdentifier.self) -> SwiftUI.ReorderDifference<ItemID, CollectionID>.Destination?
}
```

### Swipe actions

SDK lines 21612–21629:

```swift
@available(iOS 15.0, macOS 12.0, watchOS 8.0, *)
@available(tvOS, unavailable)
extension SwiftUICore.View {
  nonisolated public func swipeActions<T>(edge: SwiftUICore.HorizontalEdge = .trailing, allowsFullSwipe: Swift.Bool = true, @SwiftUICore.ContentBuilder content: () -> T) -> some SwiftUICore.View where T : SwiftUICore.View
  
}
@available(iOS 27.0, macOS 27.0, watchOS 27.0, visionOS 27.0, *)
@available(tvOS, unavailable)
extension SwiftUICore.View {
  nonisolated public func swipeActions(edge: SwiftUICore.HorizontalEdge = .trailing, allowsFullSwipe: Swift.Bool = true, @SwiftUICore.ContentBuilder content: () -> some View, onPresentationChanged: @escaping (Swift.Bool) -> Swift.Void) -> some SwiftUICore.View
  
}
@available(iOS 27.0, macOS 27.0, watchOS 27.0, visionOS 27.0, *)
@available(tvOS, unavailable)
extension SwiftUICore.View {
  nonisolated public func swipeActionsContainer() -> some SwiftUICore.View
  
}
```

## Component mutation interfaces

| Component | Existing behavior | Mutation interface |
|---|---|---|
| `LumenDocumentTabBar` | Native reorder within a bar; cross-pane drags carry tab ID and optional source pane | Immutable tab input plus public `LumenTabActions.dropTab` callback; internal `moveTab` preserves source-pane routing |
| `LumenSidebarSwitcher` | Native reorder within a dock; external pane drops and menu moves left/right | Optional encoded arrangement binding through `LumenToolLayout` |
| `LumenSidebarPaneGrid` | Native reorder within its grid; drag source for docking panes | Encoded arrangement binding preserving hidden and docked state |
| `LumenListEditor` | Add, remove, select; no drag reorder | Array binding; existing row Remove button and context-menu action |
| `LumenChecklistTree` | Check leaves/subtrees and select; no drag reorder | Immutable node input; checked/selection bindings only |
| `LumenPanelDeck` / `LumenPanelDeckControls` | Deck model and selection/show-hide controls; no drag reorder | Immutable deck input; selection/presentation bindings only |
| `LumenThemeGallery` | Imports dropped JSON URLs; no drag reorder | Theme store import |

## Gesture routing

`LumenReorderBehavior<Item>` uses `reorderContainer(for:isEnabled:move:)` and
`ReorderDifference<String, ReorderableSingleCollectionIdentifier>`; each collection's
`ForEach` uses `reorderable()`. The native placeholder supplies the same insertion
feedback, and changes use `metrics.motion.fastCurve` through `LumenMotion`.
`LumenReorderMove` resolves stable IDs to `IndexSet` and a pre-removal destination,
then uses `move(fromOffsets:toOffset:)`. Self, adjacent, and stale-ID drops do nothing.
Multi-item moves retain collection order, including when source IDs arrive unsorted.

- Document tabs within one bar: native reorder, translated into the existing
  `LumenTabActions.dropTab` callback. The internal `moveTab` callback retains its
  source pane and takes precedence when present. No public signatures change.
- Sidebar pane grid within its grid: native reorder writes the existing encoded
  arrangement binding and preserves hidden/docked state. Tiles display that order.
- Sidebar switcher within its dock: the same behavior reorders visible panes while
  preserving hidden slots and selection. Context-menu moves retain their existing path.
- Grid-to-dock and tabs between editor panes: existing prefixed String payloads and
  docking/move mutations remain. `dragContainer` exports the payload outside the
  reorder container; the enclosing `dropDestination` handles incoming external
  drags and uses `DropSession.reorderDestination` for the insertion anchor.
  There is no shared container across independently composed regions, so these
  gestures do not use a local `ReorderDifference`.

The extra SDK declarations used for external drag routing are:

```swift
nonisolated public func dragContainer<ItemID, Item, Data>(for itemType: Item.Type = Item.self, itemID: Swift.KeyPath<Item, ItemID>, in namespace: SwiftUICore.Namespace.ID? = nil, _ payload: @escaping (_ draggedItemIDs: Swift.Array<ItemID>) -> Data) -> some SwiftUICore.View where ItemID : Swift.Hashable, ItemID : Swift.Sendable, Item : CoreTransferable.Transferable, Item == Data.Element, Data : Swift.Collection
nonisolated public func dropDestination<T>(for type: T.Type = T.self, isEnabled: Swift.Bool = true, action: @escaping (_ items: [T], _ session: SwiftUI.DropSession) -> Swift.Void) -> some SwiftUICore.View where T : CoreTransferable.Transferable
```

These declarations were checked in the installed SDK interface. The composition
follows Apple's “Reordering items in lists, stacks, grids, and custom layouts”:
external drop handling encloses the reorder container so local gestures use native
reordering. Offscreen rendering omits the interactive container.

`LumenListEditor`, `LumenChecklistTree`, and `LumenPanelDeckControls`
do not expose drag reordering. The list editor's rows are `HStack`s
inside a `VStack`, not SwiftUI `List` rows, so no swipe Remove is added. Existing
Remove buttons/context menus remain. Theme-gallery file import is unchanged.
