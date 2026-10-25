import SwiftUI

extension EnvironmentValues {
    @Entry var lumenSidebarRows = false
    @Entry var lumenSidebarRowInset: CGFloat = 0
}

/// Reserves the selected title's width, as the toolbar reserves its widest percentage.
/// Only the visible title changes weight; subtitles and trailing counts keep their own fonts.
struct LumenSidebarTitle: View {
    let title: String
    let font: Font
    let isSelected: Bool
    var reservesSelectionWidth = true

    init(_ title: String, font: Font, isSelected: Bool, reservesSelectionWidth: Bool = true) {
        self.title = title
        self.font = font
        self.isSelected = isSelected
        self.reservesSelectionWidth = reservesSelectionWidth
    }

    var body: some View {
        if reservesSelectionWidth {
            Text(title)
                .font(font.weight(.semibold))
                .lineLimit(1).truncationMode(.middle)
                .hidden()
                .accessibilityHidden(true)
                .overlay(alignment: .leading) {
                    Text(title)
                        .font(isSelected ? font.weight(.semibold) : font)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
        } else {
            Text(title).font(font).lineLimit(1).truncationMode(.middle)
        }
    }
}

public extension View {
    /// Keeps a sidebar row's visible fill inset while its hit area spans the column.
    /// Apply before adding a gesture; the inset is inside `LumenListRow`'s content shape.
    func lumenSidebarRowInset(_ inset: CGFloat) -> some View {
        environment(\.lumenSidebarRowInset, max(0, inset))
    }
}
