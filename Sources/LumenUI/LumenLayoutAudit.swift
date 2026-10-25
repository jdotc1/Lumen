import AppKit
import Foundation
#if DEBUG
import OSLog
#endif

/// Reports supplied by a palette root supplement the native and semantic view trees. The weak
/// window keys keep closing a document from retaining its labels or layout history.
@MainActor
final class LumenWindowAuditReports {
    private static let windows = NSMapTable<NSWindow, LumenWindowAuditReports>.weakToStrongObjects()
    var truncated: Set<String> = []
    var visibleTexts: Set<LumenVisibleTextEntry> = []
    var bottomBars: [CGRect] = []
    var pageMargin: CGFloat?
    var scaffoldMargins: [LumenScaffoldMargin] = []
    var ownsTopBar = false
    /// The subtree minimum and laid-out frame, expressed in usable points and screen coordinates.
    var contentMinimumView = "window root"
    var contentMinimum: CGSize?
    var contentFrame: CGRect?
    /// A previously undersized host may remain open while the root installs its new constraints.
    /// It is safe only when all overflow remains reachable and future resizing honors the minimum.
    var overflowIsReachable = false
    var minimumEnforced = false
    /// The required window frame cannot fit on its current screen after chrome is included.
    var contentMinimumExceedsScreen = false
    var minimumGrowthHasNoScreen = false

    static func record(for window: NSWindow) -> LumenWindowAuditReports {
        if let report = windows.object(forKey: window) { return report }
        let report = LumenWindowAuditReports()
        windows.setObject(report, forKey: window)
        return report
    }
}

/// Shared implementation for the DEBUG observer and LumenConformance's public window checks.
/// This reads existing in-process semantics; it neither changes accessibility nor requests access
/// to another process. Custom drawing and hidden/combined semantics require explicit reports.
@_spi(LayoutAudit) @MainActor
public enum LumenLayoutAudit {
    public struct Violation: Hashable, Sendable {
        public let rule: String
        public let view: String
        public let message: String

        public init(rule: String, view: String, message: String) {
            self.rule = rule
            self.view = view
            self.message = message
        }
    }

    private struct Element {
        let identity: ObjectIdentifier
        let ancestors: Set<ObjectIdentifier>
        let controlOwner: ObjectIdentifier?
        let name: String
        let kind: String
        let frame: CGRect
        let interactive: Bool
        let text: Bool
        let clip: CGRect?
        let scrollViewport: CGRect?

        var visibleFrame: CGRect {
            scrollViewport.map { frame.intersection($0) } ?? frame
        }
        let nativeText: NSTextField?
    }

    private struct Snapshot {
        let geometry: LumenWindowGeometry
        let elements: [Element]
        let reports: LumenWindowAuditReports
        let toolbarOwners: Set<ObjectIdentifier>
    }

    private struct Rule {
        let evaluate: @MainActor (Snapshot) -> [Violation]
    }

    // Adding a rule changes this registry, not either caller's traversal or lifecycle.
    private static let rules = [
        Rule(evaluate: chrome), Rule(evaluate: bounds), Rule(evaluate: overlaps),
        Rule(evaluate: edges), Rule(evaluate: truncation), Rule(evaluate: overflow),
    ]

    public static func findings(in window: NSWindow) -> [Violation] {
        guard let content = window.contentView else { return [] }
        let geometry = LumenWindowGeometry(window: window)
        let snapshot = Snapshot(geometry: geometry, elements: elements(in: content, window: window),
                                reports: LumenWindowAuditReports.record(for: window),
                                toolbarOwners: Set((window.toolbar?.visibleItems ?? []).compactMap {
                                    $0.view.map(ObjectIdentifier.init)
                                }))
        return Array(Set(rules.flatMap { $0.evaluate(snapshot) })).sorted {
            ($0.rule, $0.view, $0.message) < ($1.rule, $1.view, $1.message)
        }
    }

    #if DEBUG
    static func renderedElements(in window: NSWindow) -> [LumenRenderedAudit.Element] {
        guard let content = window.contentView else { return [] }
        return elements(in: content, window: window).map {
            .init(identity: String(describing: $0.controlOwner ?? $0.identity),
                  ancestors: Set($0.ancestors.map { String(describing: $0) }),
                  frame: $0.visibleFrame, source: $0.nativeText?.stringValue ?? $0.name, control: $0.interactive, clip: $0.clip)
        }
    }
    #endif

    private static func elements(in content: NSView, window: NSWindow) -> [Element] {
        var result: [Element] = []
        var seen: Set<ObjectIdentifier> = []
        let interactiveRoles: Set<NSAccessibility.Role> = [
            .button, .checkBox, .radioButton, .popUpButton, .comboBox, .textField, .textArea,
            .slider, .incrementor, .menuButton,
        ]
        func screenFrame(_ view: NSView, _ rect: CGRect) -> CGRect {
            window.convertToScreen(view.convert(rect, to: nil))
        }
        // A field editor is temporarily installed outside its control's native subtree. Resolve
        // that relationship through AppKit, rather than treating its overlapping frame as evidence
        // that two independently actionable controls occupy the same space.
        var editorOwners: [ObjectIdentifier: ObjectIdentifier] = [:]
        var cellOwners: [ObjectIdentifier: ObjectIdentifier] = [:]
        var controls: [ObjectIdentifier: NSControl] = [:]
        func collectEditors(_ view: NSView) {
            if let control = view as? NSControl {
                let owner = ObjectIdentifier(control)
                controls[owner] = control
                if let editor = control.currentEditor() { editorOwners[ObjectIdentifier(editor)] = owner }
                if let cell = control.cell { cellOwners[ObjectIdentifier(cell)] = owner }
                // Search/cancel cells may have no controlView and use reparenting proxies.
                // AppKit exposes their ownership explicitly on the containing search cell.
                if let search = control.cell as? NSSearchFieldCell {
                    if let button = search.searchButtonCell { cellOwners[ObjectIdentifier(button)] = owner }
                    if let button = search.cancelButtonCell { cellOwners[ObjectIdentifier(button)] = owner }
                }
            }
            for child in view.subviews { collectEditors(child) }
        }
        collectEditors(content)
        func controlOwner(of object: AnyObject) -> ObjectIdentifier? {
            var current: AnyObject? = object
            var visited: Set<ObjectIdentifier> = []
            while let candidate = current, visited.insert(ObjectIdentifier(candidate)).inserted {
                if let owner = editorOwners[ObjectIdentifier(candidate)] ?? cellOwners[ObjectIdentifier(candidate)] { return owner }
                if let control = candidate as? NSControl { return ObjectIdentifier(control) }
                if let cell = candidate as? NSCell, let control = cell.controlView as? NSControl {
                    return ObjectIdentifier(control)
                }
                guard let semantic = candidate as? any NSAccessibilityProtocol,
                      let parent = semantic.accessibilityParent() else { return nil }
                current = parent as AnyObject
            }
            return nil
        }
        // Native descendants are walked before semantic proxies so an NSControl keeps its actual
        // clipping ancestry even when an ancestor also exposes it through accessibilityChildren.
        func walk(_ object: AnyObject, ancestors: Set<ObjectIdentifier>, nativeClip: CGRect?,
                  scrollViewport: CGRect?, inheritedOwner: ObjectIdentifier?) {
            let identity = ObjectIdentifier(object)
            guard seen.insert(identity).inserted else { return }
            let native = object as? NSView
            if let native, native.isHiddenOrHasHiddenAncestor || native.alphaValue <= 0 { return }
            // Reparented cell proxies need not retain the original NSCell identity or parent.
            // Their ownership still follows the native control whose child traversal exposes them.
            let owner = controlOwner(of: object) ?? inheritedOwner
            let semantic = object as? any NSAccessibilityProtocol
            let role = semantic?.accessibilityRole()
            let isScroll = native is NSScrollView || native is NSClipView || role == .scrollArea
            var clip = nativeClip
            var viewport = scrollViewport
            if isScroll {
                let own = native.map { screenFrame($0, $0.bounds) } ?? semantic?.accessibilityFrame()
                if let own, own.width > 0, own.height > 0 {
                    viewport = viewport.map { $0.intersection(own) } ?? own
                }
            } else if let native, native.clipsToBounds {
                let own = screenFrame(native, native.bounds)
                clip = clip.map { $0.intersection(own) } ?? own
            }
            // Ignored backing controls can share a frame with the exposed semantic control.
            // Keep traversing them for ancestry and children, but do not count them a second time.
            if let semantic, semantic.isAccessibilityElement() {
                // AppKit's button-cell semantic frame includes an extra hit/focus fringe.
                // Layout containment uses the owning button's actual bounds, not that fringe.
                let frame: CGRect
                if role == .button, let owner, let button = controls[owner] as? NSButton {
                    frame = screenFrame(button, button.bounds)
                } else { frame = semantic.accessibilityFrame() }
                let isText = role == .staticText || native is NSTextField || native is NSTextView
                let isControl = role.map { interactiveRoles.contains($0) } ?? (native is NSControl)
                let name = [semantic.accessibilityLabel(), semantic.accessibilityTitle(),
                            semantic.accessibilityValue() as? String]
                    .compactMap { $0 }
                    .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    ?? native.map { String(describing: type(of: $0)) }
                    ?? role?.rawValue ?? "view"
                let kind = "\(String(describing: type(of: object)))/\(role?.rawValue ?? "untyped")"
                if (isText || isControl), frame.width > 0.5, frame.height > 0.5,
                   frame.origin.x.isFinite, frame.origin.y.isFinite {
                    result.append(Element(identity: identity, ancestors: ancestors,
                                          controlOwner: owner, name: name,
                                          kind: kind, frame: frame, interactive: isControl, text: isText,
                                          clip: nativeClip, scrollViewport: scrollViewport,
                                          nativeText: native as? NSTextField))
                }
            }
            var next = ancestors
            next.insert(identity)
            if let native {
                for child in native.subviews {
                    walk(child, ancestors: next, nativeClip: clip, scrollViewport: viewport, inheritedOwner: owner)
                }
            }
            for child in semantic?.accessibilityChildren() ?? [] {
                walk(child as AnyObject, ancestors: next, nativeClip: clip, scrollViewport: viewport, inheritedOwner: owner)
            }
        }
        walk(content, ancestors: [], nativeClip: nil, scrollViewport: nil, inheritedOwner: nil)
        // A native control and its semantic proxy sometimes describe the same visible object.
        var unique: [Element] = []
        for element in result {
            if let owner = element.controlOwner,
               unique.contains(where: { $0.controlOwner == owner && $0.name == element.name
                   && $0.interactive == element.interactive && approximatelyEqual($0.frame, element.frame) }) { continue }
            unique.append(element)
        }
        return unique
    }

    private static func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    private static func intersects(_ a: CGRect, _ b: CGRect) -> Bool {
        let intersection = a.intersection(b)
        return !intersection.isNull && intersection.width > 0.5 && intersection.height > 0.5
    }

    private static func contains(_ outer: CGRect, _ inner: CGRect) -> Bool {
        outer.insetBy(dx: -0.5, dy: -0.5).contains(inner)
    }

    private static func toolbarOwns(_ element: Element, _ snapshot: Snapshot) -> Bool {
        // A content control can occupy exactly the same pixels as a toolbar item. Geometric
        // containment alone would hide that collision, so only actual toolbar descendants qualify.
        snapshot.toolbarOwners.contains(element.identity)
            || !snapshot.toolbarOwners.isDisjoint(with: element.ancestors)
    }

    private static func chrome(_ snapshot: Snapshot) -> [Violation] {
        snapshot.elements.flatMap { element -> [Violation] in
            guard !toolbarOwns(element, snapshot), !element.visibleFrame.isNull else { return [] }
            let frame = element.visibleFrame
            var findings: [Violation] = []
            if intersects(frame, snapshot.geometry.chromeBand)
                || snapshot.geometry.trafficLights.contains(where: { intersects(frame, $0) }) {
                findings.append(Violation(rule: "chrome", view: element.name,
                                          message: "intersects the window chrome or traffic-light zone"))
            }
            for bar in snapshot.reports.bottomBars where intersects(frame, bar) && !contains(bar, frame) {
                findings.append(Violation(rule: "bottom-bar", view: element.name,
                                          message: "crosses a bottom bar's content boundary (control \(frame), bar \(bar))"))
            }
            return findings
        }
    }

    private static func bounds(_ snapshot: Snapshot) -> [Violation] {
        snapshot.elements.flatMap { element -> [Violation] in
            // Scrolling intentionally clips at its viewport; it must not suppress clipping by
            // other ancestors, or a viewport itself extending past the usable window bounds.
            guard !toolbarOwns(element, snapshot), !element.visibleFrame.isNull else { return [] }
            let frame = element.visibleFrame
            var findings: [Violation] = []
            if !contains(snapshot.geometry.contentBounds, frame) {
                findings.append(Violation(rule: "content-bounds", view: element.name,
                                          message: "extends beyond the window content bounds"))
            }
            if let clip = element.clip, !contains(clip, frame) {
                findings.append(Violation(rule: "ancestor-clip", view: element.name,
                                          message: "is clipped by an ancestor"))
            }
            return findings
        }
    }

    private static func overlaps(_ snapshot: Snapshot) -> [Violation] {
        let controls = snapshot.elements.filter { $0.interactive && !toolbarOwns($0, snapshot) }
        var findings: [Violation] = []
        for (index, first) in controls.enumerated() {
            for second in controls.dropFirst(index + 1) {
                // Search-field icon cells, text cells and their active field editor belong to one
                // control. Only a proven common owner exempts them; unrelated controls still collide.
                if let owner = first.controlOwner, owner == second.controlOwner { continue }
                // A search icon/cancel button is a real child NSButton of the search control.
                // Its cell and the enclosing field/editor are exposed as semantic siblings.
                // Restore the proven native parent-child relation without exempting sibling controls.
                if let owner = first.controlOwner, second.ancestors.contains(owner) { continue }
                if let owner = second.controlOwner, first.ancestors.contains(owner) { continue }
                guard !first.ancestors.contains(second.identity), !second.ancestors.contains(first.identity),
                      intersects(first.visibleFrame, second.visibleFrame) else { continue }
                // Offscreen rows in native scroll containers are intentionally laid out beyond the viewport.
                if !intersects(first.visibleFrame, snapshot.geometry.contentBounds)
                    || !intersects(second.visibleFrame, snapshot.geometry.contentBounds) { continue }
                findings.append(Violation(rule: "control-overlap", view: first.name,
                                          message: "overlaps interactive control “\(second.name)” (\(first.kind) \(first.visibleFrame); \(second.kind) \(second.visibleFrame))"))
            }
        }
        return findings
    }

    private static func edges(_ snapshot: Snapshot) -> [Violation] {
        guard !snapshot.reports.ownsTopBar else { return [] }
        let content = snapshot.geometry.contentBounds
        let elements = snapshot.elements.filter { !toolbarOwns($0, snapshot) && !$0.visibleFrame.isNull }
        var findings: [Violation] = []
        if elements.filter(\.interactive).count == 1,
           let lone = elements.first(where: \.interactive),
           abs(lone.visibleFrame.midX - content.midX) < 1,
           content.maxY - lone.visibleFrame.maxY < 0.5 {
            findings.append(Violation(rule: "top-edge", view: lone.name,
                                      message: "floats at the top edge without a content margin"))
        }
        if let margin = snapshot.reports.pageMargin, margin > 0 {
            for element in elements {
                let frame = element.visibleFrame
                let owner = LumenScaffoldMargin.owner(at: CGPoint(x: frame.midX, y: frame.midY),
                                                      in: snapshot.reports.scaffoldMargins)
                let bounds = owner?.frame ?? content
                let declared = owner?.margin ?? margin
                guard frame.minX - bounds.minX < declared - 0.5
                    || bounds.maxX - frame.maxX < declared - 0.5 else { continue }
                findings.append(Violation(rule: "page-edge", view: element.name,
                                          message: "extends into the declared page margin"))
            }
        }
        return findings
    }

    private static func overflow(_ snapshot: Snapshot) -> [Violation] {
        var findings: [Violation] = []
        let usable = snapshot.geometry.contentBounds
        if snapshot.reports.minimumGrowthHasNoScreen {
            findings.append(Violation(rule: "content-minimum-no-screen", view: "window root",
                                      message: "no screen available; content minimum growth is unclamped"))
        }
        if snapshot.reports.contentMinimumExceedsScreen {
            findings.append(Violation(rule: "content-minimum-screen", view: snapshot.reports.contentMinimumView,
                                      message: "content minimum exceeds screen"))
        }
        if let minimum = snapshot.reports.contentMinimum,
           (minimum.width > usable.width + 0.5 || minimum.height > usable.height + 0.5),
           !(snapshot.reports.overflowIsReachable && snapshot.reports.minimumEnforced) {
            findings.append(Violation(rule: "content-minimum", view: "window root",
                                      message: "content's minimum size exceeds the window's usable region"))
        }
        if let frame = snapshot.reports.contentFrame, frame.maxY > usable.maxY + 0.5 {
            findings.append(Violation(rule: "content-top", view: "window root",
                                      message: "content top lies above the usable region"))
        }
        return findings
    }

    private static func truncation(_ snapshot: Snapshot) -> [Violation] {
        var findings = snapshot.reports.truncated.sorted().map {
            Violation(rule: "text-truncation", view: $0, message: "primary text is truncated")
        }
        for element in snapshot.elements {
            guard let field = element.nativeText, !field.isEditable, let cell = field.cell,
                  field.maximumNumberOfLines == 1, !field.stringValue.isEmpty else { continue }
            let natural = cell.cellSize
            if natural.width > field.bounds.width + 0.5 || natural.height > field.bounds.height + 0.5 {
                findings.append(Violation(rule: "text-truncation", view: element.name,
                                          message: "native text exceeds its rendered frame"))
            }
        }
        let grouped = Dictionary(grouping: snapshot.reports.visibleTexts, by: \.column)
        for (column, entries) in grouped {
            for (visible, values) in Dictionary(grouping: entries, by: \.visible)
                where Set(values.map(\.text)).count > 1 {
                findings.append(Violation(rule: "text-ambiguity", view: column,
                                          message: "different values display the same text “\(visible)”"))
            }
        }
        return findings
    }
}

#if DEBUG
/// No observer, timers or logging state is compiled into release builds.
@MainActor
final class LumenLayoutAuditObserver: NSObject {
    private static var shared: LumenLayoutAuditObserver?
    private let windows = NSMapTable<NSWindow, State>.weakToStrongObjects()
    private let logger = Logger(subsystem: "LumenUI", category: "layout-audit")

    private final class State {
        var pending: Task<Void, Never>?
        var reported: Set<LumenLayoutAudit.Violation> = []
        var renderedState: Int?
        var analysisKey: Int?
        var analysis: Task<LumenRenderedAudit.Result, Error>?
    }

    static func start() {
        guard shared == nil else { return }
        let observer = LumenLayoutAuditObserver()
        shared = observer
        for name in [NSWindow.didExposeNotification, NSWindow.didResizeNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            NotificationCenter.default.addObserver(observer, selector: #selector(windowChanged(_:)),
                                                   name: name, object: nil)
        }
        for window in NSApp?.windows ?? [] { observer.schedule(window) }
    }

    @objc private func windowChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        schedule(window)
    }

    private func schedule(_ window: NSWindow) {
        let state = windows.object(forKey: window) ?? State()
        windows.setObject(state, forKey: window)
        state.pending?.cancel()
        state.pending = Task { @MainActor [weak self, weak window, weak state] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard let self, let window, let state, window.isVisible, !Task.isCancelled else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            var findings = LumenLayoutAudit.findings(in: window)
            do {
                let capture = try LumenRenderedAudit.capture(in: window)
                let key = capture.stateKey
                if state.renderedState != key {
                    if let previous = state.analysis, state.analysisKey != key || previous.isCancelled {
                        previous.cancel()
                        _ = try? await previous.value
                        guard !Task.isCancelled else { return }
                        state.analysis = nil
                        state.analysisKey = nil
                    }
                    if state.analysis == nil {
                        state.analysisKey = key
                        state.analysis = Task.detached(priority: .utility) {
                            try LumenRenderedAudit.analyze(capture)
                        }
                    }
                    guard let analysis = state.analysis else { return }
                    let result = try await analysis.value
                    guard !Task.isCancelled, window.isVisible else { return }
                    state.renderedState = key
                    findings += result.findings
                }
            } catch is CancellationError {
                return
            } catch {
                findings.append(.init(rule: "rendered-capture", view: window.title,
                                      message: "rendered audit unavailable: \(error)"))
            }
            guard !Task.isCancelled else { return }
            for finding in findings where state.reported.insert(finding).inserted {
                let name = window.title.isEmpty ? String(describing: type(of: window)) : window.title
                self.logger.fault("\(name, privacy: .public) · \(finding.view, privacy: .public): \(finding.rule, privacy: .public): \(finding.message, privacy: .public)")
            }
            state.pending = nil
        }
    }
}
#endif
