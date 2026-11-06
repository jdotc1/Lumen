@_spi(LumenStyleChecks) import LumenUI
import SwiftUI

public extension LumenConformance {
    /// Standard tab indicators use continuous rounded selection and hover shapes, without a
    /// separate accent bar. `requiredStrips` makes missing chrome reports a failure too.
    @MainActor
    static func tabStyle<Content: View>(sizes: [CGSize], requiring requiredStrips: Set<String> = [],
                                       of content: () -> Content) -> [Finding] {
        TabStyleCheck.evaluate(sizes: sizes, requiring: requiredStrips, of: content)
    }

    /// A rendered style check for the runner's subject, sizes and appearance variants.
    static func tabStyle(requiring requiredStrips: Set<String> = []) -> some LumenCheck {
        TabStyleCheck(requiredStrips: requiredStrips)
    }
}

struct TabStyleCheck: LumenCheck {
    let id = "lumen.tabStyle"
    let title = "Native tab style"
    let requiredStrips: Set<String>

    @MainActor
    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        guard context.subject != nil else { return [context.missingSubject(for: title)] }
        return context.withRenderedSubject { view, _ in
            Self.evaluate(sizes: context.sizes, requiring: requiredStrips) { view }
        }
    }

    @MainActor
    static func evaluate<Content: View>(sizes: [CGSize], requiring requiredStrips: Set<String>,
                                       of content: () -> Content) -> [LumenConformance.Finding] {
        sizes.flatMap { size in
            let entries = LumenConformance.layOut(content(), size: size).0.tabChrome
            return findings(entries, requiring: requiredStrips).map {
                LumenConformance.Finding($0.area, "\($0.subject) at \(Int(size.width))×\(Int(size.height))", $0.message)
            }
        }
    }

    static func findings(_ entries: Set<LumenTabChromeEntry>, requiring requiredStrips: Set<String>) -> [LumenConformance.Finding] {
        var findings: Set<LumenConformance.Finding> = []
        for entry in entries {
            if !entry.selectedRadius.isFinite || entry.selectedRadius <= 0 {
                findings.insert(.init(.layout, entry.strip, "tab selection indicator must be rounded"))
            }
            if !entry.hoverRadius.isFinite || entry.hoverRadius <= 0 {
                findings.insert(.init(.layout, entry.strip, "tab hover indicator must be rounded"))
            }
            if !entry.continuousCorners {
                findings.insert(.init(.layout, entry.strip, "tab indicators must use continuous corners"))
            }
            if entry.separateAccentBar {
                findings.insert(.init(.layout, entry.strip, "tab selection must not use a separate accent bar"))
            }
        }
        for strip in requiredStrips.subtracting(Set(entries.map(\.strip))) {
            findings.insert(.init(.layout, strip, "tab strip did not report its indicator geometry"))
        }
        return findings.sorted { ($0.subject, $0.message) < ($1.subject, $1.message) }
    }
}
