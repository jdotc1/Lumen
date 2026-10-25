import Foundation

public extension LumenConformance {
    /// Finds literal, case-sensitive, non-overlapping occurrences in UTF-8 source files. Comments
    /// and strings count too: this is a source-text guard, not a Swift parser or a renderer.
    /// Duplicate files/patterns are checked once. Unreadable files and empty patterns are findings.
    static func forbiddenSourcePatterns(_ patterns: [String], in files: [URL]) -> some LumenCheck {
        SourcePatternsCheck(patterns: patterns, files: files)
    }
}

struct SourcePatternsCheck: LumenCheck {
    let id = "lumen.forbiddenSourcePatterns"
    let title = "Forbidden source patterns"
    let patterns: [String]
    let files: [URL]

    func run(in context: LumenCheckContext) -> [LumenConformance.Finding] {
        var findings: [LumenConformance.Finding] = []
        let uniquePatterns = Set(patterns).sorted()
        if uniquePatterns.contains("") {
            findings.append(.init(.coverage, title, "an empty source pattern is not valid"))
        }
        for file in Set(files.map(\.standardizedFileURL)).sorted(by: { $0.path < $1.path }) {
            do {
                let source = try String(contentsOf: file, encoding: .utf8)
                for pattern in uniquePatterns where !pattern.isEmpty {
                    let count = source.components(separatedBy: pattern).count - 1
                    if count > 0 {
                        findings.append(.init(.coverage, file.path, "forbidden pattern “\(pattern)” occurs \(count) time(s)"))
                    }
                }
            } catch {
                findings.append(.init(.coverage, file.path, "could not read UTF-8 source: \(error.localizedDescription)"))
            }
        }
        return findings
    }
}
