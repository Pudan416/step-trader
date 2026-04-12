#if DEBUG
import SwiftUI

struct CoachMarkOverlay: View {
    @ObservedObject var manager: CoachMarkManager
    let anchors: [CoachMarkAnchor]

    @State private var appearAnimation: Bool = false

    private var currentAnchor: CoachMarkAnchor? {
        guard let step = manager.currentStep else { return nil }
        return anchors.first { $0.step == step }
    }

    var body: some View {
        if manager.isActive, let step = manager.currentStep,
           !step.isSheetStep {
            ZStack {
                if step.requiresSpotlight {
                    spotlightView(step: step)
                } else {
                    cardView(step: step)
                }
            }
            .transition(.opacity)
            .onAppear { withAnimation(.easeOut(duration: 0.3)) { appearAnimation = true } }
            .onChange(of: manager.currentStep) { _, _ in
                appearAnimation = false
                withAnimation(.easeOut(duration: 0.3)) { appearAnimation = true }
            }
        }
    }

    // MARK: - Spotlight Mode

    @ViewBuilder
    private func spotlightView(step: CoachMarkStep) -> some View {
        let cutoutRect = currentAnchor?.frame

        GeometryReader { geo in
            let fullSize = geo.size
            ZStack {
                spotlightBackground(cutoutRect: cutoutRect, in: fullSize)
                tooltipCard(step: step, cutoutRect: cutoutRect, containerSize: fullSize)
            }
        }
        .ignoresSafeArea()
    }

    private func spotlightBackground(cutoutRect: CGRect?, in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let fullRect = CGRect(origin: .zero, size: canvasSize)
            context.fill(Path(fullRect), with: .color(.black.opacity(0.6)))

            if let cutoutRect {
                let expanded = cutoutRect.insetBy(dx: -12, dy: -12)
                let cutout = Path(roundedRect: expanded, cornerRadius: 16)
                context.blendMode = .destinationOut
                context.fill(cutout, with: .color(.white))
            }
        }
        .compositingGroup()
        .allowsHitTesting(!step_needs_passthrough(manager.currentStep))
    }

    private func step_needs_passthrough(_ step: CoachMarkStep?) -> Bool {
        guard let step else { return false }
        switch step {
        case .expandChevron, .tapPlusButton, .tapMind,
             .tapFeedsTab, .tapUnlockPill:
            return true
        default:
            return false
        }
    }

    // MARK: - Card Mode (no spotlight)

    @ViewBuilder
    private func cardView(step: CoachMarkStep) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 20) {
                Text(step.tooltip)
                    .font(.systemSerif(17, weight: .light, relativeTo: .body))
                    .italic()
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                HStack(spacing: 16) {
                    Button { manager.skipAll() } label: {
                        Text("skip all")
                            .font(.systemSerif(15, weight: .light, relativeTo: .subheadline))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Spacer()

                    if step.hasNextButton {
                        Button { manager.advance() } label: {
                            Text(step == .allSet ? "done" : "next")
                                .font(.systemSerif(15, weight: .semibold, relativeTo: .subheadline))
                                .foregroundColor(.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(AppColors.brandAccent)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground).opacity(0.12))
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            )
            .scaleEffect(appearAnimation ? 1 : 0.9)
            .opacity(appearAnimation ? 1 : 0)
        }
    }

    // MARK: - Tooltip Card (positioned near spotlight cutout)

    private func tooltipCardContent(step: CoachMarkStep) -> some View {
        VStack(spacing: 14) {
            Text(step.tooltip)
                .font(.systemSerif(16, weight: .light, relativeTo: .body))
                .italic()
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button { manager.skipAll() } label: {
                    Text("skip all")
                        .font(.systemSerif(14, weight: .light, relativeTo: .caption))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                if step.hasNextButton {
                    Button { manager.advance() } label: {
                        Text("next")
                            .font(.systemSerif(15, weight: .semibold, relativeTo: .subheadline))
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(AppColors.brandAccent)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground).opacity(0.1))
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
        )
        .scaleEffect(appearAnimation ? 1 : 0.95)
        .opacity(appearAnimation ? 1 : 0)
    }

    @ViewBuilder
    private func tooltipCard(step: CoachMarkStep, cutoutRect: CGRect?, containerSize: CGSize) -> some View {
        if let cutoutRect {
            let placement = bestPlacement(cutout: cutoutRect, container: containerSize)
            placedTooltip(step: step, placement: placement, cutout: cutoutRect, containerSize: containerSize)
        } else {
            tooltipCardContent(step: step)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func placedTooltip(step: CoachMarkStep, placement: TooltipPlacement, cutout: CGRect, containerSize: CGSize) -> some View {
        let expanded = cutout.insetBy(dx: -12, dy: -12)
        switch placement {
        case .above:
            VStack {
                Spacer().allowsHitTesting(false)
                tooltipCardContent(step: step)
                    .padding(.horizontal, 24)
                Spacer()
                    .frame(height: max(16, containerSize.height - expanded.minY + 16))
                    .allowsHitTesting(false)
            }
        case .below:
            VStack {
                Spacer()
                    .frame(height: max(16, expanded.maxY + 16))
                    .allowsHitTesting(false)
                tooltipCardContent(step: step)
                    .padding(.horizontal, 24)
                Spacer().allowsHitTesting(false)
            }
        case .center:
            tooltipCardContent(step: step)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Tooltip Placement Logic

private enum TooltipPlacement {
    case above, below, center
}

private func bestPlacement(cutout: CGRect, container: CGSize, margin: CGFloat = 16) -> TooltipPlacement {
    let expanded = cutout.insetBy(dx: -12, dy: -12)
    let spaceAbove = expanded.minY - margin
    let spaceBelow = container.height - expanded.maxY - margin
    let estimatedTooltipHeight: CGFloat = 120

    if spaceAbove >= estimatedTooltipHeight && spaceAbove >= spaceBelow {
        return .above
    } else if spaceBelow >= estimatedTooltipHeight {
        return .below
    } else if spaceAbove > spaceBelow {
        return .above
    } else {
        return .below
    }
}

// MARK: - Sheet Overlay (used inside CategoryDetailView sheet)

struct CoachMarkSheetOverlay: View {
    @ObservedObject var manager: CoachMarkManager
    let anchors: [CoachMarkAnchor]

    @State private var appearAnimation: Bool = false

    private var currentAnchor: CoachMarkAnchor? {
        guard let step = manager.currentStep else { return nil }
        return anchors.first { $0.step == step }
    }

    var body: some View {
        if manager.isActive, let step = manager.currentStep,
           step.isSheetStep {
            GeometryReader { geo in
                let geoGlobal = geo.frame(in: .global)
                let localRect: CGRect? = currentAnchor.map { a in
                    CGRect(
                        x: a.frame.minX - geoGlobal.minX,
                        y: a.frame.minY - geoGlobal.minY,
                        width: a.frame.width,
                        height: a.frame.height
                    )
                }

                ZStack {
                    sheetSpotlight(cutoutRect: localRect, passthrough: sheetNeedsPassthrough(step))
                    sheetTooltip(step: step, cutoutRect: localRect, containerSize: geo.size)
                }
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .onAppear { withAnimation(.easeOut(duration: 0.3)) { appearAnimation = true } }
            .onChange(of: manager.currentStep) { _, _ in
                appearAnimation = false
                withAnimation(.easeOut(duration: 0.3)) { appearAnimation = true }
            }
        }
    }

    private func sheetNeedsPassthrough(_ step: CoachMarkStep) -> Bool {
        switch step {
        case .spotlightFocusing, .spotlightReading, .tapAddToCanvas:
            return true
        default:
            return false
        }
    }

    private func sheetSpotlight(cutoutRect: CGRect?, passthrough: Bool) -> some View {
        Canvas { context, canvasSize in
            let fullRect = CGRect(origin: .zero, size: canvasSize)
            context.fill(Path(fullRect), with: .color(.black.opacity(0.5)))

            if let cutoutRect {
                let expanded = cutoutRect.insetBy(dx: -8, dy: -8)
                let cutout = Path(roundedRect: expanded, cornerRadius: 14)
                context.blendMode = .destinationOut
                context.fill(cutout, with: .color(.white))
            }
        }
        .compositingGroup()
        .allowsHitTesting(!passthrough)
    }

    private func sheetTooltipContent(step: CoachMarkStep) -> some View {
        VStack(spacing: 12) {
            Text(step.tooltip)
                .font(.systemSerif(15, weight: .light, relativeTo: .body))
                .italic()
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Button { manager.skipAll() } label: {
                Text("skip all")
                    .font(.systemSerif(13, weight: .light, relativeTo: .caption))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(18)
        .frame(maxWidth: 300)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground).opacity(0.1))
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
        )
        .scaleEffect(appearAnimation ? 1 : 0.95)
        .opacity(appearAnimation ? 1 : 0)
    }

    @ViewBuilder
    private func sheetTooltip(step: CoachMarkStep, cutoutRect: CGRect?, containerSize: CGSize) -> some View {
        let content = sheetTooltipContent(step: step)

        if let cutoutRect {
            let placement = bestPlacement(cutout: cutoutRect, container: containerSize)
            let expanded = cutoutRect.insetBy(dx: -8, dy: -8)

            switch placement {
            case .above:
                VStack {
                    Spacer().allowsHitTesting(false)
                    content.padding(.horizontal, 20)
                    Spacer()
                        .frame(height: max(12, containerSize.height - expanded.minY + 12))
                        .allowsHitTesting(false)
                }
            case .below:
                VStack {
                    Spacer()
                        .frame(height: max(12, expanded.maxY + 12))
                        .allowsHitTesting(false)
                    content.padding(.horizontal, 20)
                    Spacer().allowsHitTesting(false)
                }
            case .center:
                content
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            content
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
