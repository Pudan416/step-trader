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
/// The state is derived fresh on every render from `selectedGroup` and the
/// `unspentMinutes` the page polls, rather than stored. The usage budget is
/// written from outside this view — by the `DeviceActivityMonitor` extension —
/// so a cached copy of "which state am I in" would drift from it. Only the
/// timer's own stepping state (`UnlockTimerModel`) lives in `@State`, because
/// that type is explicitly designed to be advanced by discrete observations,
/// not recomputed from scratch each render.
struct FeedsSurfaceView: View {
    @ObservedObject var model: AppModel
    let selectedGroup: String?
    /// Unspent minutes on `selectedGroup`'s window; 0 when nothing is selected
    /// or the window is closed. `AppsPageSimplified` owns the poll for the
    /// whole page — this view and the dock tiles must show one number, and two
    /// unsynchronised 15s loops could not guarantee that.
    let unspentMinutes: Int
    /// Re-poll now rather than at the page's next tick. Called after a
    /// purchase, so the surface and the tile flip to the running state in the
    /// same update.
    let onBudgetChanged: () -> Void
    let onSettings: (String) -> Void
    let onDelete: (String) -> Void

    /// The surface as drawn in the design, on a 393pt-wide phone. It is a
    /// *ceiling and a ratio*, not a fixed size: hard-coding 387×443 overflowed
    /// a 375pt-wide SE 3 / 13 mini horizontally, in a page that does not
    /// scroll, and overran the height there too once the header, dock and
    /// paddings were counted. The surface now fits itself into whatever the
    /// page offers, keeping the design's proportions, and only reaches full
    /// size where there is room.
    static let designSize = CGSize(width: 387, height: 443)
    static var designAspectRatio: CGFloat { designSize.width / designSize.height }
    private static let cornerRadius: CGFloat = 28
    private static let ringLineWidth: CGFloat = 10

    /// The ring is 176pt across at the design size; scale with the surface so
    /// it keeps the same share of the card on a narrower phone.
    private static let ringDiameterRatio: CGFloat = 176 / 387

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
        // number to show — come from the one value the page polled. Reading
        // the budget again here risked disagreeing with the tile for a frame
        // (see `resolvedTimerState`); taking it as input makes that impossible.
        let group = selectedTicketGroup
        let remaining = group == nil ? 0 : unspentMinutes
        let state: SurfaceState = {
            guard let group else { return .idle }
            return remaining > 0 ? .running(group) : .offeringWindows(group)
        }()

        // GeometryReader inside the aspect-ratio frame below, not around it:
        // it reports the size the page actually granted, which the background
        // canvas and the ring need in points.
        return GeometryReader { geo in
            ZStack {
                background(size: geo.size)

                switch state {
                case .idle:
                    EmptyView()
                case .offeringWindows(let group):
                    windowOptions(for: group)
                case .running(let group):
                    timerDisplay(for: group, remaining: remaining, width: geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(Self.designAspectRatio, contentMode: .fit)
        .frame(maxWidth: Self.designSize.width, maxHeight: Self.designSize.height)
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
            refreshTimer(remaining: remaining)
        }
        .onChange(of: selectedGroup) { _, _ in
            refreshTimer(remaining: unspentMinutes)
        }
        .onChange(of: unspentMinutes) { _, newValue in
            refreshTimer(remaining: newValue)
        }
    }

    // MARK: - Background

    /// Reuses `GenerativeCanvasView` rather than a second renderer. `fixedTime`
    /// freezes it to one frame — under `.blur` the continuous animation the
    /// live view uses would be invisible motion, purely burning battery — and
    /// `showLabelsOnCanvas: false` drops labels that would just be noise under
    /// the blur. The scrim on top keeps window-option text and timer digits
    /// legible regardless of what the canvas underneath looks like today.
    private func background(size: CGSize) -> some View {
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
            .frame(width: size.width, height: size.height)
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
            // above. Ask the page to re-poll so the surface *and* the tile
            // flip to the running state now, not at the next tick.
            onBudgetChanged()
            isPurchasing = false
        }
    }

    // MARK: - State 3: timer

    private func timerDisplay(for group: TicketGroup, remaining: Int, width: CGFloat) -> some View {
        let display = resolvedTimerState(for: group, remaining: remaining)
        return ZStack {
            depletionRing(fraction: display.fraction, diameter: width * Self.ringDiameterRatio)
            Text(display.digits)
                .font(.system(size: 44, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
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
    private func depletionRing(fraction: Double, diameter: CGFloat) -> some View {
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
        .frame(width: diameter, height: diameter)
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

    /// Advances `timerModel` from the page's latest unspent-budget reading.
    /// Resets the model (the one legitimate way remaining time may increase)
    /// when the selected group changes or when its stored initial window size
    /// grows — the latter covers buying more time while already unlocked.
    ///
    /// Takes `remaining` rather than reading the prop so it can be called from
    /// an `onChange` handler with the value that just arrived.
    private func refreshTimer(remaining: Int) {
        guard let group = selectedTicketGroup else {
            timerState = nil
            trackedGroupId = nil
            return
        }
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
