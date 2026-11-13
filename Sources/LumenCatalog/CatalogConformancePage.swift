import LumenConformance
import LumenUI
import InspectorPack
import SwiftUI

/// Metadata only: browsing this page never reads source files or runs a check.
struct ConformancePage: View {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let owner: String
        init(_ check: any LumenCheck) {
            id = check.id
            title = check.title
            owner = check.owner
        }
        init(id: String, title: String) {
            self.id = id
            self.title = title
            owner = "Lumen"
        }
    }
    struct OwnerGroup: Identifiable {
        let owner: String
        let checks: [Entry]
        var id: String { owner }
    }

    static func groups(for checks: [any LumenCheck]) -> [OwnerGroup] {
        Dictionary(grouping: checks.map(Entry.init), by: \.owner).sorted { $0.key < $1.key }
            .map { OwnerGroup(owner: $0.key, checks: $0.value) }
    }

    static let builtIns: [Entry] = [
        .init(id: "themes", title: "Themes"), .init(id: "layout", title: "Layout"),
        .init(id: "shortcuts", title: "Shortcuts"), .init(id: "coverage", title: "Color coverage"),
        .init(id: "workspaceWindow", title: "Workspace window"), .init(id: "truncation", title: "Truncation"),
        .init(id: "visibleDuplicates", title: "Visible duplicates"), .init(id: "iconScale", title: "Icon scale"),
        .init(id: "backlight", title: "Backlight"), .init(id: "overflow", title: "Overflow"),
        .init(id: "narrowSizing", title: "Narrow sizing"), .init(id: "surfaceSteps", title: "Surface steps"),
        .init(LumenConformance.forbiddenSourcePatterns([], in: [])),
    ]
    static let appGroups = groups(for: [InspectorStyleRatchet(files: [], budget: 120)])

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Conformance", summary: "Lumen and app checks share a context and finding format. Run them in your app’s tests at each pin bump.")
            LumenSectionHeader("Lumen")
            entries(Self.builtIns)
            LumenSectionHeader("App checks")
            ForEach(Self.appGroups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    LumenSectionHeader(group.owner)
                    entries(group.checks)
                }
            }
            Text("The inspector example fails above its allowed source occurrence budget. This page lists checks; it does not run them.")
                .foregroundStyle(.lumen(.fgSecondary))
        }
    }

    private func entries(_ checks: [Entry]) -> some View {
        // Static metadata, so no row is interactive: no hover plate, and a neutral glyph rather
        // than a pass/fail mark (this page never runs a check).
        VStack(spacing: 0) {
            ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                if index > 0 { Divider() }
                LumenListRow(check.title, detail: check.id, systemImage: "checklist")
                    .allowsHitTesting(false)
            }
        }
        .lumenCard(padding: 0)
    }
}
