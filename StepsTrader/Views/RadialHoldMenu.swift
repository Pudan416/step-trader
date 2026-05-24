import SwiftUI

// MARK: - Radial Hold Menu (tap to fan, or long-press+drag)

/// Tap shows 3 category buttons (Body / Mind / Heart) in a fan arc, plus a
/// separate ✦ Moment node to the right for logging ephemeral life events.
/// Long-press + drag also works: nodes appear and you can drag to select.
struct RadialHoldMenu: View {
    var labelColor: Color = .white
    let onCategorySelected: (EnergyCategory) -> Void
    /// Called when the ✦ Moment node is tapped (Pro-only feature).
    var onMomentSelected: (() -> Void)? = nil
    /// Mirrors the fan open/close state into the parent so sibling views
    /// (e.g. the share button) react in the same SwiftUI update cycle —
    /// no callback delay, no one-frame overlap. The parent always owns
    /// this state; use `.constant(false)` in previews/standalone usage.
    @Binding var isFanOpen: Bool
    var onFanOpened: (() -> Void)? = nil

    @State private var isHolding = false
    @State private var hoveredCategory: EnergyCategory? = nil
    @State private var hoveredMoment = false
    @State private var touchDownTime: Date? = nil
    @State private var holdActivated = false
    @State private var holdActivationTask: Task<Void, Never>?

    // Haptic triggers for declarative `.sensoryFeedback`. Bump the counter to
    // fire the corresponding impact — no UIKit cold-start latency, no
    // `prepare()` book-keeping. Two separate triggers keep light/medium
    // independent in the same view.
    @State private var lightHapticTick = 0
    @State private var mediumHapticTick = 0

    private let nodes: [(category: EnergyCategory, angle: Double)] = [
        (.body,  135),  // upper-left
        (.mind,   90),  // straight up
        (.heart,  45),  // upper-right
    ]

    /// Moment node sits to the right, outside the main fan arc.
    private let momentAngle: Double = 0       // 0° = straight right
    private let momentRadius: CGFloat = 90    // slightly further than the 3 main nodes (80pt)

    private let fanRadius: CGFloat = 80
    private let activationDistance: CGFloat = 55

    private func nodeOffset(angleDeg: Double, radius: CGFloat? = nil) -> CGSize {
        let r = radius ?? fanRadius
        let rad = angleDeg * .pi / 180
        return CGSize(width: cos(rad) * r, height: -sin(rad) * r)
    }

    var body: some View {
        // Wrap all glass children in a GlassEffectContainer. Without this, iOS 26
        // merges the interactive glass surfaces of the + button and the three
        // category nodes (Body/Mind/Heart) and routes every tap to the first one
        // — silently breaking the fan node taps.
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 0) { menuStack }
            } else {
                menuStack
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lightHapticTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: mediumHapticTick)
    }

    @ViewBuilder
    private var menuStack: some View {
        ZStack {
            // Category nodes — visible in either fan-tap mode or hold-drag mode
            if isFanOpen || isHolding {
                ForEach(nodes, id: \.category) { node in
                    RadialCategoryNode(
                        category: node.category,
                        labelColor: labelColor,
                        isHovered: hoveredCategory == node.category,
                        offset: nodeOffset(angleDeg: node.angle),
                        onTap: { selectCategory(node.category) }
                    )
                }
                .transition(.scale.combined(with: .opacity))

                // Moment node — separate from the fan arc, appears to the right
                RadialMomentNode(
                    labelColor: labelColor,
                    isHovered: hoveredMoment,
                    offset: nodeOffset(angleDeg: momentAngle, radius: momentRadius),
                    onTap: selectMoment
                )
                .transition(
                    .scale(scale: 0.6)
                    .combined(with: .opacity)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.05))
                )
            }

            // + button with liquid dots
            plusButton
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFanOpen || isHolding)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hoveredCategory)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hoveredMoment)
    }

    // MARK: - Plus Button

    private let holdThreshold: TimeInterval = 0.3

    private var plusButton: some View {
        let unifiedDrag = DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if touchDownTime == nil {
                    touchDownTime = Date.now
                    holdActivated = false
                    scheduleHoldActivation()
                }
                if holdActivated {
                    updateHoveredCategory(from: value.translation)
                }
            }
            .onEnded { _ in
                holdActivationTask?.cancel()
                let wasTap = !holdActivated
                if wasTap {
                    toggleFan()
                } else {
                    if hoveredMoment {
                        mediumHapticTick &+= 1
                        onMomentSelected?()
                        isHolding = false
                        hoveredMoment = false
                    } else if let category = hoveredCategory {
                        mediumHapticTick &+= 1
                        onCategorySelected(category)
                    }
                    isHolding = false
                    hoveredCategory = nil
                    hoveredMoment = false
                }
                touchDownTime = nil
                holdActivated = false
            }

        let isActive = isFanOpen || isHolding

        return Image(systemName: isActive ? "xmark" : "plus")
            .font(.system(size: 22, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(labelColor.opacity(isActive ? 0.85 : 1.0))
            .rotationEffect(.degrees(isFanOpen ? 45 : 0))
            .frame(width: 56, height: 56)
            .liquidGlassControl(in: Circle())
            .frame(width: 72, height: 72)
            .contentShape(Circle())
            .accessibilityIdentifier("radial_plus_button")
            .accessibilityLabel(isFanOpen
                ? String(localized: "Close menu", comment: "RadialMenu – VoiceOver label")
                : String(localized: "Add card", comment: "RadialMenu – VoiceOver label"))
            .accessibilityHint(String(localized: "Hold and drag to quickly select a category, or tap to open the menu", comment: "RadialMenu – VoiceOver hint"))
            .accessibilityAddTraits(.isButton)
            .simultaneousGesture(unifiedDrag)
    }

    private func scheduleHoldActivation() {
        holdActivationTask?.cancel()
        holdActivationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(holdThreshold))
            guard !Task.isCancelled, touchDownTime != nil else { return }
            holdActivated = true
            isFanOpen = false
            isHolding = true
            mediumHapticTick &+= 1
        }
    }

    private func toggleFan() {
        lightHapticTick &+= 1
        if isFanOpen {
            isFanOpen = false
        } else {
            isFanOpen = true
            onFanOpened?()
        }
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    // MARK: - Selection actions (used by subviews)

    private func selectCategory(_ category: EnergyCategory) {
        guard isFanOpen else { return }
        mediumHapticTick &+= 1
        onCategorySelected(category)
        isFanOpen = false
    }

    private func selectMoment() {
        guard isFanOpen else { return }
        mediumHapticTick &+= 1
        onMomentSelected?()
        isFanOpen = false
    }

    // MARK: - Hit Testing (drag mode)

    private func updateHoveredCategory(from translation: CGSize) {
        // Check moment node first
        let momentOffset = nodeOffset(angleDeg: momentAngle, radius: momentRadius)
        let mdx = translation.width - momentOffset.width
        let mdy = translation.height - momentOffset.height
        let momentDist = sqrt(mdx * mdx + mdy * mdy)
        let newHoveredMoment = momentDist < activationDistance

        // Check category nodes
        var closest: EnergyCategory? = nil
        var closestDist: CGFloat = .infinity

        if !newHoveredMoment {
            for node in nodes {
                let off = nodeOffset(angleDeg: node.angle)
                let dx = translation.width - off.width
                let dy = translation.height - off.height
                let dist = sqrt(dx * dx + dy * dy)
                if dist < activationDistance && dist < closestDist {
                    closest = node.category
                    closestDist = dist
                }
            }
        }

        if newHoveredMoment != hoveredMoment {
            if newHoveredMoment { lightHapticTick &+= 1 }
            hoveredMoment = newHoveredMoment
        }
        if closest != hoveredCategory {
            if closest != nil { lightHapticTick &+= 1 }
            hoveredCategory = closest
        }
    }
}

// MARK: - Radial Category Node

private struct RadialCategoryNode: View {
    let category: EnergyCategory
    let labelColor: Color
    let isHovered: Bool
    let offset: CGSize
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: category.iconName)
                    .font(.system(size: isHovered ? 20 : 16, weight: .medium))
                    .foregroundStyle(labelColor.opacity(isHovered ? 1.0 : 0.85))
                    .frame(width: 44, height: 44)
                    .liquidGlassControl(in: Circle())
                    .scaleEffect(isHovered ? 1.15 : 1.0)

                Text(category.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(labelColor.opacity(isHovered ? 1.0 : 0.9))
                    .contrastingOnGlass()
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("radial_\(category.rawValue)")
        .accessibilityLabel(Text("\(category.displayName) category", comment: "RadialMenu – category VoiceOver label"))
        .accessibilityAddTraits(.isButton)
        #if DEBUG
        .modifier(MindNodeAnchor(category: category))
        #endif
        .offset(offset)
    }
}

// MARK: - Radial Moment Node

private struct RadialMomentNode: View {
    let labelColor: Color
    let isHovered: Bool
    let offset: CGSize
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: isHovered ? 18 : 14, weight: .medium))
                    .foregroundStyle(labelColor.opacity(isHovered ? 1.0 : 0.75))
                    .frame(width: 38, height: 38)
                    .liquidGlassControl(in: Circle())
                    .scaleEffect(isHovered ? 1.15 : 1.0)

                Text(String(localized: "Moment", comment: "RadialMenu – moment node label"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(labelColor.opacity(isHovered ? 1.0 : 0.75))
                    .contrastingOnGlass()
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("radial_moment")
        .accessibilityLabel(String(localized: "Log a moment", comment: "RadialMenu – moment VoiceOver label"))
        .accessibilityHint(String(localized: "Log a one-time life event for today", comment: "RadialMenu – moment VoiceOver hint"))
        .accessibilityAddTraits(.isButton)
        .offset(offset)
    }
}

#if DEBUG
private struct MindNodeAnchor: ViewModifier {
    let category: EnergyCategory
    func body(content: Content) -> some View {
        if category == .mind {
            content.coachMarkAnchor(.tapMind)
        } else {
            content
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    @Previewable @State var fanOpen = false
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            RadialHoldMenu(
                labelColor: .white,
                onCategorySelected: { category in
                    AppLogger.ui.debug("Selected: \(category.rawValue)")
                },
                onMomentSelected: {
                    AppLogger.ui.debug("Moment selected")
                },
                isFanOpen: $fanOpen
            )
            .padding(.bottom, 80)
        }
    }
}
