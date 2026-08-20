import SwiftUI

/// Bench for the two additions: dust and focus.
///
/// The point of the lab is the A/B toggle — the question is not "does this look
/// nice" but "is the flat version visibly worse", and that only shows up when
/// you can flip between them on the same canvas.
struct CanvasAtmosphereLabView: View {
    let loadCanvas: (String) -> DayCanvas?

    @State private var steps: Double = 8_400
    @State private var sleepHours: Double = 7.5
    @State private var showsAtmosphere = true
    @State private var showControls = true

    init(loadCanvas: @escaping (String) -> DayCanvas? = {
        CanvasStorageService.shared.loadCanvas(for: $0)
    }) {
        self.loadCanvas = loadCanvas
    }

    private var atmosphere: CanvasAtmosphere {
        CanvasAtmosphere.forDay(steps: Int(steps), sleepHours: sleepHours)
    }

    /// Today's real canvas when there is one, a deterministic stand-in when
    /// there is not — an empty bench cannot answer the question it exists for.
    private var canvas: DayCanvas {
        let dayKey = AppModel.dayKey(for: .now)
        if let stored = loadCanvas(dayKey), !stored.elements.isEmpty {
            return stored
        }
        return CanvasAtmosphereDemoCanvas.make(dayKey: dayKey)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CanvasAtmosphereView(
                canvas: canvas,
                atmosphere: atmosphere,
                showsAtmosphere: showsAtmosphere
            )
            .ignoresSafeArea()

            if showControls {
                controls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            toggleButton
        }
        .animation(.easeInOut(duration: 0.25), value: showControls)
        .navigationTitle("Atmosphere")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Toggle("Atmosphere", isOn: $showsAtmosphere)
                .font(.subheadline)
                .foregroundStyle(.white)

            slider("Steps", value: $steps, range: 0...20_000, step: 100,
                   readout: "\(Int(steps))",
                   derived: String(format: "dust %.2f", atmosphere.dust))

            slider("Sleep", value: $sleepHours, range: 0...10, step: 0.25,
                   readout: String(format: "%.1f h", sleepHours),
                   derived: String(format: "focus %.2f", atmosphere.focus))

            Text("far \(Int(atmosphere.blurRadius(for: .far)))  ·  mid \(Int(atmosphere.blurRadius(for: .mid)))  ·  near \(Int(atmosphere.blurRadius(for: .near)))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.bottom, 60)
        .tint(AppColors.brandAccent)
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        readout: String,
        derived: String
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(readout).font(.caption.monospacedDigit())
                Text(derived)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white.opacity(0.85))

            Slider(value: value, in: range, step: step)
        }
    }

    private var toggleButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    showControls.toggle()
                } label: {
                    Image(systemName: showControls ? "slider.horizontal.3" : "eye")
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .tint(.white)
                .padding(.trailing, 16)
            }
            Spacer()
        }
    }
}

// MARK: - Stand-in canvas

/// A deterministic set of elements for days with an empty canvas. Built through
/// the real `spawn`, so it obeys the day's composition exactly like a canvas
/// filled by hand — the bench must not flatter the renderer with data it would
/// never see.
enum CanvasAtmosphereDemoCanvas {
    static let sample: [(id: String, label: String)] = [
        ("walk", "Walk"),
        ("reading", "Reading"),
        ("coffee", "Coffee"),
        ("run", "Run"),
        ("music", "Music"),
        ("call", "Call"),
        ("rest", "Rest"),
    ]

    static func make(dayKey: String) -> DayCanvas {
        var canvas = DayCanvas(dayKey: dayKey)
        canvas.stepsPoints = 12
        canvas.sleepPoints = 14
        canvas.hasStepsData = true
        canvas.hasSleepData = true

        var elements = [CanvasElement]()
        for (index, item) in sample.enumerated() {
            let composition = DayComposition.forDay(dayKey: dayKey, happeningCount: index)
            elements.append(
                CanvasElement.spawn(
                    optionId: item.id,
                    label: item.label,
                    existingElements: elements,
                    allowedShapeTypes: CanvasShapeType.selectableCases,
                    dayKey: dayKey,
                    composition: composition
                )
            )
        }
        canvas.elements = elements
        return canvas
    }
}

#Preview {
    NavigationStack {
        CanvasAtmosphereLabView { _ in nil }
    }
}
