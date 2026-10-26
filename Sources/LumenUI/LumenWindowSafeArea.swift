import AppKit
import SwiftUI

/// One coordinate system and chrome definition for correction and diagnostics. AppKit's layout
/// rect follows toolbar style, visibility and fullscreen; no title-bar height is assumed here.
@MainActor
struct LumenWindowGeometry {
    let contentBounds: CGRect
    let chromeBand: CGRect
    let trafficLights: [CGRect]
    let toolbarItems: [CGRect]

    init(window: NSWindow) {
        contentBounds = window.convertToScreen(window.contentLayoutRect)
        chromeBand = CGRect(x: window.frame.minX, y: contentBounds.maxY,
                            width: window.frame.width,
                            height: max(0, window.frame.maxY - contentBounds.maxY))
        trafficLights = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap {
            guard let button = window.standardWindowButton($0), !button.isHiddenOrHasHiddenAncestor else { return nil }
            return window.convertToScreen(button.convert(button.bounds, to: nil))
        }
        toolbarItems = (window.toolbar?.visibleItems ?? []).compactMap {
            guard let view = $0.view, view.window === window, !view.isHiddenOrHasHiddenAncestor else { return nil }
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
    }
}

/// The complete extent owned by a scaffold, not just evidence that one exists somewhere below
/// the palette root. A stack with a control above a scaffold still needs root protection.
struct LumenChromeOwnerKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value.append(contentsOf: nextValue()) }
}

extension View {
    func lumenOwnsWindowTop() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: LumenChromeOwnerKey.self, value: [proxy.frame(in: .global)])
            }
        }
    }
}


/// Audit-only ownership, independent of whether the scaffold fills its host window.
struct LumenScaffoldMargin: Equatable, Sendable {
    var frame: CGRect
    let margin: CGFloat
    var depth: Int

    static func owner(at point: CGPoint, in declarations: [Self]) -> Self? {
        declarations.filter { $0.frame.contains(point) }.max {
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            return $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height
        }
    }
}

private struct LumenScaffoldMarginKey: PreferenceKey {
    static let defaultValue: [LumenScaffoldMargin] = []
    static func reduce(value: inout [LumenScaffoldMargin], nextValue: () -> [LumenScaffoldMargin]) {
        value.append(contentsOf: nextValue())
    }
}

/// Measured shared component extents for bounded visual-change evidence.
struct LumenMarginElementFrame: Equatable, Sendable {
    let role: String
    let frame: CGRect
}

struct LumenMarginElementFrameKey: PreferenceKey {
    static let defaultValue: [LumenMarginElementFrame] = []
    static func reduce(value: inout [LumenMarginElementFrame], nextValue: () -> [LumenMarginElementFrame]) {
        value.append(contentsOf: nextValue())
    }
}

#if DEBUG
/// Native ancestry for first-content tests; preference geometry alone cannot identify
/// a column when SwiftUI creates a separate hosting root for a native split pane.
final class LumenMarginElementProbeView: NSView {
    var role = ""
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private struct LumenMarginElementProbe: NSViewRepresentable {
    let role: String
    func makeNSView(context: Context) -> LumenMarginElementProbeView {
        let view = LumenMarginElementProbeView()
        view.setAccessibilityElement(false)
        view.role = role
        return view
    }
    func updateNSView(_ view: LumenMarginElementProbeView, context: Context) { view.role = role }
}
#endif

extension View {
    func lumenReportsMarginElement(_ role: String) -> some View {
        background {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LUMEN_SETTINGS_MATRIX_NATIVE_PROBES"] == "1" {
                LumenMarginElementProbe(role: role)
            }
            #endif
            GeometryReader { proxy in
                Color.clear.preference(key: LumenMarginElementFrameKey.self,
                    value: [.init(role: role, frame: proxy.frame(in: .global))])
            }
        }
    }

    func lumenScaffoldMargin(_ margin: CGFloat) -> some View {
        environment(\.lumenScaffoldContentMargin, margin)
        .transformPreference(LumenScaffoldMarginKey.self) { declarations in
            for index in declarations.indices { declarations[index].depth += 1 }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: LumenScaffoldMarginKey.self,
                    value: [.init(frame: proxy.frame(in: .global), margin: margin, depth: 0)])
            }
        }
    }
}

@MainActor
final class LumenWindowRootScope {
    weak var window: NSWindow?
}

extension EnvironmentValues {
    @Entry var lumenWindowRootScope: LumenWindowRootScope? = nil
    /// The innermost scaffold's declared horizontal ink clearance. Shared bottom bars
    /// keep even their capsule stroke inside it; inspector columns add it outside
    /// their own content padding. This is the existing page-margin contract, not a
    /// radius constant. Unattached components have no window margin to consume.
    @Entry var lumenScaffoldContentMargin: CGFloat? = nil
}

private struct LumenWindowMinimumKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

/// A permanent layout boundary: attachment and overflow only change numeric proposals.
/// The final subview reports the content minimum without participating in its layout.
private struct LumenWindowContentLayout: Layout {
    let topInset: CGFloat
    let anchorsOverflow: Bool

    private func minimum(_ subviews: Subviews) -> CGSize {
        subviews.dropLast().reduce(CGSize.zero) { result, child in
            let size = child.sizeThatFits(.zero)
            return CGSize(width: max(result.width, size.width.isFinite ? size.width : 0),
                          height: max(result.height, size.height.isFinite ? size.height : 0))
        }
    }

    private func contentProposal(_ proposal: ProposedViewSize, minimum: CGSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width.map { max($0, minimum.width) },
                         height: proposal.height.map { max($0 - topInset, minimum.height) })
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let minimum = minimum(subviews)
        // Preserve the child's response to the proposal. In particular, do not turn a
        // minimum/ideal/unbounded query into a finite viewport or clamp it before measuring.
        let offered = ProposedViewSize(width: proposal.width, height: proposal.height.map {
            $0.isFinite && topInset > 0 ? max(0, $0 - topInset) : $0
        })
        let response = subviews.dropLast().reduce(CGSize.zero) { result, child in
            let size = child.sizeThatFits(offered)
            return CGSize(width: max(result.width, size.width), height: max(result.height, size.height))
        }
        let natural = CGSize(width: max(minimum.width, response.width),
                             height: max(minimum.height, response.height) + topInset)
        // An oversized layout response is centered by the host before placeSubviews runs.
        // Accept a real viewport at the outer attached root; retain minimum/ideal queries
        // and the full child minimum so overflow is placed only at the trailing/bottom edge.
        func extent(_ natural: CGFloat, _ offered: CGFloat?) -> CGFloat {
            guard anchorsOverflow, let offered, offered.isFinite, offered > 0 else { return natural }
            return min(natural, offered)
        }
        return CGSize(width: extent(natural.width, proposal.width),
                      height: extent(natural.height, proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let minimum = minimum(subviews)
        let offered = contentProposal(ProposedViewSize(bounds.size), minimum: minimum)
        let origin = CGPoint(x: bounds.minX, y: bounds.minY + topInset)
        for child in subviews.dropLast() {
            child.place(at: origin, anchor: .topLeading, proposal: offered)
        }
        subviews.last?.place(at: bounds.origin, anchor: .topLeading,
                             proposal: ProposedViewSize(minimum))
    }
}

struct LumenWindowSafeArea: ViewModifier {
    let contentName: String
    @Environment(\.lumenWindowRootScope) private var ancestorScope
    @Environment(\.lumenScaffoldContentMargin) private var ancestorMargin
    @State private var scope = LumenWindowRootScope()
    @Environment(\.lumenSettingsWindow) private var explicitSettings
    @Environment(\.lumenPreservesExpandedToolbar) private var preservesExpanded
    @State private var detectedSettings = false
    @State private var settingsScaffold = false
    @State private var nativeSplitOwnsTop = false
    @State private var chromePaint = LumenWindowPaint()
    @State private var framedTileSymbols: Set<String> = []
    private var isSettings: Bool { explicitSettings || detectedSettings || settingsScaffold }
    @State private var nested = false
    @Environment(\.lumenMetrics) private var metrics
    @Environment(\.lumenReportsLayoutChecks) private var reportsChecks
    @State private var measuredTop: CGFloat = 0
    @State private var eligible = false
    @State private var owners: [CGRect] = []
    @State private var scaffoldMargins: [LumenScaffoldMargin] = []
    @State private var wizard: [LumenWizardLayoutEntry] = []
    @State private var menu: [LumenMenuBarPanelLayoutEntry] = []
    @State private var bottomBars: [CGRect] = []
    @State private var contentFrame = CGRect.zero
    @State private var minimum = CGSize.zero
    @State private var truncated: Set<String> = []
    @State private var visibleTexts: Set<LumenVisibleTextEntry> = []

    private var ownsTop: Bool {
        if isSettings || nativeSplitOwnsTop { return true }
        let extents = owners + wizard.filter { $0.region == .window }.map(\.frame)
            + menu.filter { $0.region == .panel }.map(\.frame)
        return extents.contains { owner in
            owner.width > 0 && abs(owner.minY - contentFrame.minY) < 1
                && abs(owner.minX - contentFrame.minX) < 1
                && abs(owner.maxX - contentFrame.maxX) < 1
                && abs(owner.maxY - contentFrame.maxY) < 1
        }
    }
    private var applies: Bool { eligible && !nested && !ownsTop }
    private var watches: Bool {
        #if DEBUG
        true
        #else
        reportsChecks
        #endif
    }

    func body(content: Content) -> some View {
        LumenWindowContentLayout(topInset: applies ? measuredTop + metrics.spacing.s4 : 0,
                                 anchorsOverflow: eligible && !nested) {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { contentFrame = $0 }
            GeometryReader { measured in
                Color.clear.preference(key: LumenWindowMinimumKey.self, value: measured.size)
            }
            .allowsHitTesting(false)
            .hidden()
        }
        .environment(\.lumenWindowRootScope, scope)
        .environment(\.lumenIsSettingsWindow, isSettings)
        .environment(\.lumenHasNativeSidebar, nativeSplitOwnsTop)
        .environment(\.lumenScaffoldContentMargin, ancestorMargin ?? metrics.spacing.s6)
        .environment(\.lumenReportsLayoutChecks, watches)
        .background {
            GeometryReader { proxy in
                let top = applies ? measuredTop + metrics.spacing.s4 : 0
                LumenWindowSafeAreaBridge(globalFrame: proxy.frame(in: .global), contentFrame: contentFrame,
                                          minimum: minimum, contentName: contentName, extra: CGSize(width: 0, height: top), gap: metrics.spacing.s4,
                                          ownsTop: ownsTop, scope: scope, ancestorScope: ancestorScope,
                                          settings: isSettings, settingsScaffold: settingsScaffold,
                                          preservesExpanded: preservesExpanded, paint: chromePaint, framedTileSymbols: framedTileSymbols,
                                          detectedSettings: { detectedSettings = $0 },
                                          detectedRootSplit: { nativeSplitOwnsTop = $0 },
                                          margin: metrics.spacing.s6, scaffoldMargins: scaffoldMargins,
                                          truncated: truncated, visibleTexts: visibleTexts,
                                          bottomBars: bottomBars + wizard.filter { $0.region == .bottomBar }.map(\.frame)
                                              + menu.filter { $0.region == .footer }.map(\.frame)) { top, active, isNested, _ in
                    measuredTop = top
                    eligible = active
                    nested = isNested
                }
            }
        }
        .onPreferenceChange(LumenSettingsRootKey.self) { settingsScaffold = $0 }
        .onPreferenceChange(LumenWindowPaintKey.self) { chromePaint = $0 }
        .onPreferenceChange(LumenTileFrameAdvisoryKey.self) { framedTileSymbols = $0 }
        .onPreferenceChange(LumenScaffoldMarginKey.self) { scaffoldMargins = $0 }
        .onPreferenceChange(LumenChromeOwnerKey.self) { owners = $0 }
        .onPreferenceChange(LumenWizardLayoutKey.self) { wizard = $0 }
        .onPreferenceChange(LumenMenuBarPanelLayoutKey.self) { menu = $0 }
        .onPreferenceChange(LumenBottomBarFrameKey.self) { bottomBars = $0 }
        .onPreferenceChange(LumenWindowMinimumKey.self) { minimum = $0 }
        .onPreferenceChange(LumenTruncationKey.self) { truncated = $0 }
        .onPreferenceChange(LumenVisibleTextKey.self) { visibleTexts = $0 }
        .transformPreference(LumenWindowMinimumKey.self) { $0 = .zero }
    }

}

private struct LumenWindowSafeAreaBridge: NSViewRepresentable {
    let globalFrame: CGRect
    let contentFrame: CGRect
    let minimum: CGSize
    let contentName: String
    let extra: CGSize
    let gap: CGFloat
    let ownsTop: Bool
    let scope: LumenWindowRootScope
    let ancestorScope: LumenWindowRootScope?
    let settings: Bool
    let settingsScaffold: Bool
    let preservesExpanded: Bool
    let paint: LumenWindowPaint
    let framedTileSymbols: Set<String>
    let detectedSettings: @MainActor (Bool) -> Void
    let detectedRootSplit: @MainActor (Bool) -> Void
    let margin: CGFloat?
    let scaffoldMargins: [LumenScaffoldMargin]
    let truncated: Set<String>
    let visibleTexts: Set<LumenVisibleTextEntry>
    let bottomBars: [CGRect]
    let measured: @MainActor (CGFloat, Bool, Bool, Bool) -> Void

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {
        view.input = self
        view.schedule()
    }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: NSView, LumenOwnedInkSource {
        // Geometry-only bridge: its transparent extent is never a drawing boundary.
        var ownedInkRects: [CGRect] { [] }
        var input: LumenWindowSafeAreaBridge?
        private var observation: NSKeyValueObservation?
        private let chrome = LumenNativeWindowChrome()
        private var lastDetectedSettings: Bool?
        private var lastRootSplit: Bool?
        private var pending = false
        private var lastTop: CGFloat?
        private var lastEligible: Bool?
        private var lastVisible: Bool?
        private var lastNested: Bool?
        private var lastViewport: CGSize?
        private weak var ownedWindow: NSWindow?
        private var originalMinimum: CGSize?
        private var installedMinimum: CGSize?
        private var grewToMinimum = false
        private var growth: DispatchWorkItem?
        private var growthTarget: CGSize?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            if let window {
                ownedWindow = window
                originalMinimum = window.contentMinSize
                observation = window.observe(\.contentLayoutRect, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.schedule() }
                }
                for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
                             NSWindow.didExitFullScreenNotification, NSWindow.didExposeNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(changed), name: name, object: window)
                }
            }
            schedule()
        }
        override func layout() { super.layout(); schedule() }
        @objc private func changed(_ notification: Notification) { schedule() }
        func detach() {
            chrome.detach()
            lastDetectedSettings = nil
            lastRootSplit = nil
            if let ownedWindow, let installedMinimum, ownedWindow.contentMinSize == installedMinimum,
               let originalMinimum { ownedWindow.contentMinSize = originalMinimum }
            installedMinimum = nil
            grewToMinimum = false
            growth?.cancel()
            growth = nil
            growthTarget = nil
            originalMinimum = nil
            ownedWindow = nil
            input?.scope.window = nil
            observation = nil
            NotificationCenter.default.removeObserver(self)
        }
        func schedule() {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending = false
                self.measure()
            }
        }
        private func measure() {
            guard let window, let input else { return }
            input.scope.window = window
            let nested = input.ancestorScope?.window === window
            if !nested {
                chrome.attach(window: window)
                chrome.update(preservesExpanded: input.preservesExpanded)
                let detected = LumenNativeWindowChrome.isSettingsWindow(window)
                if detected != lastDetectedSettings {
                    lastDetectedSettings = detected
                    input.detectedSettings(detected)
                }
            } else { chrome.detach() }
            let geometry = LumenWindowGeometry(window: window)
            let frame = window.convertToScreen(convert(bounds, to: nil))
            // Sheets and untitled transient panels own their own presentation margins.
            let active = window.isVisible && window.styleMask.contains(.titled) && window.sheetParent == nil
                && geometry.chromeBand.height > 0.5
            let top = max(0, frame.maxY - geometry.contentBounds.maxY)
            func screen(_ rect: CGRect) -> CGRect {
                CGRect(x: frame.minX + rect.minX - input.globalFrame.minX,
                       y: frame.maxY - (rect.maxY - input.globalFrame.minY),
                       width: rect.width, height: rect.height)
            }
            // Compare with the app subtree, not the probe/viewport. Applying or removing
            // our inset moves both extents together, so ownership does not feed back into
            // itself. A header stacked above a split makes its top lower and cannot qualify.
            let appFrame = screen(input.contentFrame)
            func rootSplit(in view: NSView) -> Bool {
                if let split = view as? NSSplitView, split.isVertical, !split.isHiddenOrHasHiddenAncestor {
                    let rect = window.convertToScreen(split.convert(split.bounds, to: nil))
                    let expectedTop = min(appFrame.maxY, geometry.contentBounds.maxY)
                    if appFrame.width > 0, appFrame.height > 0,
                       abs(rect.minX - appFrame.minX) < 1,
                       abs(rect.maxX - appFrame.maxX) < 1,
                       abs(rect.minY - appFrame.minY) < 1,
                       rect.maxY >= expectedTop - 1 {
                        return true
                    }
                }
                return view.subviews.contains(where: rootSplit)
            }
            let splitOwnsTop = !nested && window.contentView.map(rootSplit) == true
            if splitOwnsTop != lastRootSplit {
                lastRootSplit = splitOwnsTop
                input.detectedRootSplit(splitOwnsTop)
            }
            if lastTop != top || lastEligible != active || lastNested != nested || lastViewport != geometry.contentBounds.size || lastVisible != window.isVisible {
                lastTop = top
                lastEligible = active
                lastVisible = window.isVisible
                lastNested = nested
                lastViewport = geometry.contentBounds.size
                input.measured(top, active, nested, window.isVisible)
            }
            guard !nested else {
                if let installedMinimum, window.contentMinSize == installedMinimum,
                   let originalMinimum { window.contentMinSize = originalMinimum }
                installedMinimum = nil
                return
            }
            let report = LumenWindowAuditReports.record(for: window)
            report.lumenRooted = true
            report.settingsWindow = input.settings
            report.settingsScaffold = input.settingsScaffold
            report.paintsWindowGlow = input.paint.glow
            report.forcesToolbarBand = input.paint.forcedBand
            report.preservesExpandedToolbar = input.preservesExpanded
            report.framedTileSymbols = input.framedTileSymbols
            report.truncated = input.truncated
            report.visibleTexts = input.visibleTexts
            report.bottomBars = input.bottomBars.map(screen)
            report.pageMargin = input.margin
            report.scaffoldMargins = input.scaffoldMargins.map {
                .init(frame: screen($0.frame), margin: $0.margin, depth: $0.depth)
            }
            report.ownsTopBar = input.ownsTop
            report.contentMinimum = input.minimum
            report.contentMinimumView = input.contentName
            report.contentFrame = screen(input.contentFrame)
            let nativeExtra = max(0, (window.contentView?.bounds.height ?? 0) - geometry.contentBounds.height)
            let required = CGSize(width: input.minimum.width + input.extra.width,
                                  height: input.minimum.height + max(0, input.extra.height - top) + nativeExtra)
            if required.width.isFinite, required.height.isFinite, required.width > 0, required.height > 0 {
                if let installedMinimum, window.contentMinSize != installedMinimum {
                    originalMinimum = window.contentMinSize
                }
                let baseline = originalMinimum ?? .zero
                let requested = CGSize(width: max(baseline.width, required.width),
                                       height: max(baseline.height, required.height))
                let requiredFrame = window.frameRect(forContentRect: CGRect(origin: .zero, size: requested)).size
                let visible = (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
                let cap = visible.map { window.contentRect(forFrameRect: $0).size }
                let enforced = CGSize(width: min(requested.width, cap?.width ?? .infinity),
                                      height: min(requested.height, cap?.height ?? .infinity))
                if window.contentMinSize != enforced { window.contentMinSize = enforced }
                installedMinimum = enforced
                report.minimumEnforced = window.contentMinSize.width >= required.width
                    && window.contentMinSize.height >= required.height
                report.minimumGrowthHasNoScreen = visible == nil
                report.contentMinimumExceedsScreen = visible.map {
                    requiredFrame.width > $0.width + 0.5 || requiredFrame.height > $0.height + 0.5
                } ?? false
                report.overflowIsReachable = false
                // Wait for the live inset to reach the layout before the one initial growth.
                let expectedTop = active && !input.ownsTop ? top + input.gap : 0
                if !grewToMinimum, window.isVisible, abs(input.extra.height - expectedTop) < 0.5,
                   input.minimum.width > 0, input.minimum.height > 0 {
                    let target = CGSize(width: min(max(window.frame.width, requiredFrame.width), visible?.width ?? .infinity),
                                        height: min(max(window.frame.height, requiredFrame.height), visible?.height ?? .infinity))
                    let needsGrowth = window.frame.width < target.width - 0.5 || window.frame.height < target.height - 0.5
                    if !needsGrowth {
                        growth?.cancel()
                        growth = nil
                        growthTarget = nil
                    } else if growthTarget != target {
                        growth?.cancel()
                        growthTarget = target
                        let work = DispatchWorkItem { [weak self, weak window] in
                            guard let self, let window, self.window === window else { return }
                            self.growth = nil
                            self.growthTarget = nil
                            if window.frame.width < target.width - 0.5 || window.frame.height < target.height - 0.5 {
                                self.grewToMinimum = true
                                let origin = visible.map { screen in
                                    CGPoint(x: max(screen.minX, min(window.frame.minX, screen.maxX - target.width)),
                                            y: max(screen.minY, min(window.frame.maxY - target.height, screen.maxY - target.height)))
                                } ?? CGPoint(x: window.frame.minX, y: window.frame.maxY - target.height)
                                window.setFrame(CGRect(origin: origin, size: target), display: true)
                            }
                        }
                        growth = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
                    }
                }
            }
        }
    }
}
