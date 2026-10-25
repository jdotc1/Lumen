import SwiftUI
import XCTest
import LumenTokens
import LumenUI

@MainActor final class LumenRichTextGoldenTests: XCTestCase {
    func testRichTextAndSortableResizableTable() {
        let registry = LumenRegistry.core
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens")
        let variants = LumenSnapshot.Variant.all(for: registry.galleryThemes)
        XCTAssertEqual(variants.count, 6)
        for variant in variants {
            check(RichTextSubject(), name: "rich-text", variant: variant, registry: registry, directory: directory)
        }
        let standard = LumenSnapshot.Variant(themeID: LumenThemes.standardID, colorScheme: .light)
        check(RichTextSubject().lumenTextScale(1.3), name: "rich-text-scale-1.3",
              variant: standard, registry: registry, directory: directory)
        check(RichTextSubject().environment(\.lumenDensity, .compact), name: "rich-text-compact",
              variant: standard, registry: registry, directory: directory)
    }

    private func check<V: View>(_ view: V, name: String, variant: LumenSnapshot.Variant,
                               registry: LumenRegistry, directory: URL) {
        let outcome = LumenSnapshot.verify(view, named: name, size: CGSize(width: 760, height: 500),
            variant: variant, registry: registry, goldenDirectory: directory, renderer: .window)
        if let message = outcome.failureMessage { XCTFail("\(variant.label): \(message)") }
    }
}

private struct RichTextSubject: View {
    struct Record: Identifiable { let id: Int; let name: String; let count: Int }
    let rows = [Record(id: 1, name: "Draft chapters", count: 4), Record(id: 2, name: "Research notes", count: 12),
                Record(id: 3, name: "Review comments", count: 8)]
    @State private var selection: Int? = 2
    @State private var order = [LumenTableSort(column: "Name", ascending: true)]
    @State private var widths: [String: CGFloat] = ["Name": 300]
    @State private var text: AttributedString = {
        var bold = AttributedString("Research notes")
        bold.inlinePresentationIntent = .stronglyEmphasized
        var italic = AttributedString("ready for review")
        italic.inlinePresentationIntent = .emphasized
        return bold + AttributedString(" are ") + italic + AttributedString(".\nA second paragraph keeps ordinary text alongside the mixed runs.")
    }()
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s4) {
            Text("Sortable table · resized Name column").font(metrics.typography.headline)
            LumenTable(rows, selection: $selection, sortOrder: $order, columnWidths: $widths,
                       height: .fitRows(maxVisible: 4), columns: [
                LumenTableColumn("Name") { LumenTableText($0.name) }.minWidth(160).sortable(),
                LumenTableColumn("Count") { LumenTableText(String($0.count)) }.minWidth(80).sortable(),
                LumenTableColumn("State") { _ in LumenTableText("Ready") }.minWidth(80),
            ])
            Text("Rich text · native formatting and compact bar").font(metrics.typography.headline)
            LumenRichTextView(text: $text, maxHeight: 150, showsFormatBar: true)
            Text("Disabled rich text").font(metrics.typography.headline)
            LumenRichTextView(text: .constant(AttributedString("Read-only notes remain legible.")), maxHeight: 80).disabled(true)
            Spacer(minLength: 0)
        }
        .padding(24)
    }
}
