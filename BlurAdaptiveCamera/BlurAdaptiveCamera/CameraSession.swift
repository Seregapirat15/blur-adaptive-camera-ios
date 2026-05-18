import AVFoundation
import CoreGraphics

protocol CameraSessionDelegate: AnyObject {
    func cameraSession(
        _ session: CameraSession,
        didOutput pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    )
}

final class CameraSession: NSObject {
    weak var delegate: CameraSessionDelegate?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "blur.camera.session")
    private let videoQueue = DispatchQueue(label: "blur.camera.video", qos: .userInitiated)

    func configure(preset: AVCaptureSession.Preset = .hd1280x720) {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = preset

            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)

            guard self.session.canAddOutput(self.videoOutput) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addOutput(self.videoOutput)

            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                connection.isVideoMirrored = false
            }

            self.session.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let visionOrientation = cgImageOrientation(for: connection.videoOrientation)
        delegate?.cameraSession(self, didOutput: pb, orientation: visionOrientation)
    }
}

/// connection.videoOrientation = .portrait уже поворачивает буфер в портрет.
/// Поэтому EXIF-тег должен говорить «ничего не крутить» (.up),
/// иначе CIImage.oriented() повернёт уже портретный буфер ещё раз на 90°.
private func cgImageOrientation(for videoOrientation: AVCaptureVideoOrientation) -> CGImagePropertyOrientation {
    switch videoOrientation {
    case .portrait:           return .up
    case .portraitUpsideDown: return .down
    case .landscapeRight:     return .up
    case .landscapeLeft:      return .up
    @unknown default:         return .up
    }
}
