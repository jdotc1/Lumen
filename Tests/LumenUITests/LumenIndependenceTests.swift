import Foundation
import XCTest

final class LumenIndependenceTests: XCTestCase {
    func testTrackedTextUsesIndependentNames() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = root
        process.arguments = ["ls-files", "-z"]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "Could not enumerate tracked files")
        guard process.terminationStatus == 0 else { return }

        let encodedPattern = "bWFjc2NvcGV8XGJhaXJzXGJ8ZGljb218XGJub3ZhXGI="
        let decoded = try XCTUnwrap(Data(base64Encoded: encodedPattern))
        let pattern = try XCTUnwrap(String(data: decoded, encoding: .utf8))
        let expression = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let excluded: Set<String> = ["Tests/LumenUITests/LumenIndependenceTests.swift"]
        var matches: [String] = []
        for path in String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init) {
            guard !excluded.contains(path), !path.hasPrefix("receipts/") else { continue }
            let file = root.appendingPathComponent(path)
            // A tracked deletion can remain in the index until the calling thread stages it.
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let contents = try Data(contentsOf: file)
            guard !contents.contains(0), let text = String(data: contents, encoding: .utf8) else { continue }
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                if expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    matches.append("\(path):\(index + 1): \(line)")
                }
            }
        }
        XCTAssertTrue(matches.isEmpty, "Client-specific names in tracked text:\n" + matches.joined(separator: "\n"))
    }
}
