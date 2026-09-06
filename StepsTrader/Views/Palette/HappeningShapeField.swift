import SwiftUI

/// Remaining happenings as a close-packed constellation. Every item begins as
/// a circle, previews its exact Editorial canvas silhouette on the first tap,
/// and commits on the second.
struct HappeningShapeField: View {
    @Binding var presentation: HappeningFieldPresentationState
    let happenings: [Happening]
    let assignments: [String: HappeningEditorialAssignment]
    let contentTopInset: CGFloat?
    let dockCenterY: CGFloat?
    let highlightedID: String?
    let onPick: (Happening, HappeningEditorialAssignment, CGPoint) -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var labelPointSize: CGFloat = 14

    @State private var transition = HappeningSelectionTransitionState()
    @State private var previewedID: String?
    @State private var commitScale: CGFloat = 1
    @State private var commitOpacity: CGFloat = 1
    @State private var feedbackTick = 0
    @State private var commitTask: Task<Void, Never>?

    private static let commitDuration = 0.26
    private static let reflowDuration = 0.44

    var body: some View {
        GeometryReader { proxy in
            let layout = presentation.layout(
                in: proxy.size,
                safeInsets: proxy.safeAreaInsets,
                dynamicTypeSize: dynamicTypeSize,
                contentTopInset: contentTopInset,
                dockCenterY: dockCenterY
            )

            ZStack(alignment: .topLeading) {
                ForEach(
                    Array(presentation.presentedHappenings.enumerated()),
                    id: \.element.id
                ) { index, happening in
                    if index < layout.sources.count,
                       let assignment = assignments[happening.id] {
                        happeningButton(
                            happening,
                            assignment: assignment,
                            source: layout.sources[index]
                        )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sensoryFeedback(.selection, trigger: feedbackTick)
        .onChange(of: happenings) { _, next in
            receiveParentHappenings(next)
        }
        .onDisappear(perform: cancelTransition)
    }

    private func happeningButton(
        _ happening: Happening,
        assignment: HappeningEditorialAssignment,
        source: HappeningFieldLayout.Source
    ) -> some View {
        let isSelected = previewedID == happening.id
        let isCommitting = isSelected && transition.phase == .committing
        let side = source.radius * 2

        return Button {
            handleTap(happening, assignment: assignment, at: source.center)
        } label: {
            ZStack {
                Group {
                    if isSelected {
                        HappeningEditorialShapeMaterialView(
                            material: assignment.material,
                            shape: assignment.shape
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    } else {
                        HappeningEditorialCircleMaterialView(material: assignment.material)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .frame(width: side, height: side)
                .scaleEffect(isSelected ? 1.10 : 1)

                Text(happening.localizedTitle().replacingOccurrences(of: " ", with: "\n"))
                    .font(.system(size: labelPointSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.42), radius: 3, y: 1)
                    .multilineTextAlignment(.center)
                    .lineLimit(HappeningFieldLabelTypography.maximumLines(for: dynamicTypeSize))
                    .minimumScaleFactor(
                        HappeningFieldLabelTypography.minimumScaleFactor(for: dynamicTypeSize)
                    )
                    .frame(width: side * 0.80, height: side * 0.76)
            }
            .compositingGroup()
            .frame(width: side * 1.18, height: side * 1.18)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: max(44, side), height: max(44, side))
        .position(source.center)
        .scaleEffect(isCommitting ? commitScale : (highlightedID == happening.id ? 1.06 : 1))
        .opacity(isCommitting ? commitOpacity : 1)
        .disabled(transition.isInteractionLocked)
        .accessibilityLabel(happening.localizedTitle())
        .accessibilityValue(isSelected ? "Preview. Tap again to add" : "")
        .accessibilityHint(isSelected ? "Tap again to add to the canvas" : "Shows the canvas shape")
        .accessibilityIdentifier("happening_choice_\(happening.id)")
    }

    private func handleTap(
        _ happening: Happening,
        assignment: HappeningEditorialAssignment,
        at center: CGPoint
    ) {
        switch transition.handleTap(id: happening.id) {
        case .preview, .switchPreview:
            previewedID = happening.id
            feedbackTick += 1
        case .commit:
            previewedID = happening.id
            feedbackTick += 1
            beginCommit(happening, assignment: assignment, at: center)
        case .ignored:
            break
        }
    }

    private func beginCommit(
        _ happening: Happening,
        assignment: HappeningEditorialAssignment,
        at center: CGPoint
    ) {
        commitTask?.cancel()
        commitScale = 1
        commitOpacity = 1
        commitTask = Task { @MainActor in
            if reduceMotion {
                commitOpacity = 0
            } else {
                withAnimation(.easeInOut(duration: Self.commitDuration)) {
                    commitScale = 0.88
                    commitOpacity = 0
                }
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
            }

            let accepted = onPick(happening, assignment, center)
            guard transition.resolveCommit(id: happening.id, accepted: accepted) else {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                    commitScale = 1
                    commitOpacity = 1
                }
                commitTask = nil
                presentation.finishTransition()
                return
            }

            let remove = { _ = presentation.remove(id: happening.id) }
            if reduceMotion {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction, remove)
            } else {
                withAnimation(.spring(response: Self.reflowDuration, dampingFraction: 0.82)) {
                    remove()
                }
                try? await Task.sleep(for: .milliseconds(440))
                guard !Task.isCancelled else { return }
            }

            _ = transition.finishCommit(id: happening.id)
            previewedID = nil
            commitScale = 1
            commitOpacity = 1
            commitTask = nil
            presentation.finishTransition()
        }
    }

    private func receiveParentHappenings(_ next: [Happening]) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation.receiveParent(next, whileTransitioning: transition.phase != .idle)
        }
    }

    private func cancelTransition() {
        commitTask?.cancel()
        commitTask = nil
        transition.cancelSelection()
        previewedID = nil
        commitScale = 1
        commitOpacity = 1
        presentation.finishTransition()
    }
}

private struct HappeningEditorialCircleMaterialView: View {
    let material: DayObjectEditorialMaterialV1

    var body: some View {
        HappeningEditorialMaterialContent(material: material)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.19), lineWidth: 0.75) }
            .shadow(color: primaryColor.opacity(0.22), radius: 11, y: 5)
            .saturation(1.06)
    }

    private var primaryColor: Color {
        guard let color = material.colors.first else { return AppColors.brandAccent }
        return Color(.sRGB, red: Double(color.x), green: Double(color.y), blue: Double(color.z), opacity: 1)
    }
}

private struct HappeningEditorialShapeMaterialView: View {
    let material: DayObjectEditorialMaterialV1
    let shape: DayObjectShape

    var body: some View {
        let mask = HappeningEditorialShape(shape: shape, progress: 1)
        HappeningEditorialMaterialContent(material: material)
            .mask(mask)
            .overlay { mask.strokeBorder(.white.opacity(0.19), lineWidth: 0.75) }
            .shadow(color: primaryColor.opacity(0.22), radius: 11, y: 5)
            .saturation(1.06)
    }

    private var primaryColor: Color {
        guard let color = material.colors.first else { return AppColors.brandAccent }
        return Color(.sRGB, red: Double(color.x), green: Double(color.y), blue: Double(color.z), opacity: 1)
    }
}

private struct HappeningEditorialMaterialContent: View {
    let material: DayObjectEditorialMaterialV1

    private var colors: [Color] {
        let mapped = material.colors.map {
            Color(.sRGB, red: Double($0.x), green: Double($0.y), blue: Double($0.z), opacity: 1)
        }
        return mapped.isEmpty ? [AppColors.brandAccent] : mapped
    }

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)

            ZStack {
                LinearGradient(
                    colors: colors + [colors[0]],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ForEach(Array(material.fields.prefix(3).enumerated()), id: \.offset) { index, field in
                    RadialGradient(
                        colors: [
                            colors[(index + 1) % colors.count].opacity(field.opacity),
                            colors[index % colors.count].opacity(field.opacity * 0.52),
                            .clear,
                        ],
                        center: UnitPoint(x: field.focus.x, y: field.focus.y),
                        startRadius: 0,
                        endRadius: max(bounds.width, bounds.height) * field.radius
                    )
                    .blendMode(index.isMultiple(of: 2) ? .screen : .softLight)
                }

                Image("Grain")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.11)
                    .blendMode(.softLight)

                LinearGradient(
                    colors: [.white.opacity(0.26), .clear, .black.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .compositingGroup()
        }
    }
}

private struct HappeningEditorialShape: InsettableShape {
    let shape: DayObjectShape
    var progress: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func inset(by amount: CGFloat) -> HappeningEditorialShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let center = CGPoint(x: insetRect.midX, y: insetRect.midY)
        let base = min(insetRect.width, insetRect.height) / 2
        let steps = 160
        var path = Path()

        for index in 0...steps {
            let angle = CGFloat(index) / CGFloat(steps) * 2 * .pi
            let target = targetRadius(at: angle)
            let radius = base * (1 + (target - 1) * progress)
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func targetRadius(at angle: CGFloat) -> CGFloat {
        switch shape {
        case .sphere:
            return 1
        case .ellipse:
            return ellipseRadius(angle: angle, vertical: 0.78)
        case .lens:
            return ellipseRadius(angle: angle, vertical: 0.70) * (0.96 + 0.04 * cos(angle * 2))
        case .softBlob:
            return 0.93 + 0.045 * sin(angle * 3 + 0.6) + 0.025 * cos(angle * 2 - 0.3)
        case .softStar:
            return 0.88 + 0.12 * cos(angle * 5)
        case .roundedPolygon:
            return 0.93 + 0.07 * cos(angle * 6)
        case .roundedSquare:
            let c = abs(cos(angle))
            let s = abs(sin(angle))
            return 0.84 / pow(pow(c, 4) + pow(s, 4), 0.25)
        }
    }

    private func ellipseRadius(angle: CGFloat, vertical: CGFloat) -> CGFloat {
        1 / sqrt(pow(cos(angle), 2) + pow(sin(angle) / vertical, 2))
    }
}
