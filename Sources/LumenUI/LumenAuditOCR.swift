#if DEBUG
import CoreML
import Vision

/// Audit OCR must not depend on availability of a shared Neural Engine or GPU.
enum LumenAuditOCR {
    enum ConfigurationError: Error {
        case noComputeStages
        case cpuUnavailable(VNComputeStage)
    }

    /// The accurate model can return no observation at all for plainly legible light-on-dark text
    /// that begins with an ellipsis or is cut at a glyph edge (measured: "...ource string" at 1.3x
    /// in dark). Callers fall back to the fast model only when the accurate one found nothing.
    static func makeRequest(fast: Bool = false) throws -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = false
        try selectCPU(for: request)
        return request
    }

    static func makeLineGeometryRequest() throws -> VNDetectTextRectanglesRequest {
        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = true
        try selectCPU(for: request)
        return request
    }

    private static func selectCPU(for request: VNRequest) throws {
        let stages = try request.supportedComputeStageDevices
        guard !stages.isEmpty else { throw ConfigurationError.noComputeStages }
        for (stage, devices) in stages {
            guard let cpu = devices.first(where: {
                if case .cpu = $0 { return true }
                return false
            }) else { throw ConfigurationError.cpuUnavailable(stage) }
            request.setComputeDevice(cpu, for: stage)
        }
    }
}
#endif
