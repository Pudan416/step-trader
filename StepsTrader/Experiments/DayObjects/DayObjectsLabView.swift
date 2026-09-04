import SwiftUI

#if DEBUG || INTERNAL_BUILD
import AVFAudio
import Combine
import UIKit
#endif

#if DEBUG || INTERNAL_BUILD
@MainActor
final class DayObjectsSystemAccessibilityStatusSource: DayObjectsAccessibilityStatusSource {
    @Published private(set) var isVoiceOverRunning: Bool

    private let voiceOverStatus: @MainActor () -> Bool
    private var notificationCancellable: AnyCancellable?

    var voiceOverStatusChanges: AnyPublisher<Bool, Never> {
        $isVoiceOverRunning.eraseToAnyPublisher()
    }

    init(
        notificationCenter: NotificationCenter = .default,
        voiceOverStatus: @escaping @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning }
    ) {
        self.voiceOverStatus = voiceOverStatus
        isVoiceOverRunning = voiceOverStatus()
        notificationCancellable = notificationCenter
            .publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isVoiceOverRunning = self.voiceOverStatus()
            }
    }
}
#endif

#if DEBUG || INTERNAL_BUILD
/// Interactive bench for the deterministic daily choreography.
///
/// Event IDs stay chronological as the happenings slider grows, so the live
/// canvas exercises actor insertion rather than rebuilding a count-seeded
/// field. The grid intentionally freezes fifteen renderers at once.
struct DayObjectsLabView: View {
    static let uiExclusionRegion = DayObjectNormalizedRect.dayObjectsLabControls

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var dayOffset = 0
    @State private var showsGrid = false
    @State private var showControls = true
    @State private var showsFineTuning = false
    @State private var showsInstrumentDiagnostics = false
    @State private var motionEnergyOverride: Double?
    @State private var visualClarityOverride: Double?
    @StateObject private var musicController: DayObjectsMusicLabController
    @StateObject private var audition: DayObjectsInstrumentAuditionController
    @StateObject private var leadCoordinator: DayObjectsLeadAuditionCoordinator

    init() {
        _musicController = StateObject(wrappedValue: DayObjectsMusicLabController())
        let auditionController = DayObjectsInstrumentAuditionController()
        _audition = StateObject(wrappedValue: auditionController)
        _leadCoordinator = StateObject(wrappedValue: DayObjectsLeadAuditionCoordinator(
            controller: auditionController,
            accessibilityStatusSource: DayObjectsSystemAccessibilityStatusSource()
        ))
    }

    init(
        auditionController: DayObjectsInstrumentAuditionController,
        accessibilityStatusSource: any DayObjectsAccessibilityStatusSource
    ) {
        _musicController = StateObject(wrappedValue: DayObjectsMusicLabController())
        let leadCoordinator = DayObjectsLeadAuditionCoordinator(
            controller: auditionController,
            accessibilityStatusSource: accessibilityStatusSource
        )
        _audition = StateObject(wrappedValue: auditionController)
        _leadCoordinator = StateObject(wrappedValue: leadCoordinator)
    }

    private var dayKey: String { Self.dayKey(for: dayOffset) }

    private var happeningCount: Int {
        musicController.state.happeningCount
    }

    private var currentSceneInput: DayObjectSceneInput {
        sceneInput(for: dayKey)
    }

    private var spentColorCount: Int {
        musicController.state.spentColors
    }

    private var digitalImpact: DayObjectDigitalImpact {
        musicController.digitalImpact
    }

    private var currentScene: DayObjectScene {
        DayObjectScene.make(input: currentSceneInput)
    }

    private var chromeColorScheme: ColorScheme {
        relativeLuminance(currentScene.palette.backgroundBase) > 0.45 ? .light : .dark
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { _ in
                VStack(spacing: 0) {
                    canvasContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showControls {
                        controls
                    }
                }
            }
            topButtons
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showControls)
        .navigationTitle("Day Objects")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(chromeColorScheme, for: .navigationBar)
        .onAppear {
            _ = musicController.acceptLifecycleEvent(.viewAppeared)
        }
        .onDisappear {
            leadCoordinator.viewDidDisappear()
            let intent = musicController.acceptLifecycleEvent(.viewDisappeared)
            Task { await musicController.completeLifecycleEvent(intent) }
        }
        .onChange(of: scenePhase) { _, phase in
            let isActive = phase == .active
            leadCoordinator.sceneActivityChanged(isActive: isActive)
            let intent = musicController.acceptLifecycleEvent(isActive ? .sceneActive : .sceneInactive)
            Task { await musicController.completeLifecycleEvent(intent) }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            let raw = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
                ?? (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
            guard let raw,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            leadCoordinator.interruptionBegan()
            let intent = musicController.acceptLifecycleEvent(.interruptionBegan)
            Task { await musicController.completeLifecycleEvent(intent) }
        }
        .onChange(of: leadCoordinator.isVoiceOverRunning) { _, running in
            musicController.leadAvailabilityChanged(
                isGridVisible: showsGrid,
                isVoiceOverRunning: running
            )
        }
    }

    @ViewBuilder
    private var canvasContent: some View {
        if showsGrid {
            grid
        } else {
            ZStack {
                DayObjectsView(
                    sceneInput: currentSceneInput,
                    digitalImpact: digitalImpact
                )
                .ignoresSafeArea()
                leadAuditionSurface
            }
        }
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
        .accessibilityValue("Spent colors \(spentColorCount). Touch performance unavailable")
        .accessibilityIdentifier("dayObjects.grid")
    }

    // MARK: - Controls

    private var controls: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                slider(
                    "Steps",
                    value: Binding(
                        get: { musicController.state.steps },
                        set: { musicController.setSteps($0) }
                    ),
                    range: 0...DayObjectsMusicLabController.maximumSteps,
                    step: 100,
                    readout: stepsReadout,
                    identifier: "dayObjects.steps"
                )

                slider(
                    "Sleep",
                    value: Binding(
                        get: { musicController.state.sleepHours },
                        set: { musicController.setSleepHours($0) }
                    ),
                    range: 0...DayObjectsMusicLabController.maximumSleepHours,
                    step: 0.25,
                    readout: sleepReadout,
                    identifier: "dayObjects.sleep"
                )

                slider(
                    "Happenings",
                    value: Binding(
                        get: { Double(musicController.state.happeningCount) },
                        set: { musicController.setHappeningCount(Int($0.rounded())) }
                    ),
                    range: 0...Double(DayObjectsMusicLabController.maximumHappenings),
                    step: 1,
                    readout: "\(happeningCount) · \(currentScene.actors.count) figures",
                    identifier: "dayObjects.happenings"
                )

                digitalImpactControls
                HappeningSoundPadGrid(
                    controller: musicController,
                    beforeAudition: { await audition.stop() }
                )
                remixControls
                fineTuning
                instrumentDiagnostics
                navigationControls

                if !showsGrid {
                    Text("\(dayKey) · \(currentScene.composition.summary)")
                        .font(.geist(.caption2).monospaced())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .tint(AppColors.brandAccent)
    }

    private var remixControls: some View {
        VStack(spacing: 6) {
            Button {
                musicController.remix()
            } label: {
                Label("Remix", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("dayObjects.remix")

            Text(musicController.worldSummary)
                .font(.geist(.caption2).monospaced())
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityIdentifier("dayObjects.worldSummary")
        }
    }

    private var instrumentDiagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosureButton(
                title: "Instrument diagnostics",
                isExpanded: $showsInstrumentDiagnostics,
                identifier: "dayObjects.instrumentDiagnostics",
                onChange: { isExpanded in
                    guard !isExpanded else { return }
                    musicController.disableDiagnostics()
                    Task { await audition.stop() }
                }
            )
            if showsInstrumentDiagnostics {
                DayObjectsInstrumentAuditionView(
                    controller: audition,
                    musicController: musicController,
                    beforeAudition: { await musicController.turnSoundOff() }
                )
            }
        }
    }

    private var fineTuning: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosureButton(
                title: "Fine tuning",
                isExpanded: $showsFineTuning,
                identifier: "dayObjects.fineTuning"
            )
            if showsFineTuning {
                slider(
                    "Motion",
                    value: Binding(
                        get: { motionEnergyOverride ?? musicController.normalizedInput.motionEnergy },
                        set: { motionEnergyOverride = $0 }
                    ),
                    range: 0...1,
                    step: 0.05,
                    readout: currentSceneInput.motionEnergy.formatted(.number.precision(.fractionLength(2))),
                    identifier: "dayObjects.motionEnergy"
                )
                slider(
                    "Focus",
                    value: Binding(
                        get: { visualClarityOverride ?? musicController.normalizedInput.visualClarity },
                        set: { visualClarityOverride = $0 }
                    ),
                    range: 0...1,
                    step: 0.05,
                    readout: currentSceneInput.visualClarity.formatted(.number.precision(.fractionLength(2))),
                    identifier: "dayObjects.visualClarity"
                )
                Button("Reset to day progress") {
                    motionEnergyOverride = nil
                    visualClarityOverride = nil
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("dayObjects.fineTuning.reset")
            }
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 10) {
            Button {
                dayOffset += showsGrid ? 15 : 1
            } label: {
                Label(showsGrid ? "Next 15" : "Next day", systemImage: "dice")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("dayObjects.nextDay")

            Button {
                showsGrid.toggle()
                leadCoordinator.gridVisibilityChanged(isVisible: showsGrid)
                musicController.leadAvailabilityChanged(
                    isGridVisible: showsGrid,
                    isVoiceOverRunning: leadCoordinator.isVoiceOverRunning
                )
            } label: {
                Label(showsGrid ? "Single" : "Grid", systemImage: "square.grid.3x3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("dayObjects.gridToggle")
        }
    }

    private var digitalImpactControls: some View {
        VStack(spacing: 7) {
            slider(
                "Spent colors",
                value: Binding(
                    get: { Double(musicController.state.spentColors) },
                    set: { musicController.setSpentColors(Int($0.rounded())) }
                ),
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
                        musicController.setSpentColors(preset)
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
            musicController.setSpentColors(adjusted)
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

    private func disclosureButton(
        title: String,
        isExpanded: Binding<Bool>,
        identifier: String,
        onChange: ((Bool) -> Void)? = nil
    ) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
            onChange?(isExpanded.wrappedValue)
        } label: {
            HStack {
                Text(title)
                    .font(.geist(.caption).weight(.semibold))
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isExpanded.wrappedValue ? "expanded" : "collapsed")
    }

    private var stepsReadout: String {
        "\(Int(musicController.state.steps).formatted()) / \(Int(musicController.state.stepGoal).formatted()) steps"
    }

    private var sleepReadout: String {
        "\(compactNumber(musicController.state.sleepHours)) / \(compactNumber(musicController.state.sleepGoalHours)) hours"
    }

    private func compactNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return value.formatted(.number.precision(.fractionLength(2)))
    }

    private var topButtons: some View {
        VStack {
            HStack(spacing: 10) {
                Spacer()
                soundButton
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

    private var soundButton: some View {
        Button {
            guard let intent = musicController.acceptSoundButtonIntent() else { return }
            Task {
                await audition.stop()
                await musicController.completeSoundButtonIntent(intent)
            }
        } label: {
            Image(systemName: soundIcon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(musicController.soundState == .starting)
        .accessibilityLabel(soundLabel)
        .accessibilityValue(soundValue)
        .accessibilityIdentifier("dayObjects.sound")
        .tint(chromeColorScheme == .dark ? .white : .black)
    }

    private var soundIcon: String {
        switch musicController.soundState {
        case .off: "speaker.slash.fill"
        case .starting: "hourglass"
        case .on: "speaker.wave.2.fill"
        case .error: "exclamationmark.arrow.triangle.2.circlepath"
        }
    }

    private var soundLabel: String {
        switch musicController.soundState {
        case .off: "Turn Sound on"
        case .starting: "Starting Sound"
        case .on: "Turn Sound off"
        case .error: "Retry Sound"
        }
    }

    private var soundValue: String {
        switch musicController.soundState {
        case .off: "off"
        case .starting: "starting"
        case .on: "on"
        case let .error(error): "error, retry available: \(error.message)"
        }
    }

    private var leadAuditionSurface: some View {
        DayObjectsLeadGestureSurface(
            isEnabled: musicController.soundState == .on
                && !showsGrid
                && !leadCoordinator.isVoiceOverRunning,
            // This surface is already laid out strictly inside the canvas;
            // the controls are sibling chrome below it, not part of its local
            // normalized coordinate space.
            uiExclusionRegion: nil,
            onBegin: { gesture in
                musicController.beginLead(
                    gesture,
                    isGridVisible: showsGrid,
                    isVoiceOverRunning: leadCoordinator.isVoiceOverRunning
                )
            },
            onUpdate: { gesture in
                musicController.updateLead(gesture)
            },
            onEnd: {
                musicController.endLead()
            }
        )
    }

    private func sceneInput(for key: String) -> DayObjectSceneInput {
        musicController.sceneInput(
            dayKey: key,
            reduceMotion: reduceMotion,
            motionEnergyOverride: motionEnergyOverride,
            visualClarityOverride: visualClarityOverride,
            uiExclusionRegion: Self.uiExclusionRegion
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
#else
struct DayObjectsLabView: View {
    static let uiExclusionRegion = DayObjectNormalizedRect.dayObjectsLabControls

    var body: some View { EmptyView() }
}
#endif

#Preview {
    NavigationStack { DayObjectsLabView() }
}
