import SwiftUI

/// Interactive bench for the deterministic daily choreography.
///
/// Event IDs stay chronological as the happenings slider grows, so the live
/// canvas exercises actor insertion rather than rebuilding a count-seeded
/// field. The grid intentionally freezes fifteen renderers at once.
struct DayObjectsLabView: View {
    static let uiExclusionRegion = DayObjectNormalizedRect.dayObjectsLabControls
    static let canvasCoverage = DayObjectCanvasCoverage.fullCanvas

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SharedKeys.modernPaletteCategories) private var modernPaletteCategoriesRaw = ""

    @State private var dayOffset = 0
    @State private var happenings: Double = 8
    @State private var motionEnergy = 0.55
    @State private var visualClarity = 0.55
    @State private var spentColors: Double = 0
    @State private var showsGrid = false
    @State private var showControls = true

    private var dayKey: String {
        Self.dayKey(for: dayOffset)
    }

    private var happeningCount: Int {
        min(max(Int(happenings.rounded()), 0), DayObjectScene.maxActors)
    }

    private var currentSceneInput: DayObjectSceneInput {
        sceneInput(for: dayKey)
    }

    private var spentColorCount: Int {
        min(max(Int(spentColors.rounded()), 0), DayObjectDigitalImpact.maximumSpentColors)
    }

    private var digitalImpact: DayObjectDigitalImpact {
        DayObjectDigitalImpact(spentColors: spentColorCount)
    }

    private var currentScene: DayObjectScene {
        DayObjectScene.make(input: currentSceneInput)
    }

    private var chromeColorScheme: ColorScheme {
        relativeLuminance(currentScene.palette.backgroundBase) > 0.45 ? .light : .dark
    }

    private var languageSummary: String {
        let mutationCounts = Dictionary(
            grouping: currentScene.actors,
            by: { $0.appearance.mutationRole }
        ).mapValues(\.count)
        let palettes = [
            currentScene.paletteSet.background.code,
            currentScene.paletteSet.primaryObjects.code,
            currentScene.paletteSet.secondaryObjects.code,
        ].joined(separator: "/")
        return "family=\(currentScene.visualLanguage.family) "
            + "mutations=\(mutationCounts[.base, default: 0])/"
            + "\(mutationCounts[.soft, default: 0])/"
            + "\(mutationCounts[.accent, default: 0]) "
            + "motion=\(currentScene.motionPlan.preset) "
            + "palettes=\(palettes)"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if showsGrid {
                grid
            } else {
                DayObjectsView(
                    sceneInput: currentSceneInput,
                    digitalImpact: digitalImpact
                )
                    .ignoresSafeArea()
            }

            if showControls {
                controls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            toggleButton
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showControls)
        .navigationTitle("Day Objects")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(chromeColorScheme, for: .navigationBar)
    }

    // MARK: - Grid

    private var grid: some View {
        GeometryReader { geometry in
            let columns = 3
            let rows = 5
            let width = geometry.size.width / CGFloat(columns)
            let height = geometry.size.height / CGFloat(rows)

            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = dayOffset + row * columns + column
                            DayObjectsView(
                                sceneInput: sceneInput(for: Self.dayKey(for: index)),
                                digitalImpact: digitalImpact,
                                isAnimating: false
                            )
                            .frame(width: width, height: height)
                            .clipped()
                            .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day Objects grid")
        .accessibilityValue("Spent colors \(spentColorCount)")
        .accessibilityIdentifier("dayObjects.grid")
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    dayOffset += showsGrid ? 15 : 1
                } label: {
                    Label(showsGrid ? "Next 15" : "Next day", systemImage: "dice")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("dayObjects.nextDay")

                Button {
                    showsGrid.toggle()
                } label: {
                    Label(showsGrid ? "Single" : "Grid", systemImage: "square.grid.3x3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("dayObjects.gridToggle")
            }

            slider(
                "Happenings",
                value: $happenings,
                range: 0...Double(DayObjectScene.maxActors),
                step: 1,
                readout: "\(happeningCount) · \(currentScene.actors.count) figures",
                identifier: "dayObjects.happenings"
            )
            slider(
                "Motion",
                value: $motionEnergy,
                range: 0...1,
                step: 0.05,
                readout: motionEnergy.formatted(.number.precision(.fractionLength(2))),
                identifier: "dayObjects.motionEnergy"
            )
            slider(
                "Focus",
                value: $visualClarity,
                range: 0...1,
                step: 0.05,
                readout: visualClarity.formatted(.number.precision(.fractionLength(2))),
                identifier: "dayObjects.visualClarity"
            )
            digitalImpactControls

            if !showsGrid {
                Text(languageSummary)
                    .font(.geist(.caption2).monospaced())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityIdentifier("dayObjects.language")
                    .accessibilityValue(languageSummary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.bottom, 60)
        .tint(AppColors.brandAccent)
    }

    private var digitalImpactControls: some View {
        VStack(spacing: 7) {
            slider(
                "Spent colors",
                value: $spentColors,
                range: 0...Double(DayObjectDigitalImpact.maximumSpentColors),
                step: 1,
                readout: "Spent colors \(spentColorCount)",
                identifier: "dayObjects.spentColors"
            )

            HStack(spacing: 6) {
                impactStepButton("−10", amount: -10, identifier: "minus10")
                impactStepButton("+1", amount: 1, identifier: "plus1")
                impactStepButton("+5", amount: 5, identifier: "plus5")
                impactStepButton("+10", amount: 10, identifier: "plus10")
            }

            HStack(spacing: 5) {
                ForEach([0, 10, 25, 50, 75, 100], id: \.self) { preset in
                    Button("\(preset)") {
                        spentColors = Double(preset)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Set spent colors to \(preset)")
                    .accessibilityIdentifier("dayObjects.spend.preset.\(preset)")
                }
            }
        }
        .controlSize(.small)
    }

    private func impactStepButton(
        _ title: String,
        amount: Int,
        identifier: String
    ) -> some View {
        Button(title) {
            let adjusted = min(
                max(spentColorCount + amount, 0),
                DayObjectDigitalImpact.maximumSpentColors
            )
            spentColors = Double(adjusted)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Adjust spent colors by \(amount)")
        .accessibilityIdentifier("dayObjects.spend.\(identifier)")
    }

    private func slider(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        readout: String,
        identifier: String
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                    .font(.geist(.caption))
                Spacer()
                Text(readout)
                    .font(.geist(.caption).monospacedDigit())
            }
            .foregroundStyle(.white.opacity(0.85))

            Slider(value: value, in: range, step: step)
                .accessibilityIdentifier(identifier)
                .accessibilityValue(readout)
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
                .accessibilityLabel(showControls ? "Hide controls" : "Show controls")
                .accessibilityIdentifier("dayObjects.controlsToggle")
                .tint(chromeColorScheme == .dark ? .white : .black)
                .padding(.trailing, 16)
            }
            Spacer()
        }
    }

    private func sceneInput(for key: String) -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: key,
            identity: "day-objects-lab",
            eventIDs: (0..<happeningCount).map { "lab-event-\($0)" },
            motionEnergy: motionEnergy,
            visualClarity: visualClarity,
            reduceMotion: reduceMotion,
            canvasCoverage: Self.canvasCoverage,
            paletteCategories: ModernPaletteSelection.decode(modernPaletteCategoriesRaw)
        )
    }

    private static func dayKey(for offset: Int) -> String {
        String(
            format: "2026-%02d-%02d",
            (offset / 28) % 12 + 1,
            offset % 28 + 1
        )
    }
}

#Preview {
    NavigationStack { DayObjectsLabView() }
}
