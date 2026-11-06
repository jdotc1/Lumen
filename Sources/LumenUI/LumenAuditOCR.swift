#if DEBUG
import CoreML
import Vision

/// Audit OCR must not depend on availability of a shared Neural Engine or GPU.
enum LumenAuditOCR {
    enum ConfigurationError: Error {
        case noComputeStages
        case cpuUnavailable(VNComputeStage)
    }

    static func makeRequest() throws -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
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
