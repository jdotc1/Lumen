import SwiftUI
import LumenTokens
import LumenUI

struct LibraryWindowPage: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Library Window", summary: "Collections, search and filters surround a grid of images. A trailing detail pane follows the selection and makes room first as the window narrows.")
            Button("Open Library Window", systemImage: "photo.on.rectangle") { openWindow(id: "library") }
                .buttonStyle(.lumenPrimary)
            Text("Browse the sample collections, search by name, or filter favorites. Switch between sparse and populated content and drawn or glass chrome in the toolbar.")
                .foregroundStyle(.lumen(.fgSecondary))
                .lumenWrapsWithoutTruncating()
        }
    }
}

struct CatalogLibraryWindow: View {
    static let minimumSize = CGSize(width: 640, height: 400)
    static let defaultSize = CGSize(width: 1200, height: 720)

    @State private var panels = LumenLibraryPanels()
    @State private var selection: String? = "image-01"
    @State private var source: String? = "all"
    @State private var query = ""
    @State private var filter = "All"
    @State private var sort = LumenCollectionSort.title
    @State private var sparse: Bool

    init(sparse: Bool = false) { _sparse = State(initialValue: sparse) }

    private var items: [LibraryDemoImage] {
        LibraryDemoImage.filtered(source: source, query: query, filter: filter, sparse: sparse)
    }

    var body: some View {
        LumenLibraryWindow(panels: $panels, minimumSize: Self.minimumSize) {
            LibraryImageGrid(items: items.map(\.collectionItem), selection: $selection, sort: $sort)
        } sourceList: {
            LumenSourceList(sections: [LumenSourceListSection("Collections", items: [
                LumenSourceListItem(id: "all", title: "All Images", systemImage: "lumen.imageSeries", hue: .hueBlue),
                LumenSourceListItem(id: "Coast", title: "Coast", systemImage: "lumen.lens", hue: .hueTeal),
                LumenSourceListItem(id: "Garden", title: "Garden", systemImage: "lumen.imageSeries", hue: .hueGreen),
                LumenSourceListItem(id: "City", title: "City", systemImage: "lumen.imageSeries", hue: .hueOrange),
                LumenSourceListItem(id: "Studio", title: "Studio", systemImage: "lumen.lens", hue: .hueViolet),
            ])], selection: $source)
        } detail: {
            LibraryImageDetail(image: items.first { $0.id == selection })
        } filterChips: {
            LumenFilterChips(selection: $filter, options: ["All", "Favorites", "Recent"], title: { $0 })
        } statusBar: {
            Text("\(items.count) images")
            Spacer(minLength: 8)
            Text("\(items.contains { $0.id == selection } ? 1 : 0) selected")
        } topLeading: {
            LumenToolbarIdentity("Image Library", systemImage: "lumen.imageSeries", hue: .hueBlue)
        } topCenter: {
            LumenFilterField(text: $query, prompt: "Search images").frame(width: 160)
        } topTrailing: {
            Menu {
                Button("All Images") { filter = "All" }
                Button("Favorites") { filter = "Favorites" }
                Button("Recent") { filter = "Recent" }
            } label: {
                Label("Filter Images", systemImage: "line.3.horizontal.decrease.circle")
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Filter Images")
            Button(sparse ? "Show Populated Content" : "Show Sparse Content", systemImage: sparse ? "square.grid.2x2" : "rectangle.compress.vertical") {
                sparse.toggle()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(LumenToolbarIconButtonStyle())
            .help(sparse ? "Show Populated Content" : "Show Sparse Content")
            CatalogChromeToggle()
        }
        .columnWidths(sourceList: (180, 200, 280), detail: (260, 280, 380))
        .onChange(of: items.map(\.id)) { _, ids in
            if !ids.contains(selection ?? "") { selection = ids.first }
        }
    }
}

struct LibraryDemoImage: Identifiable {
    let id: String
    let title: String
    let collection: String
    let hue: LumenToken
    let symbol: String
    let favorite: Bool
    let recent: Bool

    var collectionItem: LumenCollectionItem {
        .init(id: id, title: title, detail: collection, systemImage: symbol, hue: hue)
    }

    static let samples: [Self] = (1...40).map { index in
        let group = (index - 1) % 4
        return Self(id: String(format: "image-%02d", index), title: String(format: "Image %02d", index),
                    collection: ["Coast", "Garden", "City", "Studio"][group],
                    hue: [.hueTeal, .hueGreen, .hueOrange, .hueViolet][group],
                    symbol: ["lumen.lens", "lumen.imageSeries", "lumen.imageSeries", "lumen.lens"][group],
                    favorite: index % 3 == 1, recent: index > 30)
    }

    static func filtered(source: String?, query: String, filter: String, sparse: Bool) -> [Self] {
        let candidates = sparse ? Array(samples.prefix(1)) : samples
        return candidates.filter {
            (source == nil || source == "all" || $0.collection == source)
                && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.collection.localizedCaseInsensitiveContains(query))
                && (filter != "Favorites" || $0.favorite) && (filter != "Recent" || $0.recent)
        }
    }
}

private struct LibraryImageGrid: View {
    let items: [LumenCollectionItem]
    @Binding var selection: String?
    @Binding var sort: LumenCollectionSort

    var body: some View {
        ScrollView {
            LumenCollection(items, mode: .grid, size: 100, selection: $selection, sort: $sort) { selection = $0.id }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                .lumenColumnContent("Image grid")
        }
    }
}

private struct LibraryImageDetail: View {
    let image: LibraryDemoImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let image {
                LumenDetailHeader(image.title, systemImage: image.symbol, hue: image.hue, categories: [image.collection])
                LumenInspectorSection("Image Metadata") {
                    LumenInspectorRow("Dimensions") { Text("2400 × 1600") }
                    LumenInspectorRow("Format") { Text("JPEG") }
                    LumenInspectorRow("Size") { Text("2.4 MB") }
                    LumenInspectorRow("Rating") { Text(image.favorite ? "Favorite" : "Unrated") }
                }
            } else {
                LumenDetailHeader("No Selection", systemImage: "lumen.imageSeries", hue: .hueBlue)
            }
        }
    }
}
