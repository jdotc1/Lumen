import Foundation
import XCTest
@testable import LumenUI

/// A source ratchet for package-owned text. Exceptions are exact source expressions, not files.
final class LumenStringCatalogTests: XCTestCase {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/LumenUI")

    // App data/Text composition, empty native labels, hidden measuring probes, and nonlinguistic
    // symbols/numeric ranges. Each entry must disappear when its source expression disappears.
    private static let allowed: Set<String> = [
        #"LumenCodePane.swift · lines[index].reduce(Text(verbatim: "")) { Text("\($0)\(Text(verbatim: $1.text).foregroundColor(palette[$1.token]))") }"#,
        #"LumenComponents.swift · Text("MMMM").font(metrics.typography.caption).hidden()"#,
        #"LumenComponents.swift · Text("MMMM").font(LumenMetrics.standard.typography.caption).hidden()"#,
        #"LumenComponents.swift · Text("MMMM").font(metrics.typography.body).hidden()"#,
        #"LumenComponents.swift · Text("MMMM").font(LumenMetrics.standard.typography.body).hidden()"#,
        #"LumenDebugger.swift · Text("\(frame.index)")"#,
        #"LumenDebugger.swift · Text("\(Text(prompt + " ").font(monoBold).foregroundColor(palette[.accent]))\(Text(line.text).font(monoBold).foregroundColor(palette[.fgPrimary]))")"#,
        #"LumenDebugger.swift · Text("↩").font(metrics.typography.caption).foregroundStyle(palette[.fgTertiary]).accessibilityHidden(true)"#,
        #"LumenEditors.swift · TextField(prompt, text: $text, prompt: Text(""))"#,
        #"LumenEditors.swift · format: .number, prompt: Text(""))"#,
        #"LumenExtras.swift · Text("\(length)/\(summaryLimit)").font(metrics.typography.caption.monospacedDigit())"#,
        #"LumenForms.swift · Button("\(defaultLabel) (\(title(inherited)))") { selection = nil }"#,
        #"LumenForms.swift · Text("?").font(.system(size: metrics.iconSize.small, weight: .bold, design: .rounded)).foregroundStyle(palette[.fgSecondary])"#,
        #"LumenListing.swift · case .literal(let s): Text("\(result)\(Text(verbatim: s).foregroundColor(palette[literalToken]))")"#,
        #"LumenListing.swift · case .escape(let s): Text("\(result)\(Text(verbatim: s).foregroundColor(palette[LumenToken.Code.keyword]))")"#,
        #"LumenListing.swift · case .format(let s): Text("\(result)\(Text(verbatim: s).foregroundColor(palette[LumenToken.Code.number]))")"#,
        #"LumenPanels.swift · Text("\(Text("\(label(selection)) "))\(Text(Image(systemName: "chevron.down")).font(.system(size: metrics.layout.disclosureGlyph, weight: .bold)))")"#,
        #"LumenPickers.swift · Text("")"#,
        #"LumenPickers.swift · Text("\(Text(name).foregroundColor(palette[.fgPrimary]).fontWeight(.semibold))\(Text(version.map { "  " + $0 } ?? "").foregroundColor(palette[.fgTertiary]))")"#,
        #"LumenSearch.swift · .help("\(file.name):\(match.line)")"#,
        #"LumenSearch.swift · Text("Aa").font(metrics.typography.caption.weight(.semibold))"#,
        #"LumenStates.swift · Text("\(title.map { Text("\($0)  ").fontWeight(.semibold) } ?? Text(""))\(Text(message))")"#,
        #"LumenThemeMetricControls.swift · Text("0.90–1.30 ×").font(metrics.typography.caption).foregroundStyle(palette[.fgTertiary])"#,
        #"LumenThemeMetricControls.swift · Text("1.00–1.25 ×").font(metrics.typography.caption).foregroundStyle(palette[.fgTertiary])"#,
        #"LumenTools.swift · Text("⌘").font(metrics.typography.caption).foregroundStyle(palette[.fgTertiary])"#,
        #"LumenTopBarPlacement.swift · Text("100%").font(metrics.typography.caption.monospacedDigit())"#,
    ]

    private static func matches(_ pattern: String, in text: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: $0.numberOfRanges > 1 ? 1 : 0), in: text).map { String(text[$0]) }
        }
    }

    private func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: Self.sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func testNoUncataloguedViewLiterals() throws {
        var found: Set<String> = []
        for file in try files() {
            for line in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n") {
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("//") { continue }
                if !(try Self.matches(#"\b(?:Text|Button|Label)\(\s*"|\.help\(\s*"|\bprompt:\s*""#, in: text)).isEmpty {
                    found.insert(file.lastPathComponent + " · " + text)
                }
            }
        }
        XCTAssertEqual(found.subtracting(Self.allowed).sorted(), [], "New literal bypasses the package catalog")
        XCTAssertEqual(Self.allowed.subtracting(found).sorted(), [], "Remove stale literal exceptions")
    }

    func testCatalogKeysExactlyMatchLookups() throws {
        let data = try Data(contentsOf: Self.sources.appending(path: "Resources/Localizable.xcstrings"))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "en")
        let entries = try XCTUnwrap(catalog["strings"] as? [String: Any])
        var used: Set<String> = []
        for file in try files() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let literals = try Self.matches(#"String\(localized:\s*("(?:[^"\\]|\\.)*")"#, in: source)
            for literal in literals {
                let value = try JSONDecoder().decode(String.self, from: Data(literal.utf8))
                XCTAssertFalse(value.contains(#"\("#), "Use an explicit format key for interpolated text")
                used.insert(value)
            }
        }
        XCTAssertFalse(used.isEmpty)
        XCTAssertEqual(used.subtracting(entries.keys).sorted(), [], "Missing catalog keys")
        XCTAssertEqual(Set(entries.keys).subtracting(used).sorted(), [], "Unused catalog keys")
        for (key, entry) in entries {
            let item = try XCTUnwrap(entry as? [String: Any])
            XCTAssertFalse((item["comment"] as? String ?? "").isEmpty, key)
        }
    }

    func testCatalogIsCompiledIntoModuleBundle() throws {
        let data = try Data(contentsOf: Self.sources.appending(path: "Resources/Localizable.xcstrings"))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(catalog["strings"] as? [String: Any])
        for key in entries.keys {
            XCTAssertEqual(Bundle.module.localizedString(forKey: key, value: "__missing_catalog_key__", table: nil), key)
        }
    }
}
