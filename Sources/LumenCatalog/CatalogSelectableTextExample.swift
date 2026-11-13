import SwiftUI
import LumenUI

/// Selectable large text with an exact-range highlight and reveal.
struct CatalogSelectableTextExample: View {
    private static let report = (1...2_000).map { "Line \($0): analysis step \($0 % 7) finished" }.joined(separator: "\n")
    @State private var match = 0
    @State private var revealID = 0

    private var ranges: [NSRange] {
        let text = Self.report as NSString
        var found: [NSRange] = []
        var search = NSRange(location: 0, length: text.length)
        while found.count < 400 {
            let next = text.range(of: "step 3", range: search)
            if next.location == NSNotFound { break }
            found.append(next)
            search = NSRange(location: next.upperBound, length: text.length - next.upperBound)
        }
        return found
    }

    var body: some View {
        let all = ranges
        let current = all.isEmpty ? nil : all[min(match, all.count - 1)]
        VStack(alignment: .leading, spacing: 8) {
            LumenSectionHeader("Selectable text")
            LumenSelectableText(Self.report,
                                highlights: all.map { LumenTextHighlight($0, role: .match) } + (current.map { [LumenTextHighlight($0, role: .current)] } ?? []),
                                reveal: current.map { LumenTextReveal($0, id: revealID) },
                                accessibilityLabel: "Report text")
                .frame(height: 160)
            Button("Next “step 3”") {
                match = (match + 1) % max(1, all.count)
                revealID += 1
            }
            Text("Read-only text that selects and copies across lines. The host marks exact ranges and scrolls them into view.")
                .font(.caption).foregroundStyle(.lumen(.fgSecondary))
        }
    }
}

private extension NSRange {
    var upperBound: Int { location + length }
}
