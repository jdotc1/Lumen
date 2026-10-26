import AppKit
import ImageIO
import LumenTestSupport
import LumenUI
import XCTest

/// An opt-in, bounded migration of whole-window goldens. Never changes comparator thresholds.
@MainActor
enum LumenFilterConfinedGolden {
    struct Component: Encodable {
        let bounds: CGRect
        let differingPixels: Int
        let alphaDeltaPixels: Int
        let maxChannelDelta: Int
        let maxRawChannelDelta: Int
        let maxAlphaDelta: Int
        let actualEdgeValue: Double
        let expectedEdgeValue: Double
        let actualBackground: Double
        let expectedBackground: Double
        let actualInkPixels: Int
        let expectedInkPixels: Int
        let intersectionInkPixels: Int
        let smallerToLargerInkRatio: Double
        let intersectionOverUnion: Double
        let centroidShift: Double?
        let qualificationPath: String
        let qualifies: Bool
    }
    struct Classification: Encodable {
        var differingPixels = 0
        var filterUnionPixels = 0
        var cornerEdgePixels = 0
        var sameShapeTonePixels = 0
        var antialiasEdgePixels = 0
        var conversionNoisePixels = 0
        var outsidePixels = 0
        // Top-left, top-right, bottom-left, bottom-right, exclusive of class (a).
        var cornerCounts = [0, 0, 0, 0]
        var components: [Component] = []
        var diffBounds: CGRect?
        var outsideBounds: CGRect?
    }
    private struct Measurement: Encodable {
        let name: String
        let difference: String
        let filteredLayers: [LumenHeadlessHost.FilteredLayer]
        let backingScale: CGFloat
        let classification: Classification
        let action: String
        let source: String
    }
    private enum Stop: Error { case mismatch(String), missingCapture, unreadablePNG }
    typealias Pixels = (width: Int, height: Int, bytes: [UInt8])
    static let diagnosticDirectory = ProcessInfo.processInfo.environment["LUMEN_CAPTURE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: ".build/golden-diagnostics")

    static func verify(_ actual: Data, at url: URL) throws {
        guard let capture = LumenHeadlessHost.lastCapture, capture.png == actual else {
            throw Stop.missingCapture
        }
        try verify(actual, expected: Data(contentsOf: url), at: url,
                   filteredLayers: capture.filteredLayers, backingScale: capture.backingScale, source: "live-bitmap")
    }

    /// Retained inputs enter the identical classifier without creating a window or capture.
    static func verify(_ actual: Data, expected: Data, at url: URL,
                       filteredLayers: [LumenHeadlessHost.FilteredLayer], backingScale: CGFloat,
                       source: String) throws {
        let difference = LumenSnapshot.compare(actual, expected)
        let a = try pixels(actual), b = try pixels(expected)
        let rawA = try pixels(actual, rawLuminance: true), rawB = try pixels(expected, rawLuminance: true)
        let classification = classify(a, b, rawActual: rawA, rawExpected: rawB, filterFrames: filteredLayers.map(\.pixelFrame), scale: backingScale)
        let matches = !difference.sizeMismatch && difference.differingPixelFraction <= 0.005
            && difference.densestPatchFraction <= LumenSnapshot.patchTolerance
        let authorized = ProcessInfo.processInfo.environment["LUMEN_FILTER_CONFINED_REBASELINE"] == "1"
        let confined = !difference.sizeMismatch && classification.differingPixels > 0 && classification.outsidePixels == 0
        let action = matches ? "matched" : (authorized && confined ? "rebaselined-appearance-confined" : "STOP")
        let measurement = Measurement(name: url.lastPathComponent, difference: difference.description,
                              filteredLayers: filteredLayers, backingScale: backingScale,
                              classification: classification, action: action, source: source)
        let directory = diagnosticDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = url.deletingPathExtension().lastPathComponent
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(measurement).write(to: directory.appending(path: "\(stem).json"))
        print("CONFINED GOLDEN: \(stem): \(difference); filter=\(classification.filterUnionPixels); corner=\(classification.cornerEdgePixels); tone=\(classification.sameShapeTonePixels); antialias=\(classification.antialiasEdgePixels); conversion=\(classification.conversionNoisePixels); outside=\(classification.outsidePixels); action=\(action)")
        guard !matches else { return }
        try actual.write(to: directory.appending(path: "\(stem)-actual.png"))
        try expected.write(to: directory.appending(path: "\(stem)-expected.png"))
        if action == "rebaselined-appearance-confined" {
            // Reuse the one captured bitmap; no second render or repeat comparison.
            try actual.write(to: url)
            return
        }
        let crops = classification.components.filter { !$0.qualifies }.map(\.bounds)
        for (index, bounds) in (crops.isEmpty ? [classification.outsideBounds ?? classification.diffBounds ?? .zero] : crops).enumerated() {
            let crop = bounds.insetBy(dx: -8, dy: -8)
                .intersection(CGRect(x: 0, y: 0, width: a.width, height: a.height)).integral
            if !crop.isNull && !crop.isEmpty {
                try writeCrop(actual, rect: crop, to: directory.appending(path: "\(stem)-outside-\(index)-actual.png"))
                try writeCrop(expected, rect: crop, to: directory.appending(path: "\(stem)-outside-\(index)-expected.png"))
            }
        }
        throw Stop.mismatch("\(stem): \(classification.outsidePixels) pixels outside appearance classes; \(difference)")
    }

    /// Classes are disjoint in priority order (a), (b), (c), (d), (e). Counts cover only deltas > 12.
    /// Class (c) uses Rec.709 on comparator sRGB bytes; class (d) uses source-space image bytes.
    /// Both luminance calculations are normalized to 0...1; neither edge calculation uses an ink mask.
    /// Components use a square 2 px dilation and 8-connectivity; their border ring is 4 px wide.
    static func classify(_ a: Pixels, _ b: Pixels, rawActual: Pixels? = nil, rawExpected: Pixels? = nil, filterFrames: [CGRect], scale: CGFloat) -> Classification {
        var result = Classification()
        guard a.width == b.width && a.height == b.height else { return result }
        let width = a.width, height = a.height
        let cornerSize = 24 * scale
        let corners = [CGRect(x: 0, y: 0, width: cornerSize, height: cornerSize),
                       CGRect(x: CGFloat(width) - cornerSize, y: 0, width: cornerSize, height: cornerSize),
                       CGRect(x: 0, y: CGFloat(height) - cornerSize, width: cornerSize, height: cornerSize),
                       CGRect(x: CGFloat(width) - cornerSize, y: CGFloat(height) - cornerSize, width: cornerSize, height: cornerSize)]
        var residual = Set<Int>()
        var diffBounds = CGRect.null
        func delta(_ p: Int, _ channel: Int) -> Int { abs(Int(a.bytes[p * 4 + channel]) - Int(b.bytes[p * 4 + channel])) }
        for p in 0..<(width * height) where (0..<4).contains(where: { delta(p, $0) > 12 }) {
            result.differingPixels += 1
            let rect = CGRect(x: p % width, y: p / width, width: 1, height: 1)
            diffBounds = diffBounds.union(rect)
            if filterFrames.contains(where: { $0.contains(rect) }) {
                result.filterUnionPixels += 1
            } else if let corner = corners.firstIndex(where: { $0.contains(rect) }),
                      (a.bytes[p * 4 + 3] > 0 && a.bytes[p * 4 + 3] < 255)
                        || (b.bytes[p * 4 + 3] > 0 && b.bytes[p * 4 + 3] < 255)
                        || (0..<3).allSatisfy({ delta(p, $0) == 0 }) {
                result.cornerEdgePixels += 1
                result.cornerCounts[corner] += 1
            } else { residual.insert(p) }
        }
        func dilate(_ points: Set<Int>, by radius: Int) -> Set<Int> {
            var expanded = Set<Int>()
            for p in points {
                for y in max(0, p / width - radius)...min(height - 1, p / width + radius) {
                    for x in max(0, p % width - radius)...min(width - 1, p % width + radius) {
                        expanded.insert(y * width + x)
                    }
                }
            }
            return expanded
        }
        func luminance(_ image: Pixels, _ p: Int) -> Double {
            (0.2126 * Double(image.bytes[p * 4]) + 0.7152 * Double(image.bytes[p * 4 + 1])
             + 0.0722 * Double(image.bytes[p * 4 + 2])) / 255
        }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted(), n = values.count
            guard n > 0 else { return 0 }
            return n.isMultiple(of: 2) ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2 : sorted[n / 2]
        }
        func centroid(_ points: Set<Int>) -> CGPoint? {
            guard !points.isEmpty else { return nil }
            let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + CGFloat($1 % width), y: $0.y + CGFloat($1 / width)) }
            return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
        }
        var unvisited = dilate(residual, by: 2)
        var outsideBounds = CGRect.null
        while let seed = unvisited.min() {
            var component: Set<Int> = [seed], queue = [seed], cursor = 0
            unvisited.remove(seed)
            while cursor < queue.count {
                let p = queue[cursor]
                cursor += 1
                for y in max(0, p / width - 1)...min(height - 1, p / width + 1) {
                    for x in max(0, p % width - 1)...min(width - 1, p % width + 1) {
                        let q = y * width + x
                        if unvisited.remove(q) != nil { component.insert(q); queue.append(q) }
                    }
                }
            }
            let ring = dilate(component, by: 4).subtracting(component)
            let backgroundA = median(ring.map { luminance(a, $0) })
            let backgroundB = median(ring.map { luminance(b, $0) })
            let inkA = Set(component.filter { abs(luminance(a, $0) - backgroundA) > 0.1 })
            let inkB = Set(component.filter { abs(luminance(b, $0) - backgroundB) > 0.1 })
            let union = inkA.union(inkB).count
            let intersection = inkA.intersection(inkB).count
            let smaller = min(inkA.count, inkB.count), larger = max(inkA.count, inkB.count)
            let ratio = larger == 0 ? 0 : Double(smaller) / Double(larger)
            let iou = union == 0 ? 0 : Double(intersection) / Double(union)
            let shift: Double?
            if let ca = centroid(inkA), let cb = centroid(inkB) { shift = hypot(ca.x - cb.x, ca.y - cb.y) }
            else { shift = nil }
            let alphaCount = component.filter { delta($0, 3) > 12 }.count
            let iouPath = iou >= 0.90 && (shift.map { $0 <= 0.70 } ?? false)
            let subsetPath = intersection == smaller && ratio >= 0.85 && (shift.map { $0 <= 0.25 } ?? false)
            let eligible = !ring.isEmpty && alphaCount == 0
            let changed = component.intersection(residual)
            let edge = antialiasMetrics(a, b, rawActual: rawActual ?? a, rawExpected: rawExpected ?? b,
                                        changed: changed, component: component)
            let antialias = edge.qualifies
            let rawA = rawActual ?? a, rawB = rawExpected ?? b
            let rawDelta = component.flatMap { p in
                (0..<4).map { abs(Int(rawA.bytes[p * 4 + $0]) - Int(rawB.bytes[p * 4 + $0])) }
            }.max() ?? 0
            let conversion = !changed.isEmpty && edge.maxDelta <= 16 && edge.alphaDelta == 0
                && (rawDelta <= 2 || (changed.count <= 2 && rawDelta <= 4))
            let path = eligible && iouPath ? "iou" : (eligible && subsetPath ? "subset" : (antialias ? "antialias-edge" : (conversion ? "conversion-noise" : "rejected")))
            let qualifies = path != "rejected"
            let bounds = component.reduce(CGRect.null) { $0.union(CGRect(x: $1 % width, y: $1 / width, width: 1, height: 1)) }
            result.components.append(Component(bounds: bounds, differingPixels: changed.count, alphaDeltaPixels: alphaCount,
                                               maxChannelDelta: edge.maxDelta, maxRawChannelDelta: rawDelta, maxAlphaDelta: edge.alphaDelta,
                                               actualEdgeValue: edge.actualEdge, expectedEdgeValue: edge.expectedEdge,
                                               actualBackground: backgroundA, expectedBackground: backgroundB,
                                               actualInkPixels: inkA.count, expectedInkPixels: inkB.count,
                                               intersectionInkPixels: intersection, smallerToLargerInkRatio: ratio,
                                               intersectionOverUnion: iou, centroidShift: shift,
                                               qualificationPath: path, qualifies: qualifies))
            print("CONFINED COMPONENT: bounds=\(bounds) pixels=\(changed.count) maxDelta=\(edge.maxDelta) rawDelta=\(rawDelta) alphaDelta=\(edge.alphaDelta) rawEdgeActual=\(edge.actualEdge) rawEdgeExpected=\(edge.expectedEdge) classD=\(edge.qualifies) classE=\(conversion) verdict=\(path)")
            if path == "antialias-edge" { result.antialiasEdgePixels += changed.count }
            else if path == "conversion-noise" { result.conversionNoisePixels += changed.count }
            else if qualifies { result.sameShapeTonePixels += changed.count }
            else {
                result.outsidePixels += changed.count
                for p in changed { outsideBounds = outsideBounds.union(CGRect(x: p % width, y: p / width, width: 1, height: 1)) }
            }
        }
        result.diffBounds = diffBounds.isNull ? nil : diffBounds
        result.outsideBounds = outsideBounds.isNull ? nil : outsideBounds
        return result
    }

    struct AntialiasMetrics {
        let maxDelta: Int
        let alphaDelta: Int
        // Minimum, over differing pixels, of the maximum neighbouring 3 x 3 range.
        let actualEdge: Double
        let expectedEdge: Double
        let qualifies: Bool
    }

    static func antialiasMetrics(_ actual: Pixels, _ expected: Pixels,
                                 rawActual: Pixels, rawExpected: Pixels,
                                 changed: Set<Int>, component: Set<Int>) -> AntialiasMetrics {
        func edgeValue(_ image: Pixels, _ pixel: Int) -> Double {
            let x = pixel % image.width, y = pixel / image.width
            var maximum = 0.0
            for ey in max(0, y - 1)...min(image.height - 1, y + 1) {
                for ex in max(0, x - 1)...min(image.width - 1, x + 1) {
                    var low = Double.infinity, high = -Double.infinity
                    for py in max(0, ey - 1)...min(image.height - 1, ey + 1) {
                        for px in max(0, ex - 1)...min(image.width - 1, ex + 1) {
                            let p = (py * image.width + px) * 4
                            let luma = (0.2126 * Double(image.bytes[p]) + 0.7152 * Double(image.bytes[p + 1])
                                        + 0.0722 * Double(image.bytes[p + 2])) / 255
                            low = min(low, luma); high = max(high, luma)
                        }
                    }
                    maximum = max(maximum, high - low)
                }
            }
            return maximum
        }
        let maxDelta = component.flatMap { p in
            (0..<3).map { abs(Int(actual.bytes[p * 4 + $0]) - Int(expected.bytes[p * 4 + $0])) }
        }.max() ?? 0
        let alphaDelta = component.map { abs(Int(actual.bytes[$0 * 4 + 3]) - Int(expected.bytes[$0 * 4 + 3])) }.max() ?? 0
        let actualEdge = changed.map { edgeValue(rawActual, $0) }.min() ?? 0
        let expectedEdge = changed.map { edgeValue(rawExpected, $0) }.min() ?? 0
        return AntialiasMetrics(maxDelta: maxDelta, alphaDelta: alphaDelta,
                                actualEdge: actualEdge, expectedEdge: expectedEdge,
                                qualifies: !changed.isEmpty && changed.count <= 8 && maxDelta <= 40
                                    && alphaDelta == 0 && actualEdge > 0.1 && expectedEdge > 0.1)
    }

    /// Default: the same premultiplied sRGB conversion as LumenSnapshot.compare.
    /// Raw luminance: preserve the PNG color space instead of converting its channels to sRGB.
    static func pixels(_ data: Data, rawLuminance: Bool = false) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = rawLuminance ? image.colorSpace : CGColorSpace(name: CGColorSpace.sRGB) else { throw Stop.unreadablePNG }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw Stop.unreadablePNG }
        return (image.width, image.height, bytes)
    }

    static func writeCrop(_ data: Data, rect: CGRect, to url: URL) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)?.cropping(to: rect),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw Stop.unreadablePNG
        }
        try png.write(to: url)
    }
}
