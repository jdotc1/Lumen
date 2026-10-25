import AppKit
import SwiftUI
import LumenTokens

/// The contents of a `MenuBarExtra` using `.menuBarExtraStyle(.window)`. The system owns the
/// status item, window presentation and dismissal; Lumen owns the optional header, scrolling
/// body and optional footer. The footer includes Settings and Quit after any supplied content.
/// Pair with `.lumenPaletteRoot()` inside the scene.
public struct LumenMenuBarPanel<Content: View, Accessory: View, Footer: View>: View {
    private let title: String?
    private let width: CGFloat
    private let maximumHeight: CGFloat
    private let showsFooter: Bool
    private let content: Content
    private let accessory: Accessory
    private let footer: Footer
    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @Environment(\.lumenMetrics) private var metrics

    /// The title controls header presence. An accessory is displayed at its trailing edge.
    /// Omit the footer with `showsFooter: false`; its actions operate on the host application.
    public init(_ title: String? = nil, width: CGFloat = LumenLayout.popoverWidth,
                maximumHeight: CGFloat = LumenLayout.panelMaxHeight,
                showsFooter: Bool = true,
                @ViewBuilder content: () -> Content,
                @ViewBuilder accessory: () -> Accessory = { EmptyView() },
                @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.width = width
        self.maximumHeight = maximumHeight
        self.showsFooter = showsFooter
        self.content = content()
        self.accessory = accessory()
        self.footer = footer()
    }

    public var body: some View {
        let scrollHeight = min(contentHeight, max(0, maximumHeight - headerHeight - footerHeight))
        VStack(spacing: 0) {
            if let title {
                VStack(spacing: 0) {
                    MenuBarPanelHeader(title: title, accessory: accessory)
                        .menuBarPanelRegion(.header)
                    Divider()
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.spacing.s4) { content }
                    .lumenColumnWidthWatch("Menu bar panel content", columnWidth: max(0, width - 2 * metrics.spacing.s5))
                    .padding(metrics.spacing.s5)
                    .menuBarPanelRegion(.scrollContent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(minHeight: 0, idealHeight: scrollHeight, maxHeight: scrollHeight)
            .menuBarPanelRegion(.content)
            if showsFooter {
                VStack(spacing: 0) {
                    Divider()
                    MenuBarPanelFooter(content: footer)
                        .menuBarPanelRegion(.footer)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            }
        }
        .frame(width: width)
        .frame(idealHeight: headerHeight + scrollHeight + footerHeight,
               maxHeight: min(maximumHeight, headerHeight + scrollHeight + footerHeight))
        .font(metrics.typography.callout)
        .foregroundStyle(.lumen(.fgPrimary))
        .lumenRaisedGround()
        .menuBarPanelRegion(.panel, hasHeader: title != nil, hasFooter: showsFooter)
        .lumenScaffoldMargin(metrics.spacing.s5)
    }
}

private struct MenuBarPanelHeader<Accessory: View>: View {
    let title: String
    let accessory: Accessory
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.s3) {
            Text(title).font(metrics.typography.headline)
                .lineLimit(1).lumenNeverTruncates(title)
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, metrics.spacing.s5)
        .padding(.vertical, metrics.spacing.s4)
        .fixedSize(horizontal: false, vertical: true)
        .lumenColumnContent("Menu bar panel header")
    }
}

private struct MenuBarPanelFooter<Content: View>: View {
    let content: Content
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s3) {
            content
            HStack(spacing: metrics.spacing.s3) {
                Button { openSettings() } label: {
                    Text("Settings…").lumenNeverTruncates("Settings…")
                }
                Spacer(minLength: 0)
                Button { NSApplication.shared.terminate(nil) } label: {
                    Text("Quit").lumenNeverTruncates("Quit")
                }
            }
            .buttonStyle(.lumenQuiet)
            .controlSize(.small)
        }
        .padding(.horizontal, metrics.spacing.s5)
        .padding(.vertical, metrics.spacing.s4)
        .fixedSize(horizontal: false, vertical: true)
        .lumenColumnContent("Menu bar panel footer")
    }
}
