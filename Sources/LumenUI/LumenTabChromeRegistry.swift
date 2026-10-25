import SwiftUI

/// A rendered tab's indicator geometry, shared only with Lumen's conformance module.
/// Entries are preferences, so a check observes only its own hosted view tree.
@_spi(LumenStyleChecks)
public struct LumenTabChromeEntry: Hashable, Sendable {
    public let strip: String
    public let selectedRadius: CGFloat
    public let hoverRadius: CGFloat
    public let continuousCorners: Bool
    public let separateAccentBar: Bool

    public init(strip: String, selectedRadius: CGFloat, hoverRadius: CGFloat,
                continuousCorners: Bool = true, separateAccentBar: Bool = false) {
        self.strip = strip
        self.selectedRadius = selectedRadius
        self.hoverRadius = hoverRadius
        self.continuousCorners = continuousCorners
        self.separateAccentBar = separateAccentBar
    }
}

@_spi(LumenStyleChecks)
public struct LumenTabChromeRegistry: PreferenceKey {
    public static let defaultValue: Set<LumenTabChromeEntry> = []

    public static func reduce(value: inout Set<LumenTabChromeEntry>, nextValue: () -> Set<LumenTabChromeEntry>) {
        value.formUnion(nextValue())
    }
}

extension View {
    /// Called by the shared chrome with the same radii that construct its rendered shapes.
    func lumenTabChromeReport(strip: String, selectedRadius: CGFloat, hoverRadius: CGFloat,
                              continuousCorners: Bool = true, separateAccentBar: Bool = false) -> some View {
        preference(key: LumenTabChromeRegistry.self, value: [
            LumenTabChromeEntry(strip: strip, selectedRadius: selectedRadius, hoverRadius: hoverRadius,
                                continuousCorners: continuousCorners, separateAccentBar: separateAccentBar),
        ])
    }
}
