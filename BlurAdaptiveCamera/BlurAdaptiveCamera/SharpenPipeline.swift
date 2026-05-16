import CoreGraphics
import CoreImage
import CoreVideo
import UIKit

final class SharpenPipeline {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func renderCGImage(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        sharpenSharpness: CGFloat,
        sharpenRadius: CGFloat,
        applySharpen: Bool
    ) -> CGImage? {
        let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(forExifOrientation: Int32(orientation.rawValue))
        let input = oriented

        let filtered: CIImage?
        if applySharpen {
            filtered = CIFilter(
                name: "CISharpenLuminance",
                parameters: [
                    kCIInputImageKey: input,
                    kCIInputSharpnessKey: sharpenSharpness,
                    kCIInputRadiusKey: sharpenRadius,
                ]
            )?.outputImage
        } else {
            filtered = input
        }

        guard let output = filtered else { return nil }
        let extent = output.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }

        return ciContext.createCGImage(output, from: extent)
    }

    func renderUIImage(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        sharpenSharpness: CGFloat,
        sharpenRadius: CGFloat,
        applySharpen: Bool,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage? {
        guard let cg = renderCGImage(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            sharpenSharpness: sharpenSharpness,
            sharpenRadius: sharpenRadius,
            applySharpen: applySharpen
        ) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }
}
