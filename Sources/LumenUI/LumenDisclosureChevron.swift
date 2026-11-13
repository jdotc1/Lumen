import SwiftUI

/// The chevron every Lumen disclosure draws: it points toward the trailing edge while collapsed and
/// down while expanded, in both layout directions, and turns between the two.
///
/// Whether SF Symbols' `chevron.left` and `chevron.right` mirror in right-to-left layout depends on
/// the rendering path (an offscreen `ImageRenderer` draws them unmirrored), and a call site that
/// swapped the name and negated the angle on top of that turned an expanded chevron up (design
/// review 2026-11 #22). So the glyph is pinned left-to-right here and only the angle follows the
/// direction: 0° (trailing in LTR), 180° (trailing in RTL), 90° (down) when expanded.
struct LumenDisclosureChevron: View {
    let isExpanded: Bool
    let size: CGFloat
    let weight: Font.Weight

    @Environment(\.layoutDirection) private var layoutDirection

    init(isExpanded: Bool, size: CGFloat, weight: Font.Weight = .bold) {
        self.isExpanded = isExpanded
        self.size = size
        self.weight = weight
    }

    var body: some View {
        LumenSymbol("chevron.right")
            .font(.system(size: size, weight: weight))
            .rotationEffect(.degrees(isExpanded ? 90 : (layoutDirection == .rightToLeft ? 180 : 0)))
            .environment(\.layoutDirection, .leftToRight)
    }
}
