import LumenConformance
import LumenUI
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Conformance", summary: "Design checks share a context and finding format. Run them in a test target to evaluate themes and layouts.")
            LumenSectionHeader("Lumen")
            entries(Self.builtIns)
            Text("This page lists the available checks without running them.")
                .foregroundStyle(.lumen(.fgSecondary))
        }
    }

    private func entries(_ checks: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(checks) { check in
                Text(check.title).lumenNeverTruncates(check.title)
            }
        }
    }
}
