import AVFoundation
import Combine
import CoreGraphics
import QuartzCore
import UIKit

final class CameraViewModel: NSObject, ObservableObject, CameraSessionDelegate {
    @Published var previewImage: UIImage?
    @Published var heatmapSharpness: [Float] = []
    @Published var gridColumns: Int = 16
    @Published var gridRows: Int = 12

    @Published var normalizedBlurScore: Float = 0
    @Published var globalLaplacianVariance: Float = 0
    @Published var sharpenSharpnessDisplay: CGFloat = 0
    @Published var sharpenRadiusDisplay: CGFloat = 0
    @Published var analysisWidth: Int = 320
    @Published var analysisHeight: Int = 240

    @Published var fps: Double = 0
    @Published var correctionEnabled = true
    @Published var showHeatmap = true
    @Published var showFaces = true

    /// Normalized face rects in Vision space (origin bottom-left).
    @Published var faceBoxesVisionNormalized: [CGRect] = []

    private let camera = CameraSession()
    private let analyzer = BlurAnalyzer()
    private let sharpenPipeline = SharpenPipeline()
    private let faceDetector = FaceOverlayDetector()

    private let processingQueue = DispatchQueue(label: "blur.pipeline", qos: .userInitiated)
    private let frameGate = DispatchSemaphore(value: 1)

    private var smoothedVariance: Float = 120
    private let varianceSmoothing: Float = 0.22

    private var smoothedSharpnessParam: CGFloat = 0.55
    private var smoothedRadiusParam: CGFloat = 1.6
    private let paramSmoothing: CGFloat = 0.18

    private var fpsCounter = 0
    private var lastFpsReferenceTime: CFTimeInterval = 0

    override init() {
        super.init()
        camera.delegate = self
        gridColumns = analyzer.gridColumns
        gridRows = analyzer.gridRows
    }

    func startCamera() {
        camera.configure(preset: .hd1280x720)
        camera.start()
        lastFpsReferenceTime = CACurrentMediaTime()
    }

    func stopCamera() {
        camera.stop()
    }

    func cameraSession(
        _ session: CameraSession,
        didOutput pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) {
        if frameGate.wait(timeout: .now()) != .success {
            return
        }

        let gate = frameGate
        processingQueue.async { [weak self] in
            defer { gate.signal() }
            guard let self else { return }

            let frameStart = CACurrentMediaTime()

            guard let analysis = self.analyzer.analyze(pixelBuffer: pixelBuffer, orientation: orientation) else {
                return
            }

            self.smoothedVariance += self.varianceSmoothing * (analysis.globalLaplacianVariance - self.smoothedVariance)

            let targetSharpness = self.mapVarianceToSharpness(self.smoothedVariance)
            let targetRadius = self.mapVarianceToRadius(self.smoothedVariance)

            self.smoothedSharpnessParam += self.paramSmoothing * (targetSharpness - self.smoothedSharpnessParam)
            self.smoothedRadiusParam += self.paramSmoothing * (targetRadius - self.smoothedRadiusParam)

            let analyzeEnd = CACurrentMediaTime()
            self.adaptAnalysisLoad(processingElapsed: analyzeEnd - frameStart)

            let faces = self.faceDetector.detectIfDue(
                pixelBuffer: pixelBuffer,
                orientation: orientation,
                timestamp: frameStart
            )

            let uiImage = self.sharpenPipeline.renderUIImage(
                pixelBuffer: pixelBuffer,
                orientation: orientation,
                sharpenSharpness: self.smoothedSharpnessParam,
                sharpenRadius: self.smoothedRadiusParam,
                applySharpen: self.correctionEnabled
            )

            self.fpsCounter += 1
            let now = CACurrentMediaTime()
            let dt = now - self.lastFpsReferenceTime
            var nextFps = self.fps
            if dt >= 0.5 {
                nextFps = Double(self.fpsCounter) / dt
                self.fpsCounter = 0
                self.lastFpsReferenceTime = now
            }

            DispatchQueue.main.async {
                self.previewImage = uiImage
                self.heatmapSharpness = analysis.sharpnessHeatmap
                self.normalizedBlurScore = analysis.normalizedBlurScore
                self.globalLaplacianVariance = analysis.globalLaplacianVariance
                self.sharpenSharpnessDisplay = self.smoothedSharpnessParam
                self.sharpenRadiusDisplay = self.smoothedRadiusParam
                self.faceBoxesVisionNormalized = faces
                self.fps = nextFps
            }
        }
    }

    private func mapVarianceToRadius(_ v: Float) -> CGFloat {
        let b = CGFloat(normalizedBlur(from: v))
        return CGFloat(0.6) + b * CGFloat(2.4)
    }

    private func mapVarianceToSharpness(_ v: Float) -> CGFloat {
        let b = CGFloat(normalizedBlur(from: v))
        return CGFloat(0.12) + b * CGFloat(0.95)
    }

    private func normalizedBlur(from variance v: Float) -> Float {
        let low: Float = 55
        let high: Float = 320
        let t = (v - low) / max(high - low, 1)
        return 1 - min(max(t, 0), 1)
    }

    private func adaptAnalysisLoad(processingElapsed: CFTimeInterval) {
        let aw = analyzer.analysisPixelWidth
        let ah = analyzer.analysisPixelHeight
        if processingElapsed > 0.038 {
            let nw = max(200, aw - 16)
            let nh = max(150, ah - 12)
            if nw != aw || nh != ah {
                analyzer.setAnalysisSize(width: nw, height: nh)
                DispatchQueue.main.async {
                    self.analysisWidth = nw
                    self.analysisHeight = nh
                }
            }
        } else if processingElapsed < 0.018 {
            let nw = min(400, aw + 8)
            let nh = min(300, ah + 6)
            if nw != aw || nh != ah {
                analyzer.setAnalysisSize(width: nw, height: nh)
                DispatchQueue.main.async {
                    self.analysisWidth = nw
                    self.analysisHeight = nh
                }
            }
        }
    }
}
