import SwiftUI

/// Editing chrome: Done in the top-left and a one-time
/// line telling the user the only gesture there is.
///
/// There is no Select / Draw / Text / Elements toolbar. The canvas is not a
/// drawing surface — it is an arrangement of things that happened, and the only
/// thing worth arranging is where they sit.
struct CanvasEditingDock: View {
    let showsDragHint: Bool
    let onDone: () -> Void
    var nativeRecipe: Binding<NativeAtlasRecipe?>? = nil
    var automaticTraceStrength: Float = 0

    private let traceTitles: [LocalizedStringKey] = [
        "Band shifts", "Color separation", "Pixel fragments", "Wave", "Repeated contours"
    ]
    private let intersectionTitles: [LocalizedStringKey] = [
        "Transparent blending", "Luminous seam", "Overlay"
    ]

    private var ink: Color { AppColors.Night.textPrimary }

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    doneControl
                    Spacer(minLength: 0)
                }
                if showsDragHint {
                    dragHint
                        .padding(.top, 12)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }

            VStack {
                Spacer(minLength: 0)
                if let binding = nativeRecipe, binding.wrappedValue?.isSupported == true {
                    nativeControls(binding)
                }
            }
        }
    }

    private func nativeControls(_ binding: Binding<NativeAtlasRecipe?>) -> some View {
        VStack(spacing: 10) {
            Menu {
                ForEach(Array(traceTitles.enumerated()), id: \.offset) { index, title in
                    Button(title) { binding.wrappedValue?.glitchType = index }
                }
                Button("Use colors spent") { binding.wrappedValue?.glitchStrength = nil }
            } label: { Label("Digital trace", systemImage: "waveform.path") }
            Group {
                if let strength = binding.wrappedValue?.glitchStrength {
                    Text("Strength: \(Int(strength * 100)) / 100")
                } else {
                    Text("Based on colors spent")
                }
            }
            .font(.caption)
            Slider(value: Binding(get: { Double(binding.wrappedValue?.glitchStrength ?? automaticTraceStrength) * 100 }, set: { binding.wrappedValue?.glitchStrength = Float($0 / 100) }), in: 0...100) {
                Text("Trace strength")
            }
            Menu {
                ForEach(Array(intersectionTitles.enumerated()), id: \.offset) { index, title in
                    Button(title) { binding.wrappedValue?.intersectionType = index }
                }
            } label: { Label("Intersections", systemImage: "square.on.square") }
            Slider(value: Binding(get: { Double(binding.wrappedValue?.intersectionStrength ?? 0) * 100 }, set: { binding.wrappedValue?.intersectionStrength = Float($0 / 100) }), in: 0...100) {
                Text("Intersection strength")
            }
            Toggle("Lock effects", isOn: Binding(get: { binding.wrappedValue?.locks.contains("effects") == true }, set: { value in
                if value { binding.wrappedValue?.locks.insert("effects") } else { binding.wrappedValue?.locks.remove("effects") }
            }))
            Toggle("Lock artwork", isOn: Binding(get: { binding.wrappedValue?.locks.contains("artwork") == true }, set: { value in
                if value { binding.wrappedValue?.locks.insert("artwork") } else { binding.wrappedValue?.locks.remove("artwork") }
            }))
        }
        .font(.system(size: 15)).padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var doneControl: some View {
        Button(action: onDone) {
            Text(String(localized: "Done", comment: "Canvas editing – finish editing"))
                .font(.geist(size: 15, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .liquidGlassControl(in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Done editing", comment: "Canvas editing – Done VoiceOver label"))
        .accessibilityIdentifier("canvas_done_button")
    }

    private var dragHint: some View {
        Text(String(localized: "Drag elements to move", comment: "Canvas editing – one-time coach text"))
            .font(.geist(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .liquidGlassControl(in: Capsule(style: .continuous))
            .contrastingOnGlass()
            .allowsHitTesting(false)
    }
}
