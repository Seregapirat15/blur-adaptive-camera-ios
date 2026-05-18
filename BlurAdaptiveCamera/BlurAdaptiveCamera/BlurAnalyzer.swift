import CoreGraphics
import CoreImage
import CoreVideo

struct BlurAnalysisResult {
    /// Per cell: higher = sharper (0...1 after normalization within frame).
    let sharpnessHeatmap: [Float]
    let gridColumns: Int
    let gridRows: Int
    /// Aggregate Laplacian-variance proxy for the frame (scale depends on analysis resolution).
    let globalLaplacianVariance: Float
    /// 0 = sharp scene, 1 = blurry scene (HUD).
    let normalizedBlurScore: Float
}

final class BlurAnalyzer {
    let gridColumns: Int
    let gridRows: Int

    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var analysisWidth: Int
    private var analysisHeight: Int

    /// Expected variance range at default analysis size (tunable).
    private let refVarianceBlurry: Float = 55
    private let refVarianceSharp: Float = 320

    init(gridColumns: Int = 16, gridRows: Int = 12, analysisWidth: Int = 320, analysisHeight: Int = 240) {
        self.gridColumns = gridColumns
        self.gridRows = gridRows
        self.analysisWidth = analysisWidth
        self.analysisHeight = analysisHeight
    }

    func setAnalysisSize(width: Int, height: Int) {
        analysisWidth = max(160, min(width, 480))
        analysisHeight = max(120, min(height, 360))
    }

    var analysisPixelWidth: Int { analysisWidth }
    var analysisPixelHeight: Int { analysisHeight }

    func analyze(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> BlurAnalysisResult? {
        let w = analysisWidth
        let h = analysisHeight

        let base = CIImage(cvPixelBuffer: pixelBuffer).oriented(forExifOrientation: Int32(orientation.rawValue))
        let bounds = base.extent.integral
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        let scaleX = CGFloat(w) / bounds.width
        let scaleY = CGFloat(h) / bounds.height
        let scaled = base.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard
            let gray = CIFilter(
                name: "CIColorControls",
                parameters: [
                    kCIInputImageKey: scaled,
                    kCIInputSaturationKey: 0.0,
                ]
            )?.outputImage
        else { return nil }

        var bitmap = [UInt8](repeating: 0, count: w * h)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ciContext.render(
            gray,
            toBitmap: &bitmap,
            rowBytes: w,
            bounds: rect,
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        )

        guard w > 2, h > 2 else { return nil }

        let innerW = w - 2
        let innerH = h - 2
        let cw = max(1, innerW / gridColumns)
        let ch = max(1, innerH / gridRows)

        var cellVariances = [Float](repeating: 0, count: gridColumns * gridRows)

        for gy in 0..<gridRows {
            for gx in 0..<gridColumns {
                let x0 = 1 + gx * cw
                let y0 = 1 + gy * ch
                let x1 = min(1 + (gx + 1) * cw, w - 1)
                let y1 = min(1 + (gy + 1) * ch, h - 1)
                if x1 <= x0 || y1 <= y0 { continue }

                var vals: [Float] = []
                vals.reserveCapacity(max(1, (y1 - y0) * (x1 - x0)))
                for y in y0..<y1 {
                    let row = y * w
                    for x in x0..<x1 {
                        let l = laplacian4(x: x, y: y, row: row, w: w, bitmap: bitmap)
                        vals.append(l)
                    }
                }

                cellVariances[gy * gridColumns + gx] = statisticalVariance(vals)
            }
        }

        let sorted = cellVariances.sorted()
        let median: Float
        if sorted.isEmpty {
            median = 0
        } else {
            let mid = sorted.count / 2
            if sorted.count % 2 == 0 {
                median = (sorted[mid - 1] + sorted[mid]) * 0.5
            } else {
                median = sorted[mid]
            }
        }

        let vmin = sorted.first ?? 0
        let vmax = sorted.last ?? 1
        let denom = max(vmax - vmin, 1e-6)

        let heatmap = cellVariances.map { v in
            (v - vmin) / denom
        }

        let blurScore = normalizedBlur(fromLaplacianVariance: median)

        return BlurAnalysisResult(
            sharpnessHeatmap: heatmap,
            gridColumns: gridColumns,
            gridRows: gridRows,
            globalLaplacianVariance: median,
            normalizedBlurScore: blurScore
        )
    }

    private func normalizedBlur(fromLaplacianVariance v: Float) -> Float {
        let t = (v - refVarianceBlurry) / max(refVarianceSharp - refVarianceBlurry, 1)
        let sharpness = min(max(t, 0), 1)
        return 1 - sharpness
    }

    private func laplacian4(x: Int, y: Int, row: Int, w: Int, bitmap: [UInt8]) -> Float {
        let c = Float(bitmap[row + x])
        let left = Float(bitmap[row + (x - 1)])
        let right = Float(bitmap[row + (x + 1)])
        let top = Float(bitmap[row - w + x])
        let bottom = Float(bitmap[row + w + x])
        return left + right + top + bottom - 4 * c
    }

    private func statisticalVariance(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let n = Float(values.count)
        let mean = values.reduce(Float(0)) { $0 + $1 } / n
        let sq = values.reduce(Float(0)) { partial, v in
            let d = v - mean
            return partial + d * d
        }
        return sq / (n - 1)
    }
}
