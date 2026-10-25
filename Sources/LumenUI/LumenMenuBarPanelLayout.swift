import SwiftUI

/// Geometry reported by a menu bar panel for its structure check. Scroll content may be taller
/// than its viewport; its width must still fit. Frames use SwiftUI's global coordinate space.
public struct LumenMenuBarPanelLayoutEntry: Equatable, Sendable {
    public enum Region: Hashable, Sendable { case panel, header, content, scrollContent, footer }
    public let region: Region
    public let frame: CGRect
    public let hasHeader: Bool
    public let hasFooter: Bool

    public init(region: Region, frame: CGRect, hasHeader: Bool = false, hasFooter: Bool = false) {
        self.region = region
        self.frame = frame
        self.hasHeader = hasHeader
        self.hasFooter = hasFooter
    }
}

public struct LumenMenuBarPanelLayoutKey: PreferenceKey {
    public static let defaultValue: [LumenMenuBarPanelLayoutEntry] = []
    public static func reduce(value: inout [LumenMenuBarPanelLayoutEntry], nextValue: () -> [LumenMenuBarPanelLayoutEntry]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func menuBarPanelRegion(_ region: LumenMenuBarPanelLayoutEntry.Region,
                            hasHeader: Bool = false, hasFooter: Bool = false) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: LumenMenuBarPanelLayoutKey.self, value: [
                    .init(region: region, frame: geometry.frame(in: .global), hasHeader: hasHeader, hasFooter: hasFooter)
                ])
            }
        }
    }
}
