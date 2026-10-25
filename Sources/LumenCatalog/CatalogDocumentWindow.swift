import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LumenTokens
import LumenUI

/// Plain UTF-8 text, with SwiftUI owning file coordination, save, revert and close.
@Observable
final class CatalogTextDocument: Document {
    static let readableContentTypes: [UTType] = [.plainText]
    var text: String
    @ObservationIgnored let configuration: URLDocumentConfiguration?

    init(text: String = "", configuration: URLDocumentConfiguration? = nil) {
        self.text = text
        self.configuration = configuration
    }

    func reader(configuration: sending ReadConfiguration) -> sending FileWrapperDocumentReader<String> {
        FileWrapperDocumentReader(configuration) { try Self.decode($0) }
    }

    func writer(configuration: sending WriteConfiguration) -> sending FileWrapperDocumentWriter<String> {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in Self.encode(snapshot) }
    }

    @MainActor
    func apply(snapshot: sending String, previous: sending String?) async throws {
        text = snapshot
    }

    @MainActor
    func snapshot(contentType: UTType) async throws -> sending String { text }

    static func decode(_ wrapper: FileWrapper) throws -> String {
        guard wrapper.isRegularFile, let data = wrapper.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return text
    }

    static func encode(_ text: String) -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    @MainActor
    func replaceText(_ replacement: String, undoManager: UndoManager?) {
        guard replacement != text else { return }
        let previous = text
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated { document.replaceText(previous, undoManager: undoManager) }
        }
        text = replacement
    }
}

struct DocumentWindowPage: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Document Window", summary: "Plain-text documents with native save, revert and close. An optional inspector makes room as each document window narrows.")
            Button("Open Document Welcome", systemImage: "doc.text") { openWindow(id: "document-welcome") }
                .buttonStyle(.lumenPrimary)
            Text("Create or open a text document from the welcome window. Native window tabs follow your system preference. Save sample documents to a temporary folder.")
                .foregroundStyle(.lumen(.fgSecondary))
                .lumenWrapsWithoutTruncating()
        }
    }
}

struct CatalogDocumentWelcome: View {
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @State private var openError: String?

    var body: some View {
        LumenWelcomeView(appName: "Lumen Documents", tagline: "A quiet space for plain-text notes.",
                         markSymbol: "doc.text", markHue: .hueTeal, actions: [
            LumenWelcomeAction("New Document", subtitle: "Start a plain-text note", systemImage: "plus", hue: .hueTeal,
                               isPrimary: true) { newDocument(CatalogTextDocument()) },
            LumenWelcomeAction("Open Document…", subtitle: "Choose a text file", systemImage: "folder.fill", hue: .hueBlue) {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.plainText]
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.begin { response in
                    guard response == .OK, let url = panel.url else { return }
                    Task { @MainActor in
                        do { try await openDocument(at: url) }
                        catch { openError = error.localizedDescription }
                    }
                }
            },
        ])
        .focusedSceneValue(\.catalogNewDocument, { newDocument(CatalogTextDocument()) })
        .alert("Unable to Open Document", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK") { openError = nil }
        } message: { Text(openError ?? "") }
    }
}

struct CatalogDocumentWindow: View {
    static let minimumSize = CGSize(width: 640, height: 400)
    static let defaultSize = CGSize(width: 1120, height: 680)
    @Bindable var document: CatalogTextDocument
    @State private var inspectorPresented = true
    @State private var native = CatalogDocumentNativeState()
    @Environment(\.undoManager) private var undoManager
    @Environment(\.newDocument) private var newDocument
    @Environment(\.lumenMetrics) private var metrics

    var body: some View {
        LumenDocumentWindow(title: $native.title, isModified: native.isModified,
                            onRename: { native.document?.rename(nil) },
                            inspectorPresented: $inspectorPresented, minimumSize: Self.minimumSize) {
            TextEditor(text: Binding(get: { document.text }, set: { document.replaceText($0, undoManager: undoManager) }))
                .font(metrics.typography.body)
                .scrollContentBackground(.hidden)
                .padding(metrics.spacing.s5)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        } inspector: {
            LumenInspectorHeader("Document", subtitle: "Plain text", systemImage: "doc.text", hue: .hueTeal)
            LumenInspectorSection("Text") {
                LumenInspectorRow("Characters") { Text("\(document.text.count)") }
                LumenInspectorRow("Words") { Text("\(document.text.split(whereSeparator: \.isWhitespace).count)") }
                LumenInspectorRow("Encoding") { Text("UTF-8") }
            }
        } statusBar: {
            Text("\(document.text.count) characters")
            Spacer(minLength: 8)
            Text("Plain Text")
        } topTrailing: {
            CatalogChromeToggle()
        }
        .contentMinimumWidth(640)
        .inspectorWidth((240, 280, 360))
        .background(CatalogDocumentNativeBridge(state: native))
        .focusedSceneValue(\.catalogNewDocument, { newDocument(CatalogTextDocument()) })
    }
}

/// Observe the document window owned by DocumentGroup; never create a second document controller.
@Observable @MainActor
final class CatalogDocumentNativeState {
    var title = "Untitled"
    var isModified = false
    @ObservationIgnored weak var document: NSDocument?
}

private struct CatalogDocumentNativeBridge: NSViewRepresentable {
    let state: CatalogDocumentNativeState
    func makeNSView(context: Context) -> ObserverView { ObserverView(state: state) }
    func updateNSView(_ nsView: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        let state: CatalogDocumentNativeState
        private var observations: [NSKeyValueObservation] = []
        init(state: CatalogDocumentNativeState) { self.state = state; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observations.removeAll()
            guard let window else { return }
            observations = [
                window.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.refresh() }
                },
                window.observe(\.isDocumentEdited, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.refresh() }
                },
            ]
        }
        private func refresh() {
            guard let window else { return }
            state.document = window.windowController?.document as? NSDocument
            state.title = state.document?.displayName ?? window.title
            state.isModified = window.isDocumentEdited
        }
    }
}
