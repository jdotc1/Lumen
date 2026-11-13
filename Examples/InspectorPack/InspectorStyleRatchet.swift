import Foundation
import LumenConformance

/// An app-owned source-text budget. Supply the app’s current files and accepted budget;
/// this example operates only on the supplied inputs.
/// Literal matches in comments and strings count, just as they do in the source-pattern helper.
public struct InspectorStyleRatchet: LumenCheck {
    public let id = "inspector.styleRatchet"
    public let title = "System foreground style budget"
    public let owner = "Inspector example"
    public let files: [URL]
    public let budget: Int
    public let patterns: [String]

    public init(files: [URL], budget: Int,
                patterns: [String] = [".foregroundStyle(.primary)", ".foregroundStyle(.secondary)"]) {
        self.files = files
        self.budget = budget
        self.patterns = patterns
    }

    public func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        guard budget >= 0, !patterns.contains("") else {
            return [.init(.coverage, owner, "style ratchet needs a nonnegative budget and nonempty patterns")]
        }
        var count = 0
        var findings: [LumenConformance.Finding] = []
        for file in Set(files.map(\.standardizedFileURL)).sorted(by: { $0.path < $1.path }) {
            do {
                let source = try String(contentsOf: file, encoding: .utf8)
                count += Set(patterns).reduce(0) { $0 + source.components(separatedBy: $1).count - 1 }
            } catch {
                findings.append(.init(.coverage, file.path, "could not read UTF-8 source: \(error.localizedDescription)"))
            }
        }
        if count > budget {
            findings.append(.init(.coverage, owner, "system foreground styles occur \(count) time(s); budget is \(budget)"))
        }
        return findings
    }
}
