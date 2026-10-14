import SwiftUI

struct HappeningOnboardingView: View {
    let dayKey: String
    let scope: String
    let replay: Bool
    let onComplete: () -> Void
    let onCancel: () -> Void
    @State private var profile = HappeningPersonalizationProfile()
    @State private var showsQuestions = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ink = Color(red: 0.13, green: 0.14, blue: 0.12)
    private var index: Int { min(max(profile.questionIndex, 0), 5) }
    private var question: HappeningPersonalizationQuestion { HappeningPersonalizationQuestion.allCases[index] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "nowhere").font(.nowhereDisplay(23))
                Spacer()
                Button(action: onCancel) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel(Text(verbatim: "Close questions"))
                    .accessibilityIdentifier("happenings.onboarding.close")
            }
            .padding(.horizontal, 24)
            if showsQuestions {
                HStack(spacing: 5) {
                    ForEach(0..<6) { step in Capsule().fill(ink.opacity(step <= index ? 0.75 : 0.13)).frame(height: 3) }
                }
                .padding(.horizontal, 28).padding(.top, 12)
                .accessibilityLabel(Text(verbatim: "Question \(index + 1) of 6"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: showsQuestions ? question.title : "A few questions first")
                        .font(.nowhereDisplay(35, relativeTo: .largeTitle))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: showsQuestions ? "Choose any that fit." : "Six short questions to find happenings that fit your days.")
                        .font(.onest(.body)).foregroundStyle(ink.opacity(0.66))
                    if showsQuestions { choices.padding(.top, 25) }
                }
                .padding(.horizontal, 26).padding(.top, 32).padding(.bottom, 28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            footer.padding(.horizontal, 26).padding(.bottom, 18)
        }
        .foregroundStyle(ink)
        .background(Color(red: 0.96, green: 0.965, blue: 0.93).ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear {
            if replay {
                HappeningPersonalizationStore.clearDraft(scope: scope)
                profile = HappeningPersonalizationStore.load(scope: scope)
                profile.completion = .pending; profile.questionIndex = 0; profile.hasStarted = false
            } else { profile = HappeningPersonalizationStore.draft(scope: scope) ?? HappeningPersonalizationStore.load(scope: scope) }
            showsQuestions = profile.hasStarted
        }
        .onDisappear { persist() }
        .accessibilityIdentifier("happenings.onboarding")
    }

    private var rowSizes: [Int] {
        switch question.choices.count { case 8: [3, 2, 3]; case 7: [2, 3, 2]; default: [3, 3] }
    }
    private var choices: some View {
        VStack(spacing: 22) {
            ForEach(Array(rowSizes.enumerated()), id: \.offset) { row, count in
                let start = rowSizes.prefix(row).reduce(0, +)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(question.choices.dropFirst(start).prefix(count))) { choice in
                        HappeningSurveyMark(choice: choice, question: question,
                            selected: profile.answers[question.rawValue, default: []].contains(choice.id),
                            onSelect: { set(choice.id, selected: true) },
                            onDeselect: { set(choice.id, selected: false) },
                            onToggle: { set(choice.id, selected: !profile.answers[question.rawValue, default: []].contains(choice.id)) })
                            .frame(maxWidth: 125)
                    }
                }.frame(maxWidth: .infinity)
            }
        }
        .id(question.rawValue)
    }
    private var footer: some View {
        VStack(spacing: 15) {
            Button(action: advance) {
                Text(verbatim: showsQuestions ? (index == 5 ? "Find my happenings" : "Continue") : "Start")
                    .font(.onest(17, weight: .medium))
                    .frame(maxWidth: .infinity).frame(minHeight: 54)
                    .foregroundStyle(.white).background(ink, in: Capsule())
            }.accessibilityIdentifier("happenings.onboarding.continue")
            HStack {
                Button(action: back) { Text(verbatim: showsQuestions ? "Back" : "Back to Today") }
                Spacer()
                if showsQuestions {
                    let count = profile.answers[question.rawValue, default: []].count
                    Text(verbatim: count == 0 ? "Choose any that fit" : "\(count) selected")
                        .foregroundStyle(ink.opacity(0.5)).font(.onest(.caption))
                }
                Spacer()
                Button(action: skip) { Text(verbatim: showsQuestions ? "Skip" : "Skip questions") }
                    .accessibilityIdentifier("happenings.onboarding.skip")
            }.font(.onest(.footnote)).frame(minHeight: 44)
        }.frame(maxWidth: 560).frame(maxWidth: .infinity)
    }
    private func persist() {
        if profile.completion == .pending { HappeningPersonalizationStore.saveDraft(profile, scope: scope) }
    }
    private func set(_ id: String, selected: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.58)) {
            if selected { profile.answers[question.rawValue, default: []].insert(id) }
            else { profile.answers[question.rawValue, default: []].remove(id) }
        }
        if question == .feelings { profile.emotionDayKey = dayKey }
        persist()
    }
    private func advance() {
        if !showsQuestions { profile.hasStarted = true; showsQuestions = true }
        else if index == 5 { finish(skipped: false); return }
        else { profile.questionIndex = index + 1 }
        persist()
    }
    private func back() {
        if !showsQuestions { onCancel() }
        else if index == 0 { showsQuestions = false; profile.hasStarted = false; persist() }
        else { profile.questionIndex = index - 1; persist() }
    }
    private func skip() {
        if !showsQuestions { profile.answers = [:]; finish(skipped: true) }
        else { profile.answers[question.rawValue] = []; advance() }
    }
    private func finish(skipped: Bool) {
        guard scope == HappeningPersonalizationStore.scope else {
            persist()
            onCancel()
            return
        }
        profile.completion = skipped ? .skipped : .completed
        profile.hasStarted = false
        HappeningPersonalizationStore.save(profile, scope: scope)
        HappeningPersonalizationStore.clearDraft(scope: scope)
        onComplete()
    }
}

private struct HappeningSurveyMark: View {
    let choice: HappeningPersonalizationChoice
    let question: HappeningPersonalizationQuestion
    let selected: Bool
    let onSelect: () -> Void
    let onDeselect: () -> Void
    let onToggle: () -> Void
    @State private var materialImage: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var seed: UInt64 { CanvasElement.makeSeed(optionId: "survey:\(question.rawValue):\(choice.id)", dayKey: "happenings-v1", index: 0) }
    private var preset: MetalShapePreset? { MetalShapeGenomeCatalog.presets.first { $0.id == question.presetID } }
    private var points: [SIMD2<Float>] {
        guard let preset else { return [] }
        if let points = try? MetalShapeContour.sample(preset: preset, count: 96, seed: seed) { return points }
        // The legacy families use the exact radial boundaries in
        // ShapeAtlas/Geometry/MetalShapeBasic.metalh. Their final material image
        // is rendered by that shader, including the same contour.
        guard case let .legacy(shape, variant) = preset.contour else { return [] }
        return (0..<96).map { index in
            let angle = Float(index) * 2 * .pi / 96
            let unit = SIMD2<Float>(cos(angle), sin(angle))
            let radius: Float
            if shape == 6 {
                let exponent: Float = 2.3 + 1.2 * floor(Float(max(variant, 1) - 1) / 16)
                radius = pow(pow(abs(unit.x), exponent) + pow(abs(unit.y), exponent), -1 / exponent)
            } else if shape == 5 {
                let sides = Float(3 + (max(variant, 1) - 1) % 4)
                let sector = 2 * Float.pi / sides
                let folded = angle - sector * floor((angle + sector * 0.5) / sector)
                let polygon = cos(Float.pi / sides) / max(cos(folded), 0.0001)
                radius = polygon * 0.88 + 0.94 * 0.12
            } else { radius = 1 }
            return unit * radius
        }
    }
    private var color: Color {
        guard let preset else { return .green }
        let c = MetalShapeGenomeFrame.make(preset: preset, material: .radialTwo, seed: seed).material.color0
        return Color(.sRGBLinear, red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: 1)
    }
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                HappeningSurveyContour(points: points, progress: selected ? 1 : 0)
                    .fill(LinearGradient(colors: selected ? [color, color.opacity(0.64)] : [Color.white.opacity(0.95), Color(red: 0.86, green: 0.88, blue: 0.84)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let materialImage {
                    Image(uiImage: materialImage).resizable().scaledToFit()
                        .opacity(selected ? 1 : 0)
                        .mask(HappeningSurveyContour(points: points, progress: selected ? 1 : 0))
                }
            }
            .frame(width: 99, height: 99)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.58), value: selected)
            Text(verbatim: choice.label).font(.onest(13, relativeTo: .caption))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32, alignment: .top)
        }
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded { if selected { onDeselect() } else { onSelect() } }
            .exclusively(before: TapGesture(count: 1).onEnded { if !selected { onSelect() } }))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: choice.label))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { onToggle() }
        .accessibilityIdentifier("happenings.onboarding.\(question.rawValue).\(choice.id)")
        .task(id: question.rawValue + choice.id) {
            guard let preset else { return }
            let image = try? await MetalShapeGenomeRenderer.image(preset: preset, material: .radialTwo,
                seed: seed, size: CGSize(width: 99, height: 99), scale: 2)
            guard !Task.isCancelled else { return }
            materialImage = image
        }
    }
}

/// Equal angular samples interpolate the production contour into a circle.
private struct HappeningSurveyContour: Shape {
    let points: [SIMD2<Float>]
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = max(points.count, 96)
        for index in 0..<count {
            let angle = CGFloat(index) * 2 * .pi / CGFloat(count)
            let circle = CGPoint(x: cos(angle), y: sin(angle))
            let target = points.indices.contains(index) ? CGPoint(x: CGFloat(points[index].x), y: CGFloat(points[index].y)) : circle
            let point = CGPoint(x: rect.midX + (circle.x + (target.x - circle.x) * progress) * rect.width / 2.72,
                                y: rect.midY + (circle.y + (target.y - circle.y) * progress) * rect.height / 2.72)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

#if DEBUG
struct HappeningOnboardingDeveloperPage: View {
    var body: some View {
        Form {
            Section {
                Text(verbatim: "Replay the six questions, then choose actual happenings in the live palette. Your recorded days stay in place.")
                Button("Start Happenings onboarding") { HappeningOnboardingCoordinator.shared.replay() }
                    .accessibilityIdentifier("happenings.onboarding.debug.start")
            }
        }.font(.onest(.body))
            .navigationTitle("Happenings onboarding (Debug)")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
