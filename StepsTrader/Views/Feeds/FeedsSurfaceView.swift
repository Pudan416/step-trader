import SwiftUI

/// The Feeds tab's contextual surface — one 387×443pt region above the app dock
/// that shows exactly one of three states:
///
/// 1. **idle** — nothing selected. Only the blurred canvas.
/// 2. **offeringWindows** — a locked group is selected: the group's enabled
///    window options.
/// 3. **running** — an unlocked group is selected: the depleting timer.
///
/// A corner menu (Settings / Delete) is shown whenever a group is selected —
/// in both non-idle states, not just state 2 — because it is the surface's
/// only management affordance: the dock tile itself has no context menu.
///
/// The state is derived fresh on every render from `selectedGroup` and
/// `model.unspentUsageBudgetMatchingShield(for:)` rather than stored. The usage budget is
/// written from outside this view — by the `DeviceActivityMonitor` extension —
/// so a cached copy of "which state am I in" would drift from it. Only the
/// timer's own stepping state (`UnlockTimerModel`) lives in `@State`, because
/// that type is explicitly designed to be advanced by discrete observations,
/// not recomputed from scratch each render.
struct FeedsSurfaceView: View {
    @ObservedObject var model: AppModel
    let selectedGroup: String?
    let onSettings: (String) -> Void
    let onDelete: (String) -> Void

    static let size = CGSize(width: 387, height: 443)
    private static let cornerRadius: CGFloat = 28
    private static let ringDiameter: CGFloat = 176
    private static let ringLineWidth: CGFloat = 10

    /// The three states, kept in one enum so the transitions are visible in
    /// one place. Carrying the resolved `TicketGroup` in the non-idle cases
    /// means every branch below is self-contained — no second lookup needed.
    private enum SurfaceState {
        case idle
        case offeringWindows(TicketGroup)
        case running(TicketGroup)
    }

    // Background: one static, blurred frame of today's canvas. This is
    // decorative chrome, not the live gallery, so it is loaded once from disk
    // via the same `CanvasStorageService` singleton the Gallery tab already
    // uses — no network fetch, no day-boundary tracking, no writes.
    @State private var dayCanvas = DayCanvas(dayKey: AppModel.dayKey(for: .now))
    @State private var hasLoadedCanvas = false
    @State private var fixedTime = Date.now

    // Timer bookkeeping. `UnlockTimerModel` owns the stepping/clamping logic;
    // this view's job is only to feed it fresh unspent-budget reads.
    @State private var timerModel = UnlockTimerModel(initialMinutes: 0)
    @State private var timerState: UnlockTimerModel.State?
    @State private var trackedGroupId: String?
    @State private var trackedInitialMinutes = 0

    @State private var isPurchasing = false

    private var selectedTicketGroup: TicketGroup? {
        guard let selectedGroup else { return nil }
        return model.ticketGroups.first(where: { $0.id == selectedGroup })
    }

    var body: some View {
        // Both branches below — which state to show, and (for state 3) what
        // number to show — come from this one unspent-budget read.
        // Reading it twice per render risked the two disagreeing for a frame
        // (see `resolvedTimerState`); reading it once and threading it
        // through makes that impossible.
        let group = selectedTicketGroup
        let remaining = group.map { model.unspentUsageBudgetMatchingShield(for: $0.id) } ?? 0
        let state: SurfaceState = {
            guard let group else { return .idle }
            return remaining > 0 ? .running(group) : .offeringWindows(group)
        }()

        return ZStack {
            background

            switch state {
            case .idle:
                EmptyView()
            case .offeringWindows(let group):
                windowOptions(for: group)
            case .running(let group):
                timerDisplay(for: group, remaining: remaining)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            // Independent of state (besides idle): a running window must not
            // strand the group without a path to Settings/Delete for up to
            // an hour, since the dock tile itself offers no context menu.
            if let group {
                cornerMenu(for: group)
                    .padding(16)
            }
        }
        .overlay(alignment: .bottomLeading) {
            title
                .padding(.leading, 13)
                .padding(.bottom, 22)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        )
        .onAppear {
            loadCanvasIfNeeded()
            refreshTimer()
        }
        .task(id: selectedGroup) {
            refreshTimer()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                refreshTimer()
            }
        }
    }

    // MARK: - Background

    /// Reuses `GenerativeCanvasView` rather than a second renderer. `fixedTime`
    /// freezes it to one frame — under `.blur` the continuous animation the
    /// live view uses would be invisible motion, purely burning battery — and
    /// `showLabelsOnCanvas: false` drops labels that would just be noise under
    /// the blur. The scrim on top keeps window-option text and timer digits
    /// legible regardless of what the canvas underneath looks like today.
    private var background: some View {
        ZStack {
            GenerativeCanvasView(
                elements: dayCanvas.elements,
                sleepPoints: dayCanvas.sleepPoints,
                stepsPoints: dayCanvas.stepsPoints,
                sleepColor: Color(hex: dayCanvas.sleepColorHex),
                stepsColor: Color(hex: dayCanvas.stepsColorHex),
                decayNorm: dayCanvas.decayNorm,
                backgroundColor: AppColors.Night.background,
                showLabelsOnCanvas: false,
                showsOutlinedLabels: false,
                hasStepsData: dayCanvas.resolvedHasStepsData,
                hasSleepData: dayCanvas.resolvedHasSleepData,
                fixedTime: fixedTime
            )
            .frame(width: Self.size.width, height: Self.size.height)
            .blur(radius: 18)

            // Uniform dimming so content reads anywhere on the card, plus an
            // extra gradient toward the bottom where "My Feeds" sits.
            Color.black.opacity(0.32)
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - "My Feeds" title (always visible, overlaid on the surface)

    private var title: some View {
        Text(String(localized: "My Feeds", comment: "Feeds surface – overlay title"))
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
    }

    // MARK: - Corner menu (whenever a group is selected, states 2 and 3)

    private func cornerMenu(for group: TicketGroup) -> some View {
        Menu {
            Button {
                onSettings(group.id)
            } label: {
                Label(String(localized: "Settings", comment: "Feeds surface – corner menu"), systemImage: "gearshape")
            }
            Button(role: .destructive) {
                onDelete(group.id)
            } label: {
                Label(String(localized: "Delete", comment: "Feeds surface – corner menu"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(0.16)))
        }
        .accessibilityLabel(String(localized: "Feed options", comment: "Feeds surface – corner menu VoiceOver label"))
    }

    // MARK: - State 2: window options

    private func windowOptions(for group: TicketGroup) -> some View {
        // Only the windows the user actually left enabled in Settings — every
        // other purchase surface (PayGateView) filters the
        // same way, and `enabledIntervals` is never empty (TicketGroup's
        // decode path guarantees that), so there is no empty-list case here.
        let windows = AccessWindow.allCases.filter(group.enabledIntervals.contains)
        return VStack(spacing: 12) {
            ForEach(windows, id: \.self) { window in
                windowRow(window, group: group)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 28)
    }

    private func windowRow(_ window: AccessWindow, group: TicketGroup) -> some View {
        let cost = group.cost(for: window)
        let canAfford = model.totalStepsBalance >= cost
        let isDisabled = !canAfford || isPurchasing

        return Button {
            purchase(window: window, group: group, cost: cost)
        } label: {
            HStack {
                Text(window.displayName)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(cost)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.4 : 1.0)
        .disabled(isDisabled)
        .accessibilityLabel(String(localized: "\(window.displayName), \(cost) colors", comment: "Feeds surface – window option VoiceOver label"))
        .accessibilityHint(
            canAfford
                ? String(localized: "Double tap to unlock", comment: "Feeds surface – window option VoiceOver hint")
                : String(localized: "Not enough colors", comment: "Feeds surface – window option VoiceOver hint")
        )
    }

    private func purchase(window: AccessWindow, group: TicketGroup, cost: Int) {
        guard !isPurchasing else { return }
        isPurchasing = true
        Task {
            // Unchanged: handles payment, monitoring, and refund-on-failure
            // itself, and sets `model.payGateError` on failure (surfaced by
            // the app-wide alert already wired to it in StepsTraderApp).
            await model.handlePayGatePaymentForGroup(groupId: group.id, window: window, costOverride: cost)
            // The budget UserDefaults write already happened inside the call
            // above; refresh immediately so the surface flips to state 3
            // without waiting for the next poll tick.
            refreshTimer()
            isPurchasing = false
        }
    }

    // MARK: - State 3: timer

    private func timerDisplay(for group: TicketGroup, remaining: Int) -> some View {
        let display = resolvedTimerState(for: group, remaining: remaining)
        return ZStack {
            depletionRing(fraction: display.fraction)
            Text(display.digits)
                .font(.system(size: 44, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.bottom, 24)
    }

    /// A ring rather than a bar: it reads at a glance as time draining from a
    /// full clock face, and its round footprint centers naturally behind the
    /// digits instead of competing with them for width. There is no
    /// `.animation` on the trim — `UnlockTimerModel.State.fraction` already
    /// only changes on whole-minute tick boundaries, and this view must not
    /// smooth that into a sweep. A tick lands as a hard cut, matching the
    /// spec: never interpolate, never run backwards.
    private func depletionRing(fraction: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: Self.ringLineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(
                    AppColors.brandAccent,
                    style: StrokeStyle(lineWidth: Self.ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(nil, value: fraction)
        }
        .frame(width: Self.ringDiameter, height: Self.ringDiameter)
    }

    /// What state 3 shows for `group` at `remaining` — the exact value that
    /// just decided the surface is in the running branch (see `body`).
    ///
    /// When the persisted `timerModel` is already tracking this group
    /// (`trackedGroupId == group.id`), its stepped state is authoritative:
    /// that is what enforces "never runs backwards" across an ongoing
    /// session's tick jitter. Otherwise — the selection just switched to this
    /// group, or its budget just went from zero to non-zero from outside this
    /// view (e.g. a widget unlock) and `refreshTimer()` hasn't run again yet
    /// — a throwaway local model seeded from this same `remaining` read
    /// stands in for this one render instead of the *previous* group's
    /// leftover `timerState`. It has no history to clamp against, which is
    /// correct: from this group's perspective this is its first observation,
    /// identical to what the persisted model will show once `refreshTimer()`
    /// catches up.
    private func resolvedTimerState(for group: TicketGroup, remaining: Int) -> UnlockTimerModel.State {
        if trackedGroupId == group.id, let timerState {
            return timerState
        }
        let storedInitial = UserDefaults.stepsTrader().integer(forKey: SharedKeys.usageBudgetInitialKey(group.id))
        var bridge = UnlockTimerModel(initialMinutes: max(storedInitial, remaining, 1))
        return bridge.observe(remainingMinutes: remaining)
    }

    // MARK: - Data loading & refresh

    private func loadCanvasIfNeeded() {
        guard !hasLoadedCanvas else { return }
        hasLoadedCanvas = true
        let dayKey = AppModel.dayKey(for: .now)
        if let loaded = CanvasStorageService.shared.loadCanvas(for: dayKey) {
            dayCanvas = loaded
        }
    }

    /// Advances `timerModel` from a fresh unspent-budget reading.
    /// Resets the model (the one legitimate way remaining time may increase)
    /// when the selected group changes or when its stored initial window size
    /// grows — the latter covers buying more time while already unlocked.
    private func refreshTimer() {
        guard let group = selectedTicketGroup else {
            timerState = nil
            trackedGroupId = nil
            return
        }
        let remaining = model.unspentUsageBudgetMatchingShield(for: group.id)
        guard remaining > 0 else {
            timerState = nil
            trackedGroupId = nil
            return
        }

        let defaults = UserDefaults.stepsTrader()
        let storedInitial = defaults.integer(forKey: SharedKeys.usageBudgetInitialKey(group.id))
        let effectiveInitial = max(storedInitial, remaining, 1)

        if trackedGroupId != group.id || effectiveInitial > trackedInitialMinutes {
            timerModel.reset(initialMinutes: effectiveInitial)
            trackedGroupId = group.id
            trackedInitialMinutes = effectiveInitial
        }

        timerState = timerModel.observe(remainingMinutes: remaining)
    }
}
