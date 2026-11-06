import Foundation
import XCTest

/// PRINCIPLES §6, narrow sizing, at the source: text that wraps without truncating uses
/// `.lumenWrapsWithoutTruncating()`, never a bare `.fixedSize(horizontal: false, vertical: true)`.
/// The bare form answers a split view's near-zero-width sizing pass with the text a few letters per
/// line, and that height becomes a minimum taller than the window.
///
/// A heuristic scan: for each bare use, the statement it hangs off (back over `.modifier` lines) is
/// searched for the `Text(…)` it applies to. Other uses are keyed by the prefix on the modifier's
/// line, including empty prefixes for multiline containers. Every bare use must be allow-listed
/// with a reason; containers can force arbitrary child text to wrap just as bare Text does.
/// A new bare site fails, and a converted one must leave the list.
final class LumenWrapFixedSizeScanTests: XCTestCase {
    static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/LumenUI", directoryHint: .isDirectory)

    /// "<file> · <Text expression or container prefix>" (with " #n" for identical sites).
    static let allowed: Set<String> = [
        // ViewThatFits measures the first candidate's ideal width; the fallback fixes both axes.
        // Live horizontal scrolling proposes an unspecified width to the lazy row.
        "LumenExtras.swift · container:",
        "LumenExtras.swift · container: #2",
        // A hidden measurement in a GeometryReader background cannot enlarge the parent.
        "LumenOverflow.swift · container:",
        // Both texts in every stat cell have lineLimit(1).
        "LumenPanelBar.swift · container:",
        // A bounded line limit (3): at most three lines tall at any width.
        "LumenExtras.swift · Text(summary)",
        // A popover's fixed 260 pt width.
        "LumenForms.swift · Text(message)",
        // A bounded line limit (2), middle-truncated past it.
        "LumenInspector.swift · Text(title)",
        // A popover's fixed 260 pt width (`lumenPopover(width: 260)`).
        "LumenPopover.swift · Text(message)",
        // A bounded line limit (2).
        "LumenSheet.swift · Text(status.message)",
        // A fixed-width label column (`frame(width: labelWidth ?? propertyLabelWidth)`).
        "LumenSheet.swift · Text(label)",
        // Sites that predate this scan's last refresh (round 9 inventory, 2026-11-06). Converting them to
        // `.lumenWrapsWithoutTruncating()` was tried in bulk and is not behaviour-neutral: it changed the
        // workspace-splits and forms-scale-1.3 goldens and truncated the split sidebar's section titles
        // ("Breakpoints", "Functions"), because the wrapper places its content at the bounds' height. Each
        // converts only with its own layout check. This list is a regression gate for new sites.
        "LumenCommandMenu.swift · container: level(0)",
        "LumenCommandPalette.swift · container:",
        "LumenCommandPalette.swift · container: #2",
        "LumenDataViews.swift · Text(lumenLocalized(String(localized: \"%lld earlier notices\", defaultValue: \"\\(notices.count - visible.count) earlier notices\", bundle: .module, comment: \"DataViews label. Values identify the item or count described.\")))",
        "LumenDataViews.swift · container: Button(primary.title) { primary.perform(); onDismiss() }.buttonStyle(.lumenPrimary)",
        "LumenDataViews.swift · container: Button(secondary.title) { secondary.perform(); onDismiss() }.buttonStyle(.lumenQuiet)",
        "LumenEntryControls.swift · Text(token)",
        "LumenEntryControls.swift · container:",
        "LumenExtras.swift · Text(author)",
        "LumenExtras.swift · Text(tab.title)",
        "LumenExtras.swift · Text(title)",
        "LumenFloatingSizing.swift · container: content",
        "LumenForms.swift · Text(detail)",
        "LumenForms.swift · Text(item.title)",
        "LumenForms.swift · Text(name)",
        "LumenForms.swift · Text(status.title)",
        "LumenForms.swift · Text(text)",
        "LumenForms.swift · container: unitLabel(unit)",
        "LumenInspector.swift · Text(kind)",
        "LumenInspector.swift · Text(stat.label)",
        "LumenInspector.swift · Text(title) #2",
        "LumenInspector.swift · container: .foregroundStyle(palette[.fgPrimary])",
        "LumenMenuBarPanel.swift · container:",
        "LumenMenuBarPanel.swift · container: #2",
        "LumenModeSwitcher.swift · container:",
        "LumenPanelBar.swift · container: #2",
        "LumenPanels.swift · Text(selection ?? lumenLocalized(String(localized: \"All Sources\", bundle: .module, comment: \"Panels display text.\")))",
        "LumenPanels.swift · Text(title)",
        "LumenPanels.swift · container:",
        "LumenPanels.swift · container: #2",
        "LumenPanels.swift · container: #3",
        "LumenPanels.swift · container: heading",
        "LumenPickers.swift · Text(detail)",
        "LumenPickers.swift · container: identity",
        "LumenPickers.swift · container: labelView",
        "LumenSheet.swift · Text(cancelTitle)",
        "LumenSheet.swift · Text(path)",
        "LumenSheet.swift · Text(primary.title)",
        "LumenSheet.swift · Text(process.name)",
        "LumenSheet.swift · Text(subtitle)",
        "LumenSheet.swift · Text(user)",
        "LumenSheet.swift · Text(verbatim: String(process.pid))",
        "LumenShortcutsSheet.swift · container: shortcutColumns",
        "LumenShowcase.swift · container:",
        "LumenToolbar.swift · container:",
        "LumenTopBarPlacement.swift · container: trailing",
        "LumenWelcome.swift · Text(date, format: .relative(presentation: .named))",
        "LumenWelcome.swift · Text(item.detail)",
        "LumenWelcome.swift · Text(item.title)",
        "LumenWelcome.swift · container:",
        "LumenWelcome.swift · container: #2",
        "LumenWorkspaceLayout.swift · Text(pane.title)",
        "LumenWorkspaceLayout.swift · container:",
    ]

    static let bare = try! NSRegularExpression(pattern: #"\.fixedSize\(\s*horizontal:\s*false,\s*vertical:\s*true\s*\)"#)

    /// Every bare use in `source`, keyed as `allowed` is.
    static func bareTextSites(in source: String, file: String) -> [String] {
        let lines = source.components(separatedBy: "\n")
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        var keys: [String] = []
        var seen: [String: Int] = [:]
        for (index, line) in lines.enumerated() {
            if trimmed[index].hasPrefix("//") { continue }
            guard let match = bare.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range, in: line) else { continue }
            // The statement: back over `.modifier` lines to the line the chain hangs off; on the
            // modifier's own line, only what comes before it.
            var start = index
            while start > 0, index - start < 6, trimmed[start].hasPrefix(".") { start -= 1 }
            let chain = Array(lines[start..<index]) + [String(line[..<range.lowerBound])]
            let prefix = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let text = chain.reversed().lazy.compactMap(textExpression(in:)).first
                ?? ("container:" + (prefix.isEmpty ? "" : " " + prefix))
            let count = seen[text, default: 0] + 1
            seen[text] = count
            keys.append("\(file) · \(text)" + (count > 1 ? " #\(count)" : ""))
        }
        return keys
    }

    /// The last `Text(…)` on `line`, with its balanced arguments.
    static func textExpression(in line: String) -> String? {
        guard let start = line.range(of: "Text(", options: .backwards) else { return nil }
        // `LumenHighlightedText(`, `LumenSemanticText(` and the like are components, not Text.
        if start.lowerBound > line.startIndex, line[line.index(before: start.lowerBound)].isLetter { return nil }
        var depth = 0
        for position in line[start.lowerBound...].indices {
            let character = line[position]
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1; if depth == 0 { return String(line[start.lowerBound...position]) } }
        }
        return String(line[start.lowerBound...])
    }

    func testNoTextWrapsWithABareFixedSize() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no sources at \(Self.sources.path)")
        var found: [String] = []
        for file in files {
            found += Self.bareTextSites(in: try String(contentsOf: file, encoding: .utf8), file: file.lastPathComponent)
        }
        let new = Set(found).subtracting(Self.allowed).sorted()
        let stale = Self.allowed.subtracting(found).sorted()
        XCTAssertEqual(new, [], "Unbounded content with a bare .fixedSize(horizontal: false, vertical: true); use .lumenWrapsWithoutTruncating(), "
                       + "or allow-list it with the reason it stays bounded (a line limit, a fixed-width container):\n"
                       + new.joined(separator: "\n"))
        XCTAssertEqual(stale, [], "allow-listed sites no longer occur; remove them:\n" + stale.joined(separator: "\n"))
    }

    func testTheScanFindsBareTextAndContainers() {
        let source = """
            Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(summary).lumenWrapsWithoutTruncating()
            HStack { Text(a); Text(b) }
            rowStack.fixedSize(horizontal: false, vertical: true)
            LumenHighlightedText(name, matching: query).fixedSize(horizontal: false, vertical: true)
            text(for: line)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            // Text(old).fixedSize(horizontal: false, vertical: true)
            """
        XCTAssertEqual(Self.bareTextSites(in: source, file: "X.swift"), [
            "X.swift · Text(title)", "X.swift · Text(detail)",
            "X.swift · container: rowStack", "X.swift · container: LumenHighlightedText(name, matching: query)",
            "X.swift · container:",
        ])
    }
}
