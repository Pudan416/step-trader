#if DEBUG
import SwiftUI

struct MetalShapeAtlasExportView: View {
    @State private var status = "Подготовка Metal-рендеров…"

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(status).multilineTextAlignment(.center)
        }
        .padding(32)
        .task {
            do {
                let documents = try FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                if UserDefaults.standard.bool(forKey: "gateArtworkExport") {
                    try await MetalShapeAtlasExport.exportGateArtwork(to: documents.appendingPathComponent("GateArtwork"))
                } else {
                    try await MetalShapeAtlasExport.export(to: documents.appendingPathComponent("MetalShapeAtlasExport"))
                }
                status = "Экспорт готов"
            } catch {
                status = "Ошибка экспорта: \(error.localizedDescription)"
            }
        }
    }
}
#endif
