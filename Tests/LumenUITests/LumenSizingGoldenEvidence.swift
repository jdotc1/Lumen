import Foundation
import SwiftUI
import LumenTokens
import LumenTestSupport
@testable import LumenUI

/// Retains the same render used for comparison, so reviewing a sizing difference needs no rerun.
@MainActor
enum LumenSizingGoldenEvidence {
    static func verify<Content: View>(_ view: Content, named name: String, size: CGSize,
                                     variant: LumenSnapshot.Variant, registry: LumenRegistry,
                                     metrics: LumenMetrics = .standard, goldenDirectory: URL,
                                     renderer: LumenSnapshot.Renderer = .image) -> LumenSnapshot.Outcome {
        guard let path = ProcessInfo.processInfo.environment["LUMEN_SIZING_EVIDENCE"] else {
            return LumenSnapshot.verify(view, named: name, size: size, variant: variant,
                                        registry: registry, metrics: metrics,
                                        goldenDirectory: goldenDirectory, renderer: renderer)
        }
        let filename = "\(name)@\(variant.label)"
        let expectedURL = goldenDirectory.appending(path: filename + ".png")

        guard let actual = LumenSnapshot.png(of: view, size: size, variant: variant,
                                             registry: registry, metrics: metrics, renderer: renderer) else {
            return .renderFailed
        }
        guard let expected = try? Data(contentsOf: expectedURL) else { return .missingGolden(expectedURL) }
        let difference = LumenSnapshot.compare(actual, expected)
        let matches = !difference.sizeMismatch && difference.differingPixelFraction <= 0.005
            && difference.densestPatchFraction <= LumenSnapshot.patchTolerance
        do {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !matches {
                try expected.write(to: directory.appending(path: filename + "-expected.png"))
                try actual.write(to: directory.appending(path: filename + "-actual.png"))
            }
            let measurement = "\(filename)\t\(matches ? "matched" : "differed")\t\(difference)\n"
            try Data(measurement.utf8).write(to: directory.appending(path: filename + ".txt"))
        } catch {
            return .renderFailed
        }
        return matches ? .matched(difference) : .mismatched(difference)
    }
}
