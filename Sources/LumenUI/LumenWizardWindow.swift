import SwiftUI
import LumenTokens

/// A stable step in a first-run or installer window. Page IDs must be unique within the wizard.
public struct LumenWizardPage: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var systemImage: String?

    public init(id: String, title: String, systemImage: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

/// A resizable, titled wizard with completed-step navigation and a persistent action bar.
/// Pair with `.lumenWizardScene()` and `.lumenPaletteRoot()`. The host owns page state and
/// validation. An out-of-range selection is clamped; an empty wizard has no forward action.
public struct LumenWizardWindow<Content: View>: View {
    private let pages: [LumenWizardPage]
    @Binding private var current: Int
    private let canContinue: Bool
    private let finishTitle: String
    private let onCancel: () -> Void
    private let onFinish: () -> Void
    private let content: (LumenWizardPage) -> Content
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    @Environment(\.lumenWizardPreferredSize) private var preferredSize

    public init(pages: [LumenWizardPage], current: Binding<Int>, canContinue: Bool = true,
                finishTitle: String = "Done", onCancel: @escaping () -> Void,
                onFinish: @escaping () -> Void,
                @ViewBuilder content: @escaping (LumenWizardPage) -> Content) {
        self.pages = pages
        _current = current
        self.canContinue = canContinue
        self.finishTitle = finishTitle
        self.onCancel = onCancel
        self.onFinish = onFinish
        self.content = content
    }

    private var navigation: LumenWizardNavigation {
        .init(current: $current, count: pages.count, canContinue: canContinue, onFinish: onFinish)
    }

    public var body: some View {
        // Grow with resolved typography, including theme type scale, without measuring a size
        // that this frame itself drives. Density changes spacing inside the stable window.
        let growth = max(1, metrics.layout.controlHeight / LumenMetrics.standard.layout.controlHeight)
        let minimum = CGSize(width: 640 * growth, height: 460 * growth)
        let preferred = preferredSize ?? minimum
        VStack(spacing: 0) {
            GeometryReader { bounds in
                HStack(spacing: 0) {
                    WizardStepList(pages: pages, current: navigation.index, onSelect: navigation.goBack(to:))
                        .frame(width: max(180 * growth, bounds.size.width * 180 / 640))
                    Rectangle().fill(palette[.borderSubtle]).frame(width: metrics.stroke.hairline)
                    if !pages.isEmpty {
                        WizardPageContent(page: pages[navigation.index], content: content(pages[navigation.index]))
                            .wizardRegion(.currentPage)
                    } else {
                        Text("No steps to show")
                            .font(metrics.typography.headline)
                            .foregroundStyle(palette[.fgSecondary])
                            .lumenWrapsWithoutTruncating()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .wizardRegion(.emptyState)
                    }
                }
            }
            WizardBottomBar(navigation: navigation, finishTitle: finishTitle, onCancel: onCancel)
        }
        .frame(minWidth: minimum.width, idealWidth: max(minimum.width, preferred.width), maxWidth: .infinity,
               minHeight: minimum.height, idealHeight: max(minimum.height, preferred.height), maxHeight: .infinity)
        .font(metrics.typography.body)
        .foregroundStyle(palette[.fgPrimary])
        .background(palette[.bgCanvas])
        .wizardRegion(.window, pageCount: pages.count)
        .lumenScaffoldMargin(metrics.spacing.s6)
        .onChange(of: current, initial: true) { navigation.clamp() }
        .onChange(of: pages.count) { navigation.clamp() }
    }
}

private struct WizardStepList: View {
    let pages: [LumenWizardPage]
    let current: Int
    let onSelect: (Int) -> Void
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.s2) {
                ForEach(pages.enumerated(), id: \.element.id) { index, page in
                    Button { onSelect(index) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.s4) {
                            Image(systemName: index < current ? "checkmark" : (page.systemImage ?? "circle"))
                                .frame(width: metrics.iconSize.small)
                            Text(page.title)
                                // Reserve the selected weight so navigating never shifts a row.
                                .font(metrics.typography.bodyEmphasized)
                                .hidden()
                                .overlay(alignment: .leading) {
                                    Text(page.title)
                                        .font(index == current ? metrics.typography.bodyEmphasized : metrics.typography.body)
                                        .lumenWrapsWithoutTruncating()
                                }
                                .lumenWrapsWithoutTruncating()
                        }
                        .foregroundStyle(palette[index > current ? .fgTertiary : .fgPrimary])
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(metrics.spacing.s4)
                        .background(index == current ? palette[appearsActive ? .sidebarRowSelected : .sidebarRowSelectedInactive] : .clear,
                                    in: .rect(cornerRadius: metrics.radius.sm))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(index > current)
                }
            }
            .padding(metrics.spacing.s4)
            .lumenColumnContent("Wizard steps")
        }
        .lumenSidebarBackground()
        .wizardRegion(.stepList)
    }
}

private struct WizardPageContent<Content: View>: View {
    let page: LumenWizardPage
    let content: Content
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s6) {
            Text(page.title).font(metrics.typography.title2).lumenWrapsWithoutTruncating()
            ViewThatFits(in: .vertical) {
                // ViewThatFits already evaluates the ideal height. Preserve the selected
                // candidate's finite proposal so flexible List/navigation content can fill it.
                content.lumenColumnContent("Wizard page body")
                ScrollView {
                    content.lumenColumnContent("Wizard page body")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(metrics.spacing.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .lumenColumnContent("Wizard page")
    }
}

private struct WizardBottomBar: View {
    let navigation: LumenWizardNavigation
    let finishTitle: String
    let onCancel: () -> Void
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.s3) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.lumenQuiet).keyboardShortcut(.cancelAction).fixedSize()
                .wizardRegion(.cancelButton)
            Spacer(minLength: metrics.spacing.s4)
            Button("Go Back", action: navigation.back)
                .buttonStyle(.lumenQuiet).disabled(!navigation.canGoBack).fixedSize()
                .wizardRegion(.backButton)
            Button(navigation.isLast ? finishTitle : "Continue", action: navigation.advance)
                .buttonStyle(.lumenPrimary).keyboardShortcut(.defaultAction)
                .disabled(!navigation.canAdvance).fixedSize()
                .wizardRegion(.continueButton, isDefaultAction: true)
        }
        .padding(metrics.spacing.s6)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            Rectangle().fill(palette[.borderSubtle]).frame(height: metrics.stroke.hairline)
        }
        .lumenColumnContent("Wizard bottom bar")
        .wizardRegion(.bottomBar)
    }
}

/// The review body for a wizard's final page. Values wrap within their trailing column.
public struct LumenWizardSummary: View {
    private let items: [(label: String, value: String)]
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenPalette) private var palette

    public init(_ items: [(label: String, value: String)]) { self.items = items }

    public var body: some View {
        LumenSettingsCard {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: metrics.spacing.s5) {
                    Text(items[index].label)
                        .foregroundStyle(palette[.fgSecondary])
                        .lumenWrapsWithoutTruncating()
                    Spacer(minLength: metrics.spacing.s3)
                    Text(items[index].value)
                        .multilineTextAlignment(.trailing)
                        .lumenWrapsWithoutTruncating()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(metrics.typography.body)
            }
        }
    }
}

public extension Scene {
    /// Keeps a wizard titled and resizable above its typography-aware minimum size.
    func lumenWizardScene() -> some Scene {
        windowStyle(.titleBar).windowResizability(.contentMinSize)
    }
}

/// The same transition policy drives the buttons and completed-step links.
@MainActor
struct LumenWizardNavigation {
    let current: Binding<Int>
    let count: Int
    let canContinue: Bool
    let onFinish: () -> Void

    var index: Int { min(max(0, current.wrappedValue), max(0, count - 1)) }
    var isLast: Bool { count > 0 && index == count - 1 }
    var canGoBack: Bool { count > 0 && index > 0 }
    var canAdvance: Bool { count > 0 && canContinue }

    func clamp() { if current.wrappedValue != index { current.wrappedValue = index } }
    func back() { if canGoBack { current.wrappedValue = index - 1 } }
    func goBack(to target: Int) {
        if target >= 0 && target < index { current.wrappedValue = target }
    }
    func advance() {
        guard canAdvance else { return }
        if isLast { clamp(); onFinish() } else { current.wrappedValue = index + 1 }
    }
}

extension EnvironmentValues {
    @Entry var lumenWizardPreferredSize: CGSize? = nil
}

public extension View {
    /// Sets the wizard's ideal opening size. Its scaled 640 × 460 minimum still applies,
    /// and subsequent host proposals can grow both columns and the page viewport.
    func lumenWizardPreferredSize(_ size: CGSize) -> some View {
        environment(\.lumenWizardPreferredSize, size)
    }
}
