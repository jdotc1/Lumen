import CoreML
import CoreGraphics
import LumenTestSupport
@testable import LumenUI
import Vision
import XCTest

#if DEBUG
final class LumenAuditOCRTests: XCTestCase {
    func testRequestPerformsWithCPUDevices() throws {
        let request = try LumenAuditOCR.makeRequest()
        XCTAssertEqual(request.recognitionLevel, .accurate)
        XCTAssertFalse(request.usesLanguageCorrection)
        let stages = try request.supportedComputeStageDevices
        XCTAssertFalse(stages.isEmpty)
        for (stage, supported) in stages {
            let selected = try XCTUnwrap(request.computeDevice(for: stage))
            guard case .cpu = selected else {
                return XCTFail("OCR stage \(stage) selected a non-CPU device: \(selected)")
            }
            XCTAssertTrue(supported.contains(selected))
            print("OCR stage \(stage.rawValue): \(selected)")
        }
        let context = try XCTUnwrap(CGContext(data: nil, width: 320, height: 120,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 120))
        let image = try XCTUnwrap(context.makeImage())
        try VNImageRequestHandler(cgImage: image).perform([request])
        XCTAssertEqual(request.results?.count, 0)
    }
}
#endif
