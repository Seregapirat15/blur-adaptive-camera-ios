import SwiftUI

struct ContentView: View {
    @StateObject private var model = CameraViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    if let img = model.previewImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        Text("Запуск камеры…")
                            .foregroundStyle(.secondary)
                    }

                    if model.showHeatmap {
                        HeatmapOverlayView(
                            columns: model.gridColumns,
                            rows: model.gridRows,
                            sharpness: model.heatmapSharpness,
                            size: geo.size
                        )
                        .allowsHitTesting(false)
                    }

                    if model.showFaces {
                        FaceOverlayView(
                            boxes: model.faceBoxesVisionNormalized,
                            size: geo.size
                        )
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            VStack {
                hud
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()

                controls
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
        }
        .onAppear { model.startCamera() }
        .onDisappear { model.stopCamera() }
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Размытость (оценка)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(model.normalizedBlurScore))
                .tint(.orange)

            HStack {
                labeledValue(title: "Blur", value: String(format: "%.2f", model.normalizedBlurScore))
                labeledValue(title: "Var*", value: String(format: "%.0f", model.globalLaplacianVariance))
                labeledValue(title: "FPS", value: String(format: "%.0f", model.fps))
            }

            HStack {
                labeledValue(
                    title: "Sharpness",
                    value: String(format: "%.2f", Double(model.sharpenSharpnessDisplay))
                )
                labeledValue(
                    title: "Radius",
                    value: String(format: "%.2f", Double(model.sharpenRadiusDisplay))
                )
                labeledValue(title: "Анализ", value: "\(model.analysisWidth)×\(model.analysisHeight)")
            }

            Text("* медиана дисперсии Лапласа по блокам (условные единицы)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Toggle("Коррекция резкости", isOn: $model.correctionEnabled)
            Toggle("Теплокарта резкости", isOn: $model.showHeatmap)
            Toggle("Рамки лиц (Vision)", isOn: $model.showFaces)

            Text("Проведите демонстрацию: наведите на текст — резче; смаз/дефокус — краснее на карте и выше Blur.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
    }
}

private struct HeatmapOverlayView: View {
    let columns: Int
    let rows: Int
    let sharpness: [Float]
    let size: CGSize

    var body: some View {
        Canvas { ctx, canvasSize in
            guard columns > 0, rows > 0 else { return }
            let cw = canvasSize.width / CGFloat(columns)
            let ch = canvasSize.height / CGFloat(rows)

            for gy in 0..<rows {
                for gx in 0..<columns {
                    let idx = gy * columns + gx
                    guard idx < sharpness.count else { continue }
                    let s = sharpness[idx]
                    let blur = max(0, min(1, 1 - s))

                    let rect = CGRect(x: CGFloat(gx) * cw, y: CGFloat(gy) * ch, width: cw, height: ch)
                    let color = heatColor(blur: blur)
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
        .blendMode(.plusLighter)
        .opacity(0.42)
        .allowsHitTesting(false)
        .frame(width: size.width, height: size.height)
    }

    private func heatColor(blur: CGFloat) -> Color {
        let sharp = 1 - blur
        let r = Double(blur)
        let g = Double(sharp) * 0.85
        let b = Double(sharp) * 0.35
        return Color(red: r, green: g, blue: b).opacity(0.95)
    }
}

private struct FaceOverlayView: View {
    let boxes: [CGRect]
    let size: CGSize

    var body: some View {
        Canvas { ctx, canvasSize in
            for box in boxes {
                let rect = visionNormalizedRectToView(box, canvasSize: canvasSize)
                let path = Path(roundedRect: rect, cornerRadius: 6)
                ctx.stroke(path, with: .color(.cyan.opacity(0.95)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
        .frame(width: size.width, height: size.height)
    }

    private func visionNormalizedRectToView(_ box: CGRect, canvasSize: CGSize) -> CGRect {
        let x = box.origin.x * canvasSize.width
        let w = box.size.width * canvasSize.width
        let h = box.size.height * canvasSize.height
        let y = (1 - box.origin.y - box.size.height) * canvasSize.height
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

#Preview {
    ContentView()
}
