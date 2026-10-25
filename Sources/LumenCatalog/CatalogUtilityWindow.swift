import SwiftUI
import LumenTokens
import LumenUI

/// Opens the complete single-window utility, including its native toolbar and resize behavior.
struct UtilityWindowPage: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Utility Window", summary: "A file source list, a content table, a tag inspector and a progress status share one utility window. Its optional side panes make room as the window narrows.")
            Button("Open Utility Window", systemImage: "macwindow") { openWindow(id: "utility") }
                .buttonStyle(.lumenPrimary)
            Text("Use the toolbar to switch between sparse and populated content, or drawn and glass chrome. Resize the window to see the scaffold adapt.")
                .foregroundStyle(.lumen(.fgSecondary))
                .lumenWrapsWithoutTruncating()
        }
    }
}

/// Generic file metadata only: the demo never reads an external file or uses patient data.
struct CatalogUtilityWindow: View {
    static let minimumSize = CGSize(width: 640, height: 400)
    static let defaultSize = CGSize(width: 1120, height: 680)

    @State private var panels = LumenUtilityPanels()
    @State private var selection: String? = "sample-01"
    @State private var sparse: Bool

    init(sparse: Bool = false) {
        _sparse = State(initialValue: sparse)
    }

    private var files: [UtilityDemoFile] { sparse ? Array(UtilityDemoFile.samples.prefix(1)) : UtilityDemoFile.samples }

    var body: some View {
        LumenUtilityWindow(panels: $panels, minimumSize: Self.minimumSize) {
            UtilityFileTable(files: files, selection: $selection)
        } sidebar: {
            LumenSourceList(sections: [LumenSourceListSection("Source Files", items: files.map {
                LumenSourceListItem(id: $0.id, title: $0.name, detail: $0.kind, systemImage: "doc", hue: .hueTeal)
            })], selection: $selection)
        } inspector: {
            UtilityTagInspector(file: files.first { $0.id == selection })
        } statusBar: {
            Text("\(files.count) files")
            Spacer(minLength: 8)
            Text(sparse ? "Reviewing 1 of 1" : "Reviewing 2 of 4")
            LumenProgressBar(sparse ? 1 : 0.5).frame(width: 96)
        } topLeading: {
            LumenToolbarIdentity("File Utility", systemImage: "doc.on.doc", hue: .hueTeal)
        } topTrailing: {
            Button(sparse ? "Show Populated Content" : "Show Sparse Content", systemImage: sparse ? "list.bullet" : "rectangle.compress.vertical") {
                sparse.toggle()
                if sparse { selection = UtilityDemoFile.samples.first?.id }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(LumenToolbarIconButtonStyle())
            .help(sparse ? "Show Populated Content" : "Show Sparse Content")
            CatalogChromeToggle()
        }
        .contentMinimumWidth(640)
        .columnWidths(sidebar: (200, 220, 300), inspector: (240, 280, 360))
    }
}

private struct UtilityDemoFile: Identifiable {
    let id: String
    let name: String
    let kind: String
    let size: String
    let state: String

    static let samples = [
        UtilityDemoFile(id: "sample-01", name: "Sample 01.dcm", kind: "Image", size: "512 KB", state: "Ready"),
        UtilityDemoFile(id: "sample-02", name: "Sample 02.dcm", kind: "Image", size: "512 KB", state: "Ready"),
        UtilityDemoFile(id: "sample-03", name: "Sample 03.dcm", kind: "Image", size: "256 KB", state: "Review"),
        UtilityDemoFile(id: "sample-04", name: "Sample 04.dcm", kind: "Image", size: "256 KB", state: "Queued"),
    ]
}

private struct UtilityFileTable: View {
    let files: [UtilityDemoFile]
    @Binding var selection: String?
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.s4) {
            LumenSectionHeader("File Review")
            LumenTable(files, selection: $selection, minHeight: 160, columns: [
                LumenTableColumn("File") { LumenTableText($0.name) }.minWidth(120).priority(1),
                LumenTableColumn("Size", width: 64) { LumenTableText($0.size) },
                LumenTableColumn("State", width: 64) { LumenTableText($0.state) },
            ])
            Spacer(minLength: 0)
        }
        .padding(metrics.spacing.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct UtilityTagInspector: View {
    let file: UtilityDemoFile?

    var body: some View {
        LumenInspectorHeader("Tags", subtitle: file?.name ?? "No file selected", systemImage: "tag", hue: .hueTeal)
        if let file {
            LumenInspectorSection("File", systemImage: "doc", hue: .hueTeal) {
                LumenInspectorRow("Type") { Text(file.kind) }
                LumenInspectorRow("Size") { Text(file.size) }
                LumenInspectorRow("State") { Text(file.state) }
            }
            LumenInspectorSection("Image Tags", systemImage: "square.grid.2x2", hue: .hueBlue) {
                LumenInspectorRow("Rows") { Text("512") }
                LumenInspectorRow("Columns") { Text("512") }
                LumenInspectorRow("Bits") { Text("16") }
                LumenInspectorRow("Encoding") { Text("Explicit VR") }
            }
        }
    }
}
