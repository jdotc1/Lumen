import SwiftUI
import LumenUI

extension WindowStructureCheck {
    static func wizardMessages(_ entries: [LumenWizardLayoutEntry], size: CGSize) -> [String] {
        typealias Region = LumenWizardLayoutEntry.Region
        let windows = entries.filter { $0.region == .window }
        guard let window = windows.first else {
            return ["has no wizard geometry; use LumenWizardWindow"]
        }
        var messages: [String] = []
        if windows.count != 1 { messages.append("the wizard must report exactly one window") }
        let bounds = window.frame.insetBy(dx: -0.5, dy: -0.5)
        if window.frame.width > size.width + 0.5 || window.frame.height > size.height + 0.5 {
            messages.append("the wizard exceeds its host bounds")
        }
        let pageRegion: Region = window.pageCount > 0 ? .currentPage : .emptyState
        let pages = entries.filter { $0.region == .currentPage }
        if pages.count != (window.pageCount > 0 ? 1 : 0) {
            messages.append("the wizard must report exactly one current page when pages are present, and none when empty")
        }
        var regions: [Region: LumenWizardLayoutEntry] = [:]
        for region in [Region.stepList, pageRegion, .bottomBar, .cancelButton, .backButton, .continueButton] {
            let matches = entries.filter { $0.region == region }
            guard let entry = matches.first, matches.count == 1,
                  entry.frame.width > 0.5, entry.frame.height > 0.5 else {
                messages.append("the wizard \(region) is missing or duplicated")
                continue
            }
            regions[region] = entry
            if !bounds.contains(entry.frame) {
                messages.append("the wizard \(region) exceeds the window bounds")
            }
        }
        let contentRegions = [Region.stepList, pageRegion, .bottomBar]
        for (index, first) in contentRegions.enumerated() {
            for second in contentRegions.dropFirst(index + 1) {
                if let a = regions[first], let b = regions[second], overlaps(a.frame, b.frame) {
                    messages.append("the wizard \(first) overlaps its \(second)")
                }
            }
        }
        if let steps = regions[.stepList], let page = regions[pageRegion], steps.frame.maxX > page.frame.minX + 0.5 {
            messages.append("the wizard step list must lead the page")
        }
        if let bar = regions[.bottomBar] {
            if abs(bar.frame.minX - window.frame.minX) > 0.5 || abs(bar.frame.maxX - window.frame.maxX) > 0.5 {
                messages.append("the wizard bottom bar must span the full window width")
            }
            if abs(bar.frame.maxY - window.frame.maxY) > 0.5 {
                messages.append("the wizard bottom bar must meet the bottom of the window")
            }
            let buttonRegions = [Region.cancelButton, .backButton, .continueButton]
            for (index, region) in buttonRegions.enumerated() {
                guard let button = regions[region] else { continue }
                if !bar.frame.insetBy(dx: -0.5, dy: -0.5).contains(button.frame) {
                    messages.append("the wizard \(region) exceeds the bottom bar bounds")
                }
                for otherRegion in buttonRegions.dropFirst(index + 1) {
                    if let other = regions[otherRegion], overlaps(button.frame, other.frame) {
                        messages.append("the wizard \(region) overlaps its \(otherRegion)")
                    }
                }
            }
        }
        if let next = regions[.continueButton] {
            if !next.isDefaultAction || entries.contains(where: { $0.region != .continueButton && $0.isDefaultAction }) {
                messages.append("Continue must be the wizard's only default action")
            }
            let preceding = [regions[.cancelButton], regions[.backButton]].compactMap { $0 }
            if next.frame.midX < window.frame.midX || preceding.contains(where: { $0.frame.maxX > next.frame.minX + 0.5 }) {
                messages.append("Continue must be the wizard's trailing button")
            }
        }
        return messages
    }

    private static func overlaps(_ first: CGRect, _ second: CGRect) -> Bool {
        let intersection = first.intersection(second)
        return !intersection.isNull && intersection.width > 0.5 && intersection.height > 0.5
    }
}
