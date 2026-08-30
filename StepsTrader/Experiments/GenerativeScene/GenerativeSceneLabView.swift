import SwiftUI

/// Prototype bench for the generative daily scene.
///
/// The sliders are in domain units (steps, hours, happenings) rather than
/// normalised `0...1`, so what gets tested is the mapping in
/// `GenerativeSceneParams`, not just the shader's response to numbers.
struct GenerativeSceneLabView: View {
    @State private var steps: Double = 7_200
    @State private var sleepHours: Double = 7.0
    @State private var eventCount: Double = 2
    @State private var quality: Double = 40
    @State private var seed: Double = 0.31
    @State private var showControls = true

    private var params: GenerativeSceneParams {
        GenerativeSceneParams(
            energy: GenerativeSceneParams.energy(forSteps: Int(steps)),
            clarity: GenerativeSceneParams.clarity(forSleepHours: sleepHours),
            events: GenerativeSceneParams.events(forCount: Int(eventCount)),
            seed: seed,
            palette: GenerativeScenePalette.forSeed(seed)
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GenerativeSceneView(params: params, quality: quality)
            .ignoresSafeArea()

            if showControls {
                controls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            toggleButton
        }
        .animation(.easeInOut(duration: 0.25), value: showControls)
        .navigationTitle("Generative Scene")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    seed = Double.random(in: 0..<1)
                } label: {
                    Label("New day", systemImage: "dice")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) {
                        eventCount = min(eventCount + 1, 5)
                    }
                } label: {
                    Label("Add event", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            slider("Steps", value: $steps, range: 0...20_000, step: 100,
                   readout: "\(Int(steps))",
                   normalised: GenerativeSceneParams.energy(forSteps: Int(steps)))

            slider("Sleep", value: $sleepHours, range: 0...10, step: 0.25,
                   readout: String(format: "%.1f h", sleepHours),
                   normalised: GenerativeSceneParams.clarity(forSleepHours: sleepHours))

            slider("Events", value: $eventCount, range: 0...5, step: 1,
                   readout: "\(Int(eventCount))",
                   normalised: GenerativeSceneParams.events(forCount: Int(eventCount)))

            Divider().overlay(Color.white.opacity(0.2))

            slider("Steps/ray", value: $quality, range: 16...72, step: 2,
                   readout: "\(Int(quality))", normalised: nil)

            Text("\(params.palette.name) · seed \(String(format: "%.4f", seed))")
                .font(.geist(.caption2))
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
        normalised: Double?
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                    .font(.geist(.caption))
                Spacer()
                Text(readout)
                    .font(.geist(.caption).monospacedDigit())
                if let normalised {
                    Text(String(format: "→ %.2f", normalised))
                        .font(.geist(.caption2).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
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

#Preview {
    NavigationStack {
        GenerativeSceneLabView()
    }
}
