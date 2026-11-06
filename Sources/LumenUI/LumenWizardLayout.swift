import SwiftUI

/// Geometry reported by a wizard for its structure check. Frames use SwiftUI's global
/// coordinate space; `currentPage` marks the visible page viewport, including its title.
public struct LumenWizardLayoutEntry: Equatable, Sendable {
    public enum Region: Hashable, Sendable {
        case window, stepList, currentPage, emptyState, bottomBar
        case cancelButton, backButton, continueButton
    }
    public let region: Region
    public let frame: CGRect
    public let pageCount: Int
    public let isDefaultAction: Bool

    public init(region: Region, frame: CGRect, pageCount: Int = 0, isDefaultAction: Bool = false) {
        self.region = region
        self.frame = frame
        self.pageCount = pageCount
        self.isDefaultAction = isDefaultAction
    }
}

public struct LumenWizardLayoutKey: PreferenceKey {
    public static let defaultValue: [LumenWizardLayoutEntry] = []
    public static func reduce(value: inout [LumenWizardLayoutEntry], nextValue: () -> [LumenWizardLayoutEntry]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func wizardRegion(_ region: LumenWizardLayoutEntry.Region,
                      pageCount: Int = 0, isDefaultAction: Bool = false) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: LumenWizardLayoutKey.self, value: [
                    .init(region: region, frame: geometry.frame(in: .global),
                          pageCount: pageCount, isDefaultAction: isDefaultAction)
                ])
            }
        }
    }
}
