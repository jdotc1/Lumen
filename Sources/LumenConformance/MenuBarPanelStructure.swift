import SwiftUI
import LumenUI

extension WindowStructureCheck {
    static func menuBarPanelMessages(_ entries: [LumenMenuBarPanelLayoutEntry], size: CGSize) -> [String] {
        guard let panel = entries.first(where: { $0.region == .panel }) else {
            return ["has no menu bar panel geometry; use LumenMenuBarPanel"]
        }
        var messages: [String] = []
        let bounds = panel.frame.insetBy(dx: -0.5, dy: -0.5)
        if panel.frame.width > size.width + 0.5 || panel.frame.height > size.height + 0.5 {
            messages.append("the menu bar panel exceeds its host bounds")
        }
        for (region, required) in [(LumenMenuBarPanelLayoutEntry.Region.header, panel.hasHeader),
                                   (.content, true), (.footer, panel.hasFooter)] where required {
            guard let entry = entries.first(where: { $0.region == region }), entry.frame.height > 0.5 else {
                messages.append("the supplied menu bar panel \(region) is missing")
                continue
            }
            if !bounds.contains(entry.frame) {
                messages.append("the menu bar panel \(region) exceeds the panel bounds")
            }
        }
        if let content = entries.first(where: { $0.region == .content }) {
            for entry in entries where entry.region == .scrollContent {
                if entry.frame.minX < content.frame.minX - 0.5 || entry.frame.maxX > content.frame.maxX + 0.5 {
                    messages.append("the menu bar panel scrolling content exceeds its width")
                }
            }
            if let header = entries.first(where: { $0.region == .header }), header.frame.maxY > content.frame.minY + 0.5 {
                messages.append("the menu bar panel header overlaps its content")
            }
            if let footer = entries.first(where: { $0.region == .footer }), footer.frame.minY < content.frame.maxY - 0.5 {
                messages.append("the menu bar panel footer overlaps its content")
            }
        }
        return messages
    }
}
