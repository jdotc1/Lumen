import SwiftUI

/// Measures once and places the same label and trailing control identities in either arrangement.
struct LumenSettingsRowLayout: Layout {
    let spacing: CGFloat

    private func controlSpacing(_ subviews: Subviews) -> [CGFloat] {
        subviews.indices.map { index in
            index > 1 ? subviews[index - 1].spacing.distance(to: subviews[index].spacing, along: .horizontal) : 0
        }
    }

    private func measure(width: CGFloat?, subviews: Subviews) -> (sizes: [CGSize], gaps: [CGFloat], vertical: Bool, width: CGFloat) {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let gaps = controlSpacing(subviews)
        let controlsWidth = ideal.dropFirst().reduce(0) { $0 + $1.width } + gaps.reduce(0, +)
        let labelGap = subviews.count > 1 ? spacing : 0
        let natural = (ideal.first?.width ?? 0) + labelGap + controlsWidth
        let vertical = subviews.count > 1 && natural > (width ?? .infinity)
        let width = width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? natural
        let controlBudget = max(0, width - gaps.reduce(0, +))
        let idealControls = ideal.dropFirst().reduce(0) { $0 + $1.width }
        let sizes = subviews.enumerated().map { index, child in
            let available = index == 0 ? (vertical ? width : max(0, width - controlsWidth - labelGap))
                : ideal[index].width * min(1, controlBudget / max(1, idealControls))
            return child.sizeThatFits(ProposedViewSize(width: available, height: nil))
        }
        return (sizes, gaps, vertical, width)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let layout = measure(width: proposal.width, subviews: subviews)
        let labelHeight = layout.sizes.first?.height ?? 0
        let controlHeight = layout.sizes.dropFirst().map(\.height).max() ?? 0
        return CGSize(width: layout.width, height: layout.vertical
            ? labelHeight + spacing + controlHeight : max(labelHeight, controlHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let layout = measure(width: bounds.width, subviews: subviews)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: layout.vertical ? bounds.minY : bounds.midY),
                          anchor: layout.vertical ? .topLeading : .leading,
                          proposal: ProposedViewSize(layout.sizes[0]))
        let controlHeight = layout.sizes.dropFirst().map(\.height).max() ?? 0
        let y = layout.vertical ? bounds.maxY - controlHeight / 2 : bounds.midY
        var x = bounds.maxX
        for index in subviews.indices.dropFirst().reversed() {
            subviews[index].place(at: CGPoint(x: x, y: y), anchor: .trailing,
                                  proposal: ProposedViewSize(layout.sizes[index]))
            x -= layout.sizes[index].width + layout.gaps[index]
        }
    }
}
