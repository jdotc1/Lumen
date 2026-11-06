# Document window

The package targets macOS 27.0 directly: no `FileDocument` fallback or availability branch.

## Platform and launch

The selected SDK is **macOS 27.2**, at
`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.2.sdk`.
The exact excerpts below come from
`System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
inside that SDK.

`Document`, `ReadableDocument`, `WritableDocument`, `DocumentReader`, `DocumentWriter`,
`FileWrapperDocumentReader`, `FileWrapperDocumentWriter` and `URLDocumentConfiguration` are
available on macOS 27.0. The shown `NewDocumentButton` initializer is available on macOS 15.0.
`DocumentGroup` accepts the new `Document` protocol on macOS 27.0.

**`DocumentLaunchView` is explicitly unavailable on macOS.** The launch architecture
uses Lumen's existing welcome component as its own document picker window. New and Open feed
`DocumentGroup`; SwiftUI owns the real document windows and their save, revert and close lifecycle.

## Native document window tabs

Document windows use the system's native window tabbing, with the default `.automatic` behavior
honoring the user's preference. System merge, detach and overview operate on real windows.
`LumenDocumentWindow` does not draw `LumenDocumentTabBar`; that component remains available for
in-window workspace content tabs. This keeps one selection model per document and lets the system
own save and close for each window. No global tabbing setting is changed.

## Layout contract

The document inspector reuses `LumenUtilityLayout.visiblePanels` with no sidebar: the optional
inspector yields before content and restores when space returns. An explicitly hidden inspector
remains hidden, and resizing never overwrites requested visibility. Real content and the mounted
inspector occupy `HSplitView` panes using `lumenWorkspaceRegion(shown:width:)`. Available width is
measured only on the flexible, clipped outer wrapper; the root minimum sits outside that wrapper.

## Public API and Catalog example

`LumenDocumentWindow(title:isModified:onRename:inspectorPresented:minimumSize:content:inspector:statusBar:topTrailing:)`
composes `LumenUtilityWindow` with no sidebar. The title binding feeds an editable field in the
native unified top bar, beside an Unmodified/Edited indicator driven by `isModified`. The host supplies
actual document naming and edit state. With `onRename`, title clicks invoke the supplied native
rename action; without it, the title field edits the binding directly. `inspectorWidth(_:)` and `contentMinimumWidth(_:)` configure
layout. `.lumenDocumentScene()` applies the shared native window chrome. Optional region builders
can be omitted; an optional inspector visibility binding preserves explicit intent during resizing.

`WindowKind.document` uses the existing window-structure checker with the stable identifier
`lumen.windowStructure.document`. It requires unified placement and adds independent missing-title
and missing-modified-state findings using `LumenDocumentChromeEntry` / `LumenDocumentChromeKey`.
Other window kinds retain their existing results.

The Catalog's Document Window entry opens `LumenWelcomeView`. Its closure-based actions use the
`newDocument(CatalogTextDocument())` environment action and an `NSOpenPanel` followed by
`openDocument(at:)`; these fit the existing welcome action model without embedding a
`NewDocumentButton`. The welcome and editor publish the same typed creation action through the
Catalog's existing focused New command, retaining New Window in the Catalog and the workspace's
existing action. `CatalogTextDocument` is observable and conforms to the new `Document`
protocol. `FileWrapperDocumentReader<String>` and `FileWrapperDocumentWriter<String>` serialize
UTF-8 text; `apply` and `snapshot` run on the main actor. The document group creates the model
from `URLDocumentConfiguration`, then supplies it to the editor. A native window/document bridge
reports the system document title and dirty state and forwards title clicks to
`NSDocument.rename(_:)`, preserving system naming and save ownership. The Catalog provides generic
sample content.

## Native API declarations

### Welcome environment actions

The welcome uses these macOS environment actions (interface lines 4159–4167 and
4185–4193). The open panel supplies the URL; the macOS 27 new action supplies an instance of the
`ReadableDocument` type handled by the document group.

```swift
@available(macOS 13.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
@_Concurrency.MainActor public struct OpenDocumentAction {
  @_Concurrency.MainActor public func callAsFunction(at url: Foundation.URL) async throws
}
@available(macOS 27.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension SwiftUI.NewDocumentAction {
  @_Concurrency.MainActor @preconcurrency public func callAsFunction<D>(_ newDocument: @autoclosure @escaping @Sendable () -> sending D) where D : SwiftUI.ReadableDocument
}
```

### DocumentGroup with the new Document protocol

Interface lines 2268–2273:

```swift
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
extension SwiftUI.DocumentGroup where Document : Observation.Observable, Document : SwiftUI.Document, Document.Reader.Source == Foundation.URL, Document.Writer.Destination == Foundation.URL {
  nonisolated public init(allowCreating: Swift.Bool = true, @SwiftUICore.ContentBuilder editor: @escaping (_ document: Document) -> Content, makeDocument: @escaping @_Concurrency.MainActor (_ configuration: SwiftUI.URLDocumentConfiguration, _ context: SwiftUI.DocumentCreationContext) async throws -> Document)
}
```

### Document protocols and file-wrapper adapters

Interface lines 2046–2132:

```swift
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public protocol Document : SwiftUI.ReadableDocument, SwiftUI.WritableDocument {
}
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public protocol DocumentReader<Snapshot> {
  associatedtype Snapshot
  associatedtype Source = Foundation.URL
  #if compiler(>=5.3) && $AsyncExecutionBehaviorAttributes
  @concurrent func read(from source: sending Self.Source, progress: consuming Foundation.Subprogress) async throws -> sending Self.Snapshot
  #endif
}
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public protocol DocumentWriter<Snapshot> {
  associatedtype Snapshot
  associatedtype Destination = Foundation.URL
  #if compiler(>=5.3) && $AsyncExecutionBehaviorAttributes
  @concurrent func write(snapshot: sending Self.Snapshot, to destination: sending Self.Destination, previous: sending Self.Snapshot?, progress: consuming Foundation.Subprogress) async throws
  #endif
}
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public protocol ReadableDocument : AnyObject {
  associatedtype Reader : SwiftUI.DocumentReader
  typealias ReadConfiguration = SwiftUI.DocumentReadConfiguration
  static var readableContentTypes: [UniformTypeIdentifiers.UTType] { get }
  func reader(configuration: sending Self.ReadConfiguration) -> sending Self.Reader
  @_Concurrency.MainActor func apply(snapshot: sending Self.Reader.Snapshot, previous: sending Self.Reader.Snapshot?) async throws
}
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public protocol WritableDocument : AnyObject {
  associatedtype Writer : SwiftUI.DocumentWriter
  typealias WriteConfiguration = SwiftUI.DocumentWriteConfiguration
  static var writableContentTypes: [UniformTypeIdentifiers.UTType] { get }
  func writer(configuration: sending Self.WriteConfiguration) -> sending Self.Writer
  @_Concurrency.MainActor func snapshot(contentType: UniformTypeIdentifiers.UTType) async throws -> sending Self.Writer.Snapshot
}
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
extension SwiftUI.ReadableDocument where Self : SwiftUI.WritableDocument {
  public static var writableContentTypes: [UniformTypeIdentifiers.UTType] {
    get
  }
}
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct FileWrapperDocumentWriter<Snapshot> : SwiftUI.DocumentWriter {
  public typealias WriteConfiguration = SwiftUI.DocumentWriteConfiguration
  public init(_ configuration: sending SwiftUI.FileWrapperDocumentWriter<Snapshot>.WriteConfiguration, makeFileWrapper: @escaping (_ snapshot: Snapshot, _ previous: Foundation.FileWrapper?) async throws -> Foundation.FileWrapper)
  #if compiler(>=5.3) && $AsyncExecutionBehaviorAttributes
  @concurrent public func write(snapshot: sending Snapshot, to destination: sending Foundation.URL, previous: sending Snapshot?, progress: consuming Foundation.Subprogress) async throws
  #endif
  @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
  @available(tvOS, unavailable)
  @available(watchOS, unavailable)
  public typealias Destination = Foundation.URL
}
@available(*, unavailable)
extension SwiftUI.FileWrapperDocumentWriter : Swift.Sendable {
}
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
public struct FileWrapperDocumentReader<Snapshot> : SwiftUI.DocumentReader {
  public typealias ReadConfiguration = SwiftUI.DocumentReadConfiguration
  public init(_ configuration: sending SwiftUI.FileWrapperDocumentReader<Snapshot>.ReadConfiguration, makeSnapshot: @escaping (Foundation.FileWrapper) async throws -> sending Snapshot)
  #if compiler(>=5.3) && $AsyncExecutionBehaviorAttributes
  @concurrent public func read(from source: sending Foundation.URL, progress: consuming Foundation.Subprogress) async throws -> sending Snapshot
  #endif
  @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
  @available(tvOS, unavailable)
  @available(watchOS, unavailable)
  public typealias Source = Foundation.URL
}
@available(*, unavailable)
extension SwiftUI.FileWrapperDocumentReader : Swift.Sendable {
}
```

### URL document configuration

Interface lines 2133–2147:

```swift
@_hasMissingDesignatedInitializers @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
@_Concurrency.MainActor final public class URLDocumentConfiguration {
  @_Concurrency.MainActor final public var fileURL: Foundation.URL? {
    get
    set
  }
  @_Concurrency.MainActor final public var lastContentModificationDate: Foundation.Date? {
    get
    set
  }
  @_Concurrency.MainActor final public func makeFileCoordinator() -> sending Foundation.NSFileCoordinator
  @objc deinit
}
```

### New document button initializer

Interface lines 12956–12961:

```swift
@available(iOS 18.0, macOS 15.0, visionOS 2.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension SwiftUI.NewDocumentButton where Label == SwiftUICore.Text {
  nonisolated public init(_ label: SwiftUICore.Text? = nil, contentType: UniformTypeIdentifiers.UTType? = nil)
  nonisolated public init(_ title: SwiftUICore.LocalizedStringKey, contentType: UniformTypeIdentifiers.UTType? = nil)
```

### Document launch view: unavailable on macOS

Interface lines 30182–30193:

```swift
#if compiler(>=5.3) && $TildeSendable
@available(iOS 18.0, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
@available(macCatalyst, unavailable)
nonisolated public struct DocumentLaunchView<Actions, DocumentView> : SwiftUICore.View, ~Swift.Sendable where Actions : SwiftUICore.View, DocumentView : SwiftUICore.View {
  nonisolated public var body: some SwiftUICore.View {
    get
  }
  nonisolated public init(_ title: SwiftUICore.LocalizedStringKey, for contentTypes: [UniformTypeIdentifiers.UTType], @SwiftUICore.ContentBuilder _ actions: () -> Actions, @SwiftUICore.ContentBuilder onDocumentOpen: @escaping (Foundation.URL) -> DocumentView, @SwiftUICore.ContentBuilder background: () -> some View, @SwiftUICore.ContentBuilder backgroundAccessoryView: @escaping (SwiftUI.DocumentLaunchGeometryProxy) -> some View, @SwiftUICore.ContentBuilder overlayAccessoryView: @escaping (SwiftUI.DocumentLaunchGeometryProxy) -> some View)
```
