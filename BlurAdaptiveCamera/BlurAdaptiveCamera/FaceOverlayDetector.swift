import CoreGraphics
import CoreVideo
import Vision

final class FaceOverlayDetector {
    private let request = VNDetectFaceRectanglesRequest()
    private var lastBoxes: [CGRect] = []
    private var lastExecTime: CFTimeInterval = 0
    /// Minimum interval between Vision runs (seconds).
    var minInterval: CFTimeInterval = 0.125

    func detectIfDue(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        timestamp: CFTimeInterval
    ) -> [CGRect] {
        guard timestamp - lastExecTime >= minInterval else {
            return lastBoxes
        }
        lastExecTime = timestamp

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results as? [VNFaceObservation] ?? []
            lastBoxes = observations.map(\.boundingBox)
        } catch {
            return lastBoxes
        }

        return lastBoxes
    }

    func reset() {
        lastBoxes = []
        lastExecTime = 0
    }
}
