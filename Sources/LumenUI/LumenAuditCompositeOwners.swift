#if DEBUG
import AppKit

/// Retains measured container geometry separately from actionable/text elements. Native controls
/// may also appear through semantic proxies; both paths contribute ancestry, never extra ink.
@MainActor enum LumenAuditCompositeOwners {
    static func collect(in window: NSWindow, elements: [LumenRenderedAudit.Element])
        -> (elements: [LumenRenderedAudit.Element], containers: [LumenRenderedAudit.Element]) {
        guard let root = window.contentView else { return (elements, []) }
        var parents: [String: Set<String>] = [:]
        var containers: [String: LumenRenderedAudit.Element] = [:]
        var visited = Set<String>()
        var aliases: [String: String] = [:]
        var declarations: [LumenRenderedAudit.Element] = []
        func identity(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }
        func nativeOwners(_ view: NSView) {
            if let control = view as? NSControl {
                let owner = identity(control)
                if let editor = control.currentEditor() { aliases[identity(editor)] = owner }
                if let cell = control.cell { aliases[identity(cell)] = owner }
            }
            for child in view.subviews { nativeOwners(child) }
        }
        nativeOwners(root)
        func walk(_ object: AnyObject, parent: String?) {
            let key = identity(object)
            if let parent, parent != key { parents[key, default: []].insert(parent) }
            guard visited.insert(key).inserted else { return }
            let native = object as? NSView
            if let native, native.isHiddenOrHasHiddenAncestor || native.alphaValue <= 0 { return }
            let semantic = object as? any NSAccessibilityProtocol
            let frame = native.map { window.convertToScreen($0.convert($0.bounds, to: nil)) }
                ?? semantic?.accessibilityFrame()
            if native is LumenTextCompositeView, let frame, !frame.isEmpty {
                var clip: CGRect?
                var ancestor = native?.superview
                while let view = ancestor, view !== root {
                    if view.clipsToBounds {
                        let bounds = window.convertToScreen(view.convert(view.bounds, to: nil))
                        clip = clip.map { $0.intersection(bounds) } ?? bounds
                    }
                    ancestor = view.superview
                }
                declarations.append(.init(identity: "lumen-composite:" + key, ancestors: [],
                    frame: frame, source: "", control: false, clip: clip))
            }
            let nativeChildren = native?.subviews.map { $0 as AnyObject } ?? []
            let semanticChildren = (semantic?.accessibilityChildren() ?? []).map { $0 as AnyObject }
            if key != identity(root), let frame, !frame.isEmpty, frame.origin.x.isFinite, frame.origin.y.isFinite,
               !nativeChildren.isEmpty || !semanticChildren.isEmpty {
                containers[key] = .init(identity: key, ancestors: [], frame: frame,
                                        source: "", control: false, clip: nil)
            }
            for child in nativeChildren + semanticChildren { walk(child, parent: key) }
        }
        walk(root, parent: nil)
        // Editor/cell aliases keep their semantic ancestry attached to the owning control.
        for (alias, owner) in aliases {
            parents[owner, default: []].formUnion(parents[alias, default: []].filter { $0 != owner })
        }
        func ancestry(_ key: String) -> Set<String> {
            var result = Set<String>()
            var pending = Array(parents[key, default: []])
            while let next = pending.popLast() {
                guard next != key, result.insert(next).inserted else { continue }
                pending.append(contentsOf: parents[next, default: []])
            }
            return result
        }
        let enriched = elements.map { element in
            let declaredParents = declarations.filter {
                $0.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
            }.map(\.identity)
            return LumenRenderedAudit.Element(identity: element.identity,
                ancestors: element.ancestors.union(ancestry(element.identity)).union(declaredParents), frame: element.frame,
                source: element.source, control: element.control, clip: element.clip)
        }
        let measured = containers.values.map { container in
            LumenRenderedAudit.Element(identity: container.identity, ancestors: ancestry(container.identity),
                frame: container.frame, source: "", control: false, clip: nil)
        }
        return (enriched, measured + declarations)
    }
}
#endif
