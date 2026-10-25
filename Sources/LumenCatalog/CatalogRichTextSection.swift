import SwiftUI
import LumenUI

struct CatalogRichTextSection: View {
    private struct Record: Identifiable {
        let id: Int
        let name: String
        let count: Int
    }
    private let records = [Record(id: 1, name: "Research notes", count: 12),
                           Record(id: 2, name: "Draft chapters", count: 4),
                           Record(id: 3, name: "Review comments", count: 8)]
    @State private var selection: Int?
    @State private var sortOrder = [LumenTableSort(column: "Name", ascending: true)]
    @State private var widths: [String: CGFloat] = ["Name": 260]
    @State private var text: AttributedString = {
        var bold = AttributedString("Research notes")
        bold.inlinePresentationIntent = .stronglyEmphasized
        var italic = AttributedString("ready for review")
        italic.inlinePresentationIntent = .emphasized
        return bold + AttributedString(" are ") + italic + AttributedString(".\nSelect text and use the Format menu or the compact bar.")
    }()

    private var sortedRecords: [Record] {
        records.sorted { lhs, rhs in
            for key in sortOrder {
                switch key.column {
                case "Name" where lhs.name != rhs.name:
                    return key.ascending ? lhs.name < rhs.name : lhs.name > rhs.name
                case "Count" where lhs.count != rhs.count:
                    return key.ascending ? lhs.count < rhs.count : lhs.count > rhs.count
                default: continue
                }
            }
            return lhs.id < rhs.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LumenSectionHeader("Review and rich text")
            LumenTable(sortedRecords, selection: $selection, sortOrder: $sortOrder, columnWidths: $widths,
                       height: .fitRows(maxVisible: 4), columns: [
                LumenTableColumn("Name") { LumenTableText($0.name) }.minWidth(160).sortable(),
                LumenTableColumn("Count") { LumenTableText(String($0.count)) }.minWidth(80).sortable(),
            ])
            Text("Click a header to sort. Drag its divider to resize; double-click to restore the natural width.")
                .font(.caption).foregroundStyle(.lumen(.fgSecondary))
            LumenRichTextView(text: $text, maxHeight: 160, showsFormatBar: true)
            Text("Native rich text grows to its height limit. Format text with ⌘B, ⌘I, ⌘U or the Format menu; the list button opens the system list panel.")
                .font(.caption).foregroundStyle(.lumen(.fgSecondary))
        }
    }
}
