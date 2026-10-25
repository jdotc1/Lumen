import SwiftUI
import LumenUI
import LumenTokens

/// A sample workspace composed from the public Lumen API with synthetic data.
/// The demo performs no persistence or backend operations.
public struct SampleWorkspace: View {
    public static let minimumSize = CGSize(width: 1080, height: 680)
    public static let defaultSize = CGSize(width: 1440, height: 900)
    @State private var panels = LumenWorkspacePanels(leading: true, bottom: true, trailing: true)
    @State private var availableWidth = Self.minimumSize.width
    @State private var mode: SampleWorkspaceMode
    @State private var activity = LumenActivity.working("Analyzing Sample", progress: 0.42)

    public init(mode: SampleWorkspaceMode = .disassembly) {
        _mode = State(initialValue: mode)
    }

    public var body: some View {
        // Preserve the user's inspector preference while the documented width threshold
        // temporarily suppresses it. App policy, expressed using the public panels binding.
        let visiblePanels = Binding(
            get: { LumenWorkspacePanels(leading: panels.leading, bottom: panels.bottom,
                                       trailing: panels.trailing && availableWidth >= 1220) },
            set: { value in
                panels.leading = value.leading
                panels.bottom = value.bottom
                if availableWidth >= 1220 { panels.trailing = value.trailing }
            })
        LumenWorkspaceWindow(panels: visiblePanels) {
            SampleWorkspaceEditor(mode: $mode)
                .lumenBottomPanel(isPresented: $panels.bottom, contentMinHeight: 360, maxFraction: 0.25, maximumHeight: 360) {
                    SampleWorkspaceDebugger()
                }
        } sidebar: {
            SampleWorkspaceSidebar()
        } inspector: {
            SampleWorkspaceInspector(isEmpty: mode == .welcome)
        } topLeading: {
            SampleWorkspaceToolbar(activity: $activity, mode: $mode)
        } topCenter: {
            LumenToolbarStatus(activity)
        }
        .columnWidths(sidebar: (328, 328, 384), inspector: (280, 280, 320))
        .contentMinimumWidth(560)
        .bottomPanelToggle($panels.bottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        // This workspace composition's full-size host reserves two compact bands when deriving
        // its native minimum (80 pt on macOS 27). A 600 pt content floor yields 1080×680;
        // the focused live-window test guards the resulting minimum and visible columns.
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height - 2 * LumenLayout.unifiedTopBarHeight)
    }
}

public enum SampleWorkspaceMode: String, CaseIterable {
    case disassembly = "Disassembly", pseudocode = "Pseudocode", graph = "Graph", hex = "Hex", welcome = "Welcome"
    var symbol: String {
        switch self {
        case .disassembly: "lumen.disassembly"
        case .pseudocode: "lumen.pseudocode"
        case .graph: "lumen.callGraph"
        case .hex: "number"
        case .welcome: "sparkles"
        }
    }
    var hue: LumenToken {
        switch self {
        case .disassembly: .hueIndigo
        case .pseudocode: .huePink
        case .graph: .hueTeal
        case .hex: .hueOrange
        case .welcome: .huePink
        }
    }
}

private struct SampleWorkspaceToolbar: View {
    @Binding var activity: LumenActivity
    @Binding var mode: SampleWorkspaceMode
    @State private var slice = "arm64"
    @State private var launcher = false
    var body: some View {
        LumenWorkspaceToolbar {
            Button { launcher = true } label: {
                LumenIconTile("cpu", hue: .huePink, size: 20)
            }
            .buttonStyle(.lumenPlain)
            .lumenLaunchMenu(isPresented: $launcher, items: [
                LumenLaunchItem("Open Demo Binary", systemImage: "doc.fill", hue: .hueOrange) { mode = .disassembly },
                LumenLaunchItem("Empty Workspace", systemImage: "sparkles", hue: .huePink) { mode = .welcome },
            ])
        } project: {
            LumenToolbarIdentity("Sample", subtitle: "\(slice) · Mach-O", systemImage: "lumen.binaryFile", hue: .hueOrange)
        } tasks: {
            LumenTaskCluster([
                LumenTaskAction("Analyze", systemImage: "hammer.fill", hue: .hueOrange) {
                    activity = .succeeded("Demo analysis complete")
                },
                LumenTaskAction("Launch", systemImage: "play.fill", role: .start) { activity = .working("Demo running") },
                LumenTaskAction("Stop", systemImage: "stop.fill", role: .stop) { activity = .idle() },
            ], activity: activity)
        } configuration: {
            LumenPopUp(selection: $slice, options: ["arm64", "x86_64"], title: { $0 })
        }
    }
}

private struct SampleWorkspaceSidebar: View {
    @State private var tool = "project"
    @State private var selection: String? = "main"
    var body: some View {
        VStack(spacing: 12) {
            LumenSidebarSwitcher(selection: $tool, items: [
                LumenSidebarItem(id: "project", title: "Project", systemImage: "square.stack.3d.up.fill", hue: .huePink),
                LumenSidebarItem(id: "strings", title: "Strings", systemImage: "text.quote", hue: .hueOrange),
                LumenSidebarItem(id: "xrefs", title: "Xrefs", systemImage: "lumen.crossReference", hue: .hueTeal),
            ], shortcuts: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LumenSidebarHeader(tool == "project" ? "Project" : tool == "strings" ? "Strings" : "Xrefs",
                                       subtitle: "Sample Workspace", systemImage: "square.stack.3d.up.fill", hue: .huePink)
                    LumenStatsCard([LumenStat("Targets", count: 1), LumenStat("Functions", count: 3), LumenStat("Xrefs", count: 2)])
                    if tool == "project" {
                        LumenSidebarCountSection("Binaries", systemImage: "lumen.binaryFile", hue: .hueIndigo,
                                                 count: 1, emptyMessage: "No binaries") {
                            LumenListRow("Sample", detail: "arm64 · Mach-O", systemImage: "lumen.binaryFile")
                        }
                        LumenSidebarCountSection("Functions", systemImage: "lumen.pseudocode", hue: .hueBlue,
                                                 count: 3, emptyMessage: "No functions") {
                            ForEach(["main", "parse_header", "read_segment"], id: \.self) { name in
                                LumenListRow(name, systemImage: "lumen.pseudocode", isSelected: selection == name, context: .sidebar)
                                    .lumenSidebarRowInset(12)
                                    .padding(.horizontal, -12)
                                    .onTapGesture { selection = name }
                            }
                        }
                    } else if tool == "strings" {
                        LumenStringRow("Hello, Lumen!", address: 0x100004000, section: "__cstring", length: 16)
                    } else {
                        LumenSidebarCountSection("main", systemImage: "lumen.crossReference", hue: .hueTeal,
                                                 count: 2, emptyMessage: "No references") {
                            LumenReferenceRow("_start+12", kind: "call") {}
                            LumenReferenceRow("parse_header+24", kind: "call") {}
                        }
                    }
                }
                .padding(12)
                .lumenColumnContent("Sample workspace sidebar")
            }
        }
    }
}

private struct SampleWorkspaceEditor: View {
    @Binding var mode: SampleWorkspaceMode
    var body: some View {
        VStack(spacing: 0) {
            LumenContentTabBar {
                LumenModeSwitcher(selection: $mode, options: SampleWorkspaceMode.allCases, style: .underline,
                                  title: \.rawValue, systemImage: \.symbol, hue: \.hue)
            }
            if mode == .welcome {
                LumenEmptyHero("No binary open", message: "Open a macOS executable, app bundle, framework, or dylib to begin analysis.",
                               systemImage: "cpu", hue: .huePink,
                               primary: LumenBarAction("Open Binary…") { mode = .disassembly },
                               secondary: [LumenBarAction("Open Workspace…") { mode = .disassembly }],
                               recents: [LumenRecentItem(title: "Demo Workspace", detail: "Static sample", systemImage: "cpu", hue: .huePink)],
                               recentsTitle: "Recent Workspaces", onOpenRecent: { _ in mode = .disassembly })
            } else {
                LumenStatusStrip(status: LumenStripStatus("Ready", tone: .statusSuccess)) { Text("main") }
                ScrollView {
                    Group {
                        switch mode {
                        case .disassembly: SampleWorkspaceListing()
                        case .graph: SampleWorkspaceGraph()
                        case .pseudocode:
                            LumenCodeListing([[LumenCodeRun("int ", LumenToken.Code.keyword), LumenCodeRun("main() {")],
                                              [LumenCodeRun("    return 0;", LumenToken.Code.keyword)], [LumenCodeRun("}")]], currentLine: 1)
                        case .hex:
                            LumenHexDump(Array("Hello, Lumen!".utf8), baseAddress: 0x100004000, selection: .constant(nil))
                        case .welcome: EmptyView()
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lumenColumnContent("Sample workspace editor")
                }
            }
        }
        .background(.lumen(.bgCanvas))
    }
}

private struct SampleWorkspaceListing: View {
    @Environment(\.lumenPalette) private var palette
    @Environment(\.lumenCodeFont) private var codeFont
    private let lines = ["stp x29, x30, [sp, #-16]!", "mov x29, sp", "bl parse_header", "cbz x0, 0x100003f10", "ret"]
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            LumenBranchLanes([LumenBranchLane(fromRow: 3, toRow: 4, isHighlighted: true)], rowHeight: 26, rowCount: lines.count)
            VStack(spacing: 0) {
                ForEach(lines.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Text(String(format: "%08X", 0x1000_3F00 + index * 4)).foregroundStyle(palette[LumenToken.Code.lineNumber])
                        Text(lines[index]).foregroundStyle(palette[LumenToken.Code.keyword]).lumenNeverTruncates(lines[index])
                        Spacer(minLength: 0)
                    }
                    .font((codeFont ?? .standard).font())
                    .frame(height: 26)
                    .lumenListingRow(.init(isSelected: index == 3, isProgramCounter: index == 1,
                                           isPatched: index == 2, isInCurrentBlock: true))
                }
            }
        }
    }
}

private struct SampleWorkspaceGraph: View {
    @Environment(\.lumenPalette) private var palette
    var body: some View {
        VStack(spacing: 12) {
            LumenGraphNode("main", detail: "0x100003f00–3f0c", systemImage: "lumen.entryPoint", hue: .hueGreen, count: 4, state: .selected)
            HStack(spacing: 32) {
                ForEach([LumenGraphEdgeKind.taken, .notTaken], id: \.self) { kind in
                    Rectangle()
                        .fill(palette[kind.token])
                        .frame(width: kind.lineWidth(isSelected: false), height: 40)
                        .overlay { LumenGraphEdgeBadge(kind) }
                }
            }
            LumenGraphNode("Return", detail: "0x100003f10–3f14", systemImage: "arrow.uturn.left", hue: .hueOrange, count: 1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SampleWorkspaceInspector: View {
    let isEmpty: Bool
    @State private var address = "100003f0c"
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                LumenInspectorSummary(kind: "Instruction", title: "0x100003f0c", link: "main", detail: "+12 · __TEXT,__text",
                                      stats: [LumenStat("callers", count: 2), LumenStat("blocks", count: 2), LumenStat("bytes", count: 20)], onOpenLink: {})
                LumenInspectorSection("Address Detail", systemImage: "scope", hue: .hueOrange) {
                    LumenAddressField(text: $address, hint: "Select an instruction or enter an address.") { _ in }
                }
                LumenInspectorSection("Cross-References", systemImage: "lumen.crossReference", hue: .hueTeal) {
                    LumenReferenceRow("_start+12", kind: "call") {}
                    LumenPropertyRow(label: "Section", value: "__text")
                }
            }
            .lumenColumnContent("Sample workspace inspector")
        }
        .lumenInspectorEmptyState(isEmpty, message: "Select an instruction to see its bytes, function, data and cross-references.")
    }
}

private struct SampleWorkspaceDebugger: View {
    @State private var status = "Not attached"
    var body: some View {
        VStack(spacing: 0) {
            LumenPanelBar("Debugger", systemImage: "ladybug.fill", hue: .hueRed, status: status,
                          secondary: [LumenBarAction("Breakpoints", systemImage: "lumen.breakpoint") { status = "No breakpoints" }],
                          primary: LumenBarAction("Attach to Process…") { status = "Demo attached" })
            LumenEmptyState(systemImage: "ladybug", title: "Static debugger demo", message: "No process is launched or attached.")
        }
    }
}
