import SwiftUI
import LumenTokens

/// A document's native unified title bar, content, optional inspector and status items.
/// Use inside the macOS 27 `DocumentGroup` and pair with `.lumenDocumentScene()`.
/// The host connects `title` to document naming and supplies the document's modified state;
/// `DocumentGroup` remains responsible for saving, reverting and closing the document.
/// Native window tabs own document selection. This scaffold draws no content tab strip.
public struct LumenDocumentWindow<Content: View, Inspector: View, Status: View, Trailing: View>: View {
    @Binding private var title: String
    private let isModified: Bool
    private let onRename: (() -> Void)?
    @Binding private var inspectorPresented: Bool
    private let hasInspectorBinding: Bool
    private let minimumSize: CGSize
    private let content: Content
    private let inspector: Inspector
    private let statusBar: Status
    private let topTrailing: Trailing
    private var inspectorColumnOverride: (min: CGFloat, ideal: CGFloat, max: CGFloat)?
    private var inspectorColumn: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        inspectorColumnOverride ?? LumenLayout.inspectorColumn(metrics: metrics)
    }
    private var contentMinWidth: CGFloat = 0
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    /// The minimum describes the content area, excluding the unified toolbar. With no
    /// inspector binding the shared utility policy manages automatic and explicit intent.
    /// Resizing never changes the supplied binding; a collapsed inspector restores when it fits.
    /// Supply `onRename` to route title clicks to the owning document's native rename action.
    /// Without that action, the title field edits the host-provided binding directly.
    public init(title: Binding<String>, isModified: Bool, onRename: (() -> Void)? = nil,
                inspectorPresented: Binding<Bool>? = nil,
                minimumSize: CGSize = CGSize(width: 640, height: 400),
                @ViewBuilder content: () -> Content,
                @ViewBuilder inspector: () -> Inspector = { EmptyView() },
                @ViewBuilder statusBar: () -> Status = { EmptyView() },
                @ViewBuilder topTrailing: () -> Trailing = { EmptyView() }) {
        _title = title
        self.isModified = isModified
        self.onRename = onRename
        _inspectorPresented = inspectorPresented ?? .constant(true)
        hasInspectorBinding = inspectorPresented != nil
        self.minimumSize = minimumSize
        self.content = content()
        self.inspector = inspector()
        self.statusBar = statusBar()
        self.topTrailing = topTrailing()
    }

    public func inspectorWidth(_ width: (min: CGFloat, ideal: CGFloat, max: CGFloat)) -> Self {
        var copy = self
        copy.inspectorColumnOverride = width
        return copy
    }

    public func contentMinimumWidth(_ width: CGFloat) -> Self {
        var copy = self
        copy.contentMinWidth = width.isFinite ? max(0, width) : 0
        return copy
    }

    private var panels: Binding<LumenUtilityPanels>? {
        guard hasInspectorBinding else { return nil }
        return Binding(get: {
            LumenUtilityPanels(sidebar: false, inspector: inspectorPresented)
        }, set: { inspectorPresented = $0.inspector })
    }

    public var body: some View {
        let growth = max(1, metrics.layout.controlHeight / LumenMetrics.standard.layout.controlHeight)
        // Compose the utility scaffold so its proposal measurement, mounted native split panes,
        // collapse policy and explicit user intent remain one implementation.
        LumenUtilityWindow(panels: panels, minimumSize: minimumSize) {
            content
        } inspector: {
            inspector
        } statusBar: {
            statusBar
        } topLeading: {
            HStack(spacing: metrics.spacing.s2) {
                Group {
                    if let onRename {
                        Button(action: onRename) {
                            HStack(spacing: metrics.spacing.s1) {
                                Text(title).lineLimit(1).lumenNeverTruncates(title)
                                Image(systemName: "chevron.down")
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        TextField("Document title", text: $title)
                            .textFieldStyle(.plain)
                    }
                }
                .font(metrics.typography.callout.weight(.semibold))
                .foregroundStyle(palette[.fgPrimary])
                .frame(minWidth: 100 * growth, idealWidth: 180 * growth, maxWidth: 240 * growth)
                Text(isModified ? "Edited" : "Unmodified")
                    .font(metrics.typography.caption)
                    .foregroundStyle(palette[.fgSecondary])
                    .fixedSize()
            }
        } topTrailing: {
            topTrailing
        }
        .columnWidths(inspector: inspectorColumn)
        .contentMinimumWidth(contentMinWidth)
        .lumenScaffoldMargin(metrics.spacing.s6)
        // Toolbar content is hosted separately. Report its guaranteed controls at the root
        // so conformance can observe the title and modified-state presentation in either host.
        .preference(key: LumenDocumentChromeKey.self,
                    value: [.init(hasTitle: true, hasModifiedState: true)])
    }
}

public extension Scene {
    /// Completes document chrome while preserving the system's automatic window tabbing.
    func lumenDocumentScene() -> some Scene {
        lumenUtilityScene()
    }
}

/// Presence of document controls supplied by the scaffold's native unified toolbar.
public struct LumenDocumentChromeEntry: Hashable, Sendable {
    public let hasTitle: Bool
    public let hasModifiedState: Bool

    public init(hasTitle: Bool, hasModifiedState: Bool) {
        self.hasTitle = hasTitle
        self.hasModifiedState = hasModifiedState
    }
}

/// Document toolbar reports consumed by `windowStructure(kind: .document)`.
public struct LumenDocumentChromeKey: PreferenceKey {
    public static let defaultValue: [LumenDocumentChromeEntry] = []
    public static func reduce(value: inout [LumenDocumentChromeEntry], nextValue: () -> [LumenDocumentChromeEntry]) {
        value.append(contentsOf: nextValue())
    }
}
