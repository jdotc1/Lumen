import AppKit
import LumenTestSupport
import XCTest

@MainActor
final class LumenFilterConfinedGoldenTests: XCTestCase {
    func testToneShiftPreservesInkButMovementAndRadiusChangesFail() {
        func glyph(offset: Int = 0, extraWidth: Int = 0, color: [UInt8]) -> LumenFilterConfinedGolden.Pixels {
            let width = 160, height = 160
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for y in 65..<90 {
                for x in 65..<(85 + extraWidth) where x < 70 || y < 70 || (y >= 76 && y < 81) {
                    let p = (y * width + x + offset) * 4
                    for c in 0..<3 { bytes[p + c] = color[c] }
                }
            }
            return (width, height, bytes)
        }
        let original = glyph(color: [30, 30, 30])
        let tinted = LumenFilterConfinedGolden.classify(glyph(color: [60, 100, 120]), original, filterFrames: [], scale: 2)
        XCTAssertGreaterThan(tinted.sameShapeTonePixels, 0)
        XCTAssertEqual(tinted.outsidePixels, 0)
        XCTAssertEqual(tinted.components.count, 1)
        XCTAssertEqual(tinted.components.first?.intersectionOverUnion, 1)
        XCTAssertEqual(tinted.components.first?.centroidShift, 0)
        XCTAssertEqual(tinted.components.first?.qualificationPath, "iou")
        let shifted = LumenFilterConfinedGolden.classify(glyph(offset: 1, color: [30, 30, 30]), original, filterFrames: [], scale: 2)
        XCTAssertGreaterThan(shifted.outsidePixels, 0, "A one-pixel glyph shift must not qualify as tone")
        XCTAssertEqual(shifted.sameShapeTonePixels, 0)
        XCTAssertGreaterThan(shifted.components.first?.centroidShift ?? 0, 0.70,
                             "The dilated diff region must exceed the allowed centroid shift")

        let wider = LumenFilterConfinedGolden.classify(glyph(extraWidth: 1, color: [30, 30, 30]), original, filterFrames: [], scale: 2)
        XCTAssertGreaterThan(wider.outsidePixels, 0, "A one-pixel wider glyph must not qualify as tone")
        XCTAssertEqual(wider.sameShapeTonePixels, 0)
        XCTAssertTrue(wider.components.allSatisfy { !$0.qualifies })
        XCTAssertFalse(wider.components.isEmpty)
        for component in wider.components {
            XCTAssertGreaterThan(component.actualInkPixels, component.expectedInkPixels)
            XCTAssertEqual(component.intersectionInkPixels, component.expectedInkPixels,
                           "The wider glyph is a superset, so containment alone cannot reject it")
            XCTAssertGreaterThan(component.centroidShift ?? 0, 0.25,
                                 "The wider glyph must fail the subset path's centroid limit")
            XCTAssertEqual(component.qualificationPath, "rejected")
        }

        func rounded(radius: Double) -> LumenFilterConfinedGolden.Pixels {
            let width = 160, height = 160
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let dx = max(0, radius - min(Double(x) + 0.5, Double(width - x) - 0.5))
                    let dy = max(0, radius - min(Double(y) + 0.5, Double(height - y) - 0.5))
                    // One-pixel antialiased edge around the rounded rect, premultiplied white.
                    let alpha = UInt8((min(1, max(0, radius + 0.5 - hypot(dx, dy))) * 255).rounded())
                    for c in 0..<4 { bytes[(y * width + x) * 4 + c] = alpha }
                }
            }
            return (width, height, bytes)
        }
        let radiusChange = LumenFilterConfinedGolden.classify(rounded(radius: 35), rounded(radius: 32), filterFrames: [], scale: 2)
        XCTAssertGreaterThan(radiusChange.cornerEdgePixels, 0, "Antialiased edge pixels qualify separately")
        XCTAssertGreaterThan(radiusChange.outsidePixels, 0, "The opaque/clear interior of a 3-pixel radius change must fail")
        XCTAssertLessThan(radiusChange.cornerEdgePixels, radiusChange.differingPixels)
        XCTAssertEqual(radiusChange.sameShapeTonePixels, 0)
    }

    func testAntialiasEdgeBoundsAndShiftRejection() {
        func fixture(edge: Bool = true, shift: Int = 0) -> LumenFilterConfinedGolden.Pixels {
            var bytes = [UInt8](repeating: 128, count: 160 * 160 * 4)
            for p in 0..<(160 * 160) { bytes[p * 4 + 3] = 255 }
            // A low-contrast diagonal edge, below the class-c ink threshold relative to mid-gray.
            if edge {
                for y in 65..<85 {
                    for c in 0..<3 { bytes[(y * 160 + y + shift) * 4 + c] = 105 }
                    for c in 0..<3 { bytes[(y * 160 + y + 1 + shift) * 4 + c] = 151 }
                }
            }
            return (160, 160, bytes)
        }
        let expected = fixture()
        func changed(count: Int = 4, delta: UInt8 = 24, alpha: Bool = false, xOffset: Int = -1) -> LumenFilterConfinedGolden.Pixels {
            var image = expected
            for y in 70..<(70 + count) {
                let p = (y * 160 + y + xOffset) * 4
                for c in 0..<3 { image.bytes[p + c] -= delta }
                if alpha { image.bytes[p + 3] -= 1 }
            }
            return image
        }
        func classify(_ actual: LumenFilterConfinedGolden.Pixels, _ baseline: LumenFilterConfinedGolden.Pixels? = nil) -> LumenFilterConfinedGolden.Classification {
            LumenFilterConfinedGolden.classify(actual, baseline ?? expected, filterFrames: [], scale: 2)
        }
        let accepted = classify(changed())
        XCTAssertEqual(accepted.antialiasEdgePixels, 4)
        XCTAssertEqual(accepted.sameShapeTonePixels, 0)
        XCTAssertEqual(accepted.outsidePixels, 0)
        XCTAssertEqual(accepted.components.first?.qualificationPath, "antialias-edge")
        let symbolEdge = classify(changed(count: 8, delta: 33))
        XCTAssertEqual(symbolEdge.antialiasEdgePixels, 8)
        XCTAssertEqual(symbolEdge.outsidePixels, 0)
        let shifted = classify(fixture(shift: 1))
        XCTAssertEqual(shifted.components.count, 1)
        XCTAssertGreaterThan(shifted.components.first?.differingPixels ?? 0, 8,
                             "A real glyph shift forms a long contiguous component beyond class d's cap")
        XCTAssertEqual(shifted.conversionNoisePixels, 0)
        for rejected in [classify(changed(count: 9)), classify(changed(delta: 41)),
                         classify(changed(alpha: true)), classify(changed(xOffset: -5)),
                         shifted] {
            XCTAssertEqual(rejected.antialiasEdgePixels, 0)
            XCTAssertEqual(rejected.sameShapeTonePixels, 0)
            XCTAssertGreaterThan(rejected.outsidePixels, 0)
        }
        // An edge present in only one image cannot qualify, in either image order.
        var flat = fixture(edge: false)
        var edgeOnly = flat
        for c in 0..<3 { flat.bytes[(75 * 160 + 75) * 4 + c] = 115 }
        edgeOnly = flat
        for c in 0..<3 { edgeOnly.bytes[(75 * 160 + 75) * 4 + c] = 95 }
        XCTAssertEqual(classify(edgeOnly, flat).antialiasEdgePixels, 0)
        XCTAssertEqual(classify(flat, edgeOnly).antialiasEdgePixels, 0)
    }

    func testConversionNoiseBoundsAndShiftRejection() {
        typealias Pixels = LumenFilterConfinedGolden.Pixels
        var flat: Pixels = (160, 160, [UInt8](repeating: 128, count: 160 * 160 * 4))
        for p in 0..<(160 * 160) { flat.bytes[p * 4 + 3] = 255 }
        func classify(count: Int, delta: UInt8 = 16, rawDelta: UInt8 = 4, alpha: UInt8 = 0) -> LumenFilterConfinedGolden.Classification {
            var actual = flat, raw = flat
            for x in 70..<(70 + count) {
                let p = (75 * 160 + x) * 4
                actual.bytes[p] += delta
                actual.bytes[p + 3] -= alpha
                raw.bytes[p] += rawDelta
            }
            return LumenFilterConfinedGolden.classify(actual, flat, rawActual: raw, rawExpected: flat,
                                                       filterFrames: [], scale: 2)
        }
        for count in [1, 2] {
            let result = classify(count: count)
            XCTAssertEqual(result.conversionNoisePixels, count)
            XCTAssertEqual(result.outsidePixels, 0)
            XCTAssertEqual(result.components.first?.maxRawChannelDelta, 4)
            XCTAssertEqual(result.components.first?.qualificationPath, "conversion-noise")
        }
        for result in [classify(count: 3), classify(count: 2, delta: 17),
                       classify(count: 2, rawDelta: 5), classify(count: 2, alpha: 1)] {
            XCTAssertEqual(result.conversionNoisePixels, 0)
            XCTAssertGreaterThan(result.outsidePixels, 0)
        }
        let broadRounding = classify(count: 20, rawDelta: 1)
        XCTAssertEqual(broadRounding.conversionNoisePixels, 20)
        XCTAssertEqual(broadRounding.outsidePixels, 0)
        let broadChange = classify(count: 20, rawDelta: 3)
        XCTAssertEqual(broadChange.conversionNoisePixels, 0)
        XCTAssertEqual(broadChange.outsidePixels, 20)
        var original = flat, shifted = flat
        for y in 65..<85 {
            for c in 0..<3 {
                original.bytes[(y * 160 + y) * 4 + c] = 105
                original.bytes[(y * 160 + y + 1) * 4 + c] = 151
                shifted.bytes[(y * 160 + y + 1) * 4 + c] = 105
                shifted.bytes[(y * 160 + y + 2) * 4 + c] = 151
            }
        }
        let rejected = LumenFilterConfinedGolden.classify(shifted, original, rawActual: shifted,
            rawExpected: original, filterFrames: [], scale: 2)
        XCTAssertEqual(rejected.sameShapeTonePixels, 0)
        XCTAssertEqual(rejected.antialiasEdgePixels, 0)
        XCTAssertEqual(rejected.conversionNoisePixels, 0)
        XCTAssertGreaterThan(rejected.outsidePixels, 0)
    }

    func testRetainedTagsCropRawLuminanceAntialiasEdge() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/ClassDAntialias")
        let actual = try LumenFilterConfinedGolden.pixels(Data(contentsOf: directory.appending(path: "actual.png")), rawLuminance: true)
        let expected = try LumenFilterConfinedGolden.pixels(Data(contentsOf: directory.appending(path: "expected.png")), rawLuminance: true)
        // Retained backing-pixel coordinates, translated by the crop origin (1808,154).
        // The first two have raw deltas 5 and 4; this exercises the supplied four-point edge predicate.
        let points = Set([(2, 4), (8, 4), (4, 5), (6, 5)].map { $0.1 * actual.width + $0.0 })
        let result = LumenFilterConfinedGolden.antialiasMetrics(actual, expected, rawActual: actual,
            rawExpected: expected, changed: points, component: points)
        print("RETAINED CROP: pixels=\(points.count) maxDelta=\(result.maxDelta) alphaDelta=\(result.alphaDelta) rawEdgeActual=\(result.actualEdge) rawEdgeExpected=\(result.expectedEdge) classD=\(result.qualifies)")
        XCTAssertTrue(result.qualifies)
        XCTAssertEqual(result.maxDelta, 16)
        XCTAssertEqual(result.alphaDelta, 0)
        XCTAssertEqual(result.actualEdge, 0.442, accuracy: 0.001)
        XCTAssertEqual(result.expectedEdge, 0.445, accuracy: 0.001)
    }

}
