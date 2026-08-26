import SwiftUI
import UIKit

// MARK: - MeView support types
//
// Extracted from `MeView.swift` (§9.2): the day-key identifier wrapper and the
// two view-modifiers that own MeView's lifecycle (snapshot loading /
// day-boundary refresh) and sheet presentation.

struct MeDayKeyWrapper: Identifiable {
    let key: String
    var id: String { key }
}

/// The small, privacy-safe piece of the payment log that the Me poster needs.
/// One record means one successful access purchase through Nowhere; it does not
/// claim that the underlying app was launched or how long it was used.
struct MePosterUnlockRecord: Codable, Equatable {
    let timestamp: Date
    let target: String
    let targetName: String?
    let minutes: Int?

    init(timestamp: Date, target: String, targetName: String?, minutes: Int? = nil) {
        self.timestamp = timestamp
        self.target = target
        self.targetName = targetName
        self.minutes = minutes
    }
}

struct MePosterUnlock: Equatable, Identifiable {
    let title: String
    let count: Int
    let minutes: Int

    var id: String { title.localizedLowercase }

    var posterLabel: String {
        minutes > 0 ? "\(title) \(minutes) min" : "\(title) ×\(count)"
    }
}

enum MePosterCanvasMode: Equatable {
    case liveToday
    case savedPast
    case healthPast
    case emptyPast
}

enum MePosterPresentationPolicy {
    static func mode(
        isToday: Bool,
        hasSavedElements: Bool,
        hasHealthData: Bool = false
    ) -> MePosterCanvasMode {
        if isToday { return .liveToday }
        if hasSavedElements { return .savedPast }
        return hasHealthData ? .healthPast : .emptyPast
    }

    static func canShare(
        mode: MePosterCanvasMode,
        hasElements: Bool,
        hasStepsData: Bool,
        hasSleepData: Bool
    ) -> Bool {
        switch mode {
        case .liveToday:
            // Today's live canvas is meaningful even before the first HealthKit
            // sample or happening arrives: it is the current state of the day.
            return true
        case .savedPast:
            // Keep the action stable while the persisted canvas is loading.
            // The health background is itself a shareable daily poster.
            return hasElements || hasStepsData || hasSleepData
        case .healthPast:
            // Recent calendar days always have a neutral energy background,
            // including while HealthKit is unavailable in Simulator or denied.
            return true
        case .emptyPast:
            return false
        }
    }
}

struct MePosterCanvasLoadID: Hashable {
    let dayKey: String
    let hasTrackedSnapshot: Bool
}

struct MeDayHealth: Equatable {
    let steps: Int?
    let sleepHours: Double?
    let stepsTarget: Double
    let sleepTargetHours: Double

    var hasStepsData: Bool { steps != nil }
    var hasSleepData: Bool { sleepHours != nil }
    var hasAnyData: Bool { hasStepsData || hasSleepData }

    var stepsPoints: Int {
        normalizedPoints(
            value: Double(steps ?? 0),
            target: stepsTarget,
            maximum: EnergyDefaults.stepsMaxPoints
        )
    }

    var sleepPoints: Int {
        normalizedPoints(
            value: sleepHours ?? 0,
            target: sleepTargetHours,
            maximum: EnergyDefaults.sleepMaxPoints
        )
    }

    init(
        steps: Int?,
        sleepHours: Double?,
        stepsTarget: Double = EnergyDefaults.stepsTarget,
        sleepTargetHours: Double = EnergyDefaults.sleepTargetHours
    ) {
        self.steps = steps
        self.sleepHours = sleepHours
        self.stepsTarget = stepsTarget
        self.sleepTargetHours = sleepTargetHours
    }

    init(snapshot: PastDaySnapshot) {
        steps = snapshot.steps
        sleepHours = snapshot.sleepHours
        stepsTarget = snapshot.stepsTarget
        sleepTargetHours = snapshot.sleepTargetHours
    }

    private func normalizedPoints(value: Double, target: Double, maximum: Int) -> Int {
        guard target > 0 else { return 0 }
        return Int(min(max(value, 0), target) / target * Double(maximum))
    }
}

enum MePosterEventLedger {
    static func unlocks(
        records: [MePosterUnlockRecord],
        dayKey: String,
        dayEndHour: Int,
        dayEndMinute: Int,
        calendar: Calendar = .current
    ) -> [MePosterUnlock] {
        var counts: [String: Int] = [:]
        var minutes: [String: Int] = [:]
        var titles: [String: String] = [:]
        var order: [String] = []

        for record in records {
            let recordDayKey = DayBoundary.dayKey(
                for: record.timestamp,
                dayEndHour: dayEndHour,
                dayEndMinute: dayEndMinute,
                calendar: calendar
            )
            guard recordDayKey == dayKey else { continue }

            let fallback = record.target.hasPrefix("group_")
                ? String(record.target.dropFirst("group_".count))
                : record.target
            let title = record.targetName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = (title?.isEmpty == false ? title : nil) ?? fallback
            let identity = resolvedTitle.localizedLowercase

            if counts[identity] == nil {
                order.append(identity)
                titles[identity] = resolvedTitle
            }
            counts[identity, default: 0] += 1
            minutes[identity, default: 0] += max(0, record.minutes ?? 0)
        }

        return order.compactMap { identity in
            guard let title = titles[identity], let count = counts[identity] else { return nil }
            return MePosterUnlock(
                title: title,
                count: count,
                minutes: minutes[identity] ?? 0
            )
        }
    }

    static func displayEvents(
        happeningTitles: [String]
    ) -> [String] {
        var seen: Set<String> = []
        var events: [String] = []

        for rawTitle in happeningTitles {
            let title = sentenceCaseIfNeeded(rawTitle)
            let identity = title.localizedLowercase
            guard !title.isEmpty, seen.insert(identity).inserted else { continue }
            events.append(title)
        }

        return events
    }

    private static func sentenceCaseIfNeeded(_ rawTitle: String) -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title == title.localizedUppercase else { return title }

        let lowercased = title.localizedLowercase
        return lowercased.prefix(1).localizedUppercase + lowercased.dropFirst()
    }
}

enum MePosterRailLayout {
    enum Role {
        case metrics
        case unlocks
    }

    enum TextAlignment: Equatable {
        case leading
        case trailing
    }

    struct Placement: Equatable {
        let center: CGPoint
        let railLength: CGFloat
        let lineHeight: CGFloat
        let textAlignment: TextAlignment

        var rotatedFrame: CGRect {
            CGRect(
                x: center.x - lineHeight / 2,
                y: center.y - railLength / 2,
                width: lineHeight,
                height: railLength
            )
        }
    }

    static func placement(
        for role: Role,
        ruleLeft: CGFloat = 38.5,
        ruleRight: CGFloat,
        artworkTop: CGFloat,
        artworkBottom: CGFloat,
        railLength: CGFloat,
        lineHeight: CGFloat
    ) -> Placement {
        switch role {
        case .metrics:
            return Placement(
                center: CGPoint(
                    x: ruleLeft + lineHeight / 2,
                    y: artworkTop + railLength / 2
                ),
                railLength: railLength,
                lineHeight: lineHeight,
                textAlignment: .leading
            )
        case .unlocks:
            return Placement(
                center: CGPoint(
                    x: ruleRight - lineHeight / 2,
                    y: artworkBottom - railLength / 2
                ),
                railLength: railLength,
                lineHeight: lineHeight,
                textAlignment: .trailing
            )
        }
    }
}

enum MePosterHappeningsLayout {
    private static func font(size: CGFloat) -> UIFont {
        UIFont(name: "GeistMono-Medium", size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .medium)
    }

    static func lineCount(
        for text: String,
        width: CGFloat,
        fontSize: CGFloat
    ) -> Int {
        guard !text.isEmpty, width > 0, fontSize > 0 else { return 0 }
        let font = font(size: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraph,
            ],
            context: nil
        )
        return max(1, Int(ceil(bounds.height / font.lineHeight - 0.01)))
    }

    static func fontSize(
        for text: String,
        width: CGFloat,
        maximumSize: CGFloat,
        maximumLines: Int
    ) -> CGFloat {
        guard !text.isEmpty, width > 0, maximumSize > 0, maximumLines > 0 else {
            return maximumSize
        }
        guard lineCount(
            for: text,
            width: width,
            fontSize: maximumSize
        ) > maximumLines else { return maximumSize }

        var lowerBound: CGFloat = 1
        var upperBound = maximumSize
        for _ in 0..<14 {
            let candidate = (lowerBound + upperBound) / 2
            if lineCount(for: text, width: width, fontSize: candidate) <= maximumLines {
                lowerBound = candidate
            } else {
                upperBound = candidate
            }
        }
        return floor(lowerBound * 100) / 100
    }
}

/// The gallery sheet used both on Me and for its share export. The canvas is
/// deliberately text-free; the day context lives in the paper margin.
struct MeGalleryPoster<Content: View>: View {
    let date: Date
    let steps: Int?
    let sleepHours: Double?
    let events: [String]
    let unlocks: [MePosterUnlock]
    let content: Content

    private let paper = Color(red: 0.969, green: 0.961, blue: 0.925)

    init(
        date: Date,
        steps: Int?,
        sleepHours: Double?,
        events: [String],
        unlocks: [MePosterUnlock] = [],
        @ViewBuilder content: () -> Content
    ) {
        self.date = date
        self.steps = steps
        self.sleepHours = sleepHours
        self.events = events
        self.unlocks = unlocks
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let scaleX = width / 604.0
            let scaleY = height / 842.0
            let ruleWidth = 527.02 * scaleX
            let ruleHeight = max(1, 3 * scaleY)
            let ruleLeft = 38.5 * scaleX
            let ruleRight = 566.02 * scaleX
            let artworkWidth = 482 * scaleX
            let artworkHeight = 659 * scaleY
            let artworkTop = 91 * scaleY
            let artworkBottom = artworkTop + artworkHeight
            let metricsLength = 245 * scaleY
            let metricsLineHeight = 15 * scaleX
            let metricsPlacement = MePosterRailLayout.placement(
                for: .metrics,
                ruleLeft: ruleLeft,
                ruleRight: ruleRight,
                artworkTop: artworkTop,
                artworkBottom: artworkBottom,
                railLength: metricsLength,
                lineHeight: metricsLineHeight
            )
            let unlocksPlacement = MePosterRailLayout.placement(
                for: .unlocks,
                ruleLeft: ruleLeft,
                ruleRight: ruleRight,
                artworkTop: artworkTop,
                artworkBottom: artworkBottom,
                railLength: metricsLength,
                lineHeight: metricsLineHeight
            )
            let footerTop = 781 * scaleY
            let footerHeight = height - footerTop
            let happeningsText = events.joined(separator: " / ")
            let happeningsWidth = 344 * scaleX
            let happeningsFontSize = MePosterHappeningsLayout.fontSize(
                for: happeningsText,
                width: happeningsWidth,
                maximumSize: width * 0.0175,
                maximumLines: 3
            )

            ZStack {
                paper

                Text(formattedDate)
                    .font(.unbounded(width * (40.0 / 604.0), weight: .black))
                    .fontDesign(nil)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: ruleWidth, height: 55 * scaleY, alignment: .leading)
                    .position(x: width * 0.5, y: 49.5 * scaleY)

                Rectangle()
                    .fill(.black)
                    .frame(width: ruleWidth, height: ruleHeight)
                    .position(x: width * 0.5, y: 77 * scaleY)

                content
                    .frame(width: artworkWidth, height: artworkHeight)
                    .clipped()
                    .position(x: width * 0.5, y: artworkTop + artworkHeight / 2)

                metricsLabel(fontSize: max(5, width * 0.019))
                    .frame(
                        width: metricsLength,
                        height: metricsLineHeight,
                        alignment: metricsPlacement.textAlignment == .leading
                            ? .leading
                            : .trailing
                    )
                    .rotationEffect(.degrees(90))
                    .position(metricsPlacement.center)

                unlocksLabel(
                    fontSize: max(5, width * 0.019),
                    availableWidth: metricsLength
                )
                    .frame(
                        width: metricsLength,
                        height: metricsLineHeight,
                        alignment: unlocksPlacement.textAlignment == .leading
                            ? .leading
                            : .trailing
                    )
                    .rotationEffect(.degrees(90))
                    .position(unlocksPlacement.center)

                Rectangle()
                    .fill(.black)
                    .frame(width: ruleWidth, height: ruleHeight)
                    .position(x: width * 0.5, y: 770.96 * scaleY)

                Text("NOWHERE")
                    .font(.unbounded(width * (24.0 / 604.0), weight: .black))
                    .fontDesign(nil)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .frame(
                        width: width * 0.36,
                        height: footerHeight,
                        alignment: .topLeading
                    )
                    .position(x: width * 0.245, y: footerTop + footerHeight / 2)

                if !events.isEmpty {
                    Text(happeningsText)
                        .font(.geistMono(size: happeningsFontSize, weight: .regular))
                        .foregroundStyle(.black.opacity(0.86))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(3)
                        .frame(
                            width: happeningsWidth,
                            height: footerHeight,
                            alignment: .topTrailing
                        )
                        .position(
                            x: ruleRight - happeningsWidth / 2,
                            y: footerTop + footerHeight / 2
                        )
                }
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(604.0 / 842.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func unlocksLabel(fontSize: CGFloat, availableWidth: CGFloat) -> some View {
        if !unlocks.isEmpty {
            let label = unlocks.map(\.posterLabel).joined(separator: " / ")
            let fittedSize = MePosterHappeningsLayout.fontSize(
                for: label,
                width: availableWidth,
                maximumSize: fontSize,
                maximumLines: 1
            )
            Text(label)
                .font(.geistMono(size: fittedSize, weight: .regular, design: .monospaced))
                .foregroundStyle(.black.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.1)
                .allowsTightening(true)
        }
    }

    @ViewBuilder
    private func metricsLabel(fontSize: CGFloat) -> some View {
        let parts = [
            steps.map { "\(formatCompactNumber($0)) steps" },
            sleepHours.map { "\($0.formatted(.number.precision(.fractionLength(1)))) h. sleep" }
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: " / "))
                .font(.geistMono(size: fontSize, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.black.opacity(0.9))
                .lineLimit(1)
        }
    }

    private var formattedDate: String {
        let calendar = Calendar.current
        return String(
            format: "%02d/%02d/%02d",
            calendar.component(.day, from: date),
            calendar.component(.month, from: date),
            calendar.component(.year, from: date) % 100
        )
    }

    private var accessibilityLabel: String {
        let metricParts = [
            steps.map { "\($0) steps" },
            sleepHours.map { "\($0.formatted(.number.precision(.fractionLength(1)))) hours sleep" }
        ].compactMap { $0 }
        return ([CachedFormatters.longDate.string(from: date)]
            + metricParts
            + unlocks.map(\.posterLabel)
            + events)
            .joined(separator: ", ")
    }
}

struct MeSelectedDayPoster: View {
    @ObservedObject var model: AppModel
    let dayKey: String
    let snapshot: PastDaySnapshot?
    let health: MeDayHealth?
    let unlockRecords: [MePosterUnlockRecord]
    let shareRequestID: Int
    var handlesShareRequest: Bool = true
    let onShareAvailabilityChange: (Bool) -> Void

    @Environment(\.appTheme) private var theme
    @AppStorage("gallery_sleep_color", store: UserDefaults.stepsTrader())
    private var liveSleepColorHex: String = "#000000"
    @AppStorage("gallery_steps_color", store: UserDefaults.stepsTrader())
    private var liveStepsColorHex: String = "#FED415"
    @AppStorage(SharedKeys.gradientStyle)
    private var liveGradientStyle: String = GradientStyle.radial.rawValue
    @AppStorage(SharedKeys.gradientPalette)
    private var liveGradientPalette: String = GradientPalette.warmSunset.rawValue
    @AppStorage(SharedKeys.canvasTexture)
    private var liveTextureRaw: String = CanvasTexture.grainSmall.rawValue
    @State private var dayCanvas: DayCanvas?
    @State private var isLoading = false
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false

    private var displayDate: Date {
        CachedFormatters.dayKey.date(from: dayKey) ?? .now
    }

    private var isToday: Bool {
        dayKey == AppModel.dayKey(for: .now)
    }

    private var posterMode: MePosterCanvasMode {
        MePosterPresentationPolicy.mode(
            isToday: isToday,
            hasSavedElements: dayCanvas?.elements.isEmpty == false,
            // A selected recent calendar day always owns a visual background.
            // HealthKit values may arrive a moment after the poster itself.
            hasHealthData: health?.hasAnyData == true || snapshot != nil || !isToday
        )
    }

    private var liveDecayNorm: Double {
        guard model.baseEnergyToday > 0 else { return 0 }
        return min(1, Double(model.spentStepsToday) / Double(model.baseEnergyToday))
    }

    private var displayedSteps: Int? {
        if isToday, model.hasStepsData { return Int(model.stepsToday) }
        return health?.steps ?? snapshot?.steps
    }

    private var displayedSleep: Double? {
        if isToday, model.hasSleepData { return model.dailySleepHours }
        return health?.sleepHours ?? snapshot?.sleepHours
    }

    private var displayedUnlocks: [MePosterUnlock] {
        let boundary = AppModel.storedDayEnd()
        return MePosterEventLedger.unlocks(
            records: unlockRecords,
            dayKey: dayKey,
            dayEndHour: boundary.hour,
            dayEndMinute: boundary.minute
        )
    }

    private var displayEvents: [String] {
        let happeningTitles: [String]
        if let canvas = dayCanvas, !canvas.elements.isEmpty {
            happeningTitles = canvas.elements.map(\.displayLabel)
        } else if isToday {
            happeningTitles = model.todayAdditions.map {
                model.resolveOptionTitle(for: $0.optionId)
            }
        } else {
            happeningTitles = snapshot?.happeningIds.map { model.resolveOptionTitle(for: $0) } ?? []
        }

        return MePosterEventLedger.displayEvents(
            happeningTitles: happeningTitles
        )
    }

    private var canShare: Bool {
        MePosterPresentationPolicy.canShare(
            mode: posterMode,
            hasElements: dayCanvas?.elements.isEmpty == false,
            hasStepsData: isToday
                ? model.hasStepsData
                : health?.hasStepsData == true
                    || snapshot != nil
                    || dayCanvas?.resolvedHasStepsData == true,
            hasSleepData: isToday
                ? model.hasSleepData
                : health?.hasSleepData == true
                    || snapshot != nil
                    || dayCanvas?.resolvedHasSleepData == true
        )
    }

    var body: some View {
        MeGalleryPoster(
            date: displayDate,
            steps: displayedSteps,
            sleepHours: displayedSleep,
            events: displayEvents,
            unlocks: displayedUnlocks
        ) {
            canvasLayer(isOffscreenRender: false)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
        .accessibilityIdentifier("me_selected_day_poster")
        .accessibilityValue(dayKey)
        .task(id: MePosterCanvasLoadID(
            dayKey: dayKey,
            hasTrackedSnapshot: snapshot != nil
        )) { await loadCanvas() }
        .onChange(of: canShare, initial: true) { _, available in
            onShareAvailabilityChange(available)
        }
        .onChange(of: shareRequestID) { _, _ in
            guard handlesShareRequest else { return }
            prepareShare()
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { shareImage = nil }) {
            if let shareImage {
                CanvasShareSheet(items: [shareImage])
            }
        }
    }

    @ViewBuilder
    private func canvasLayer(isOffscreenRender: Bool) -> some View {
        switch posterMode {
        case .liveToday:
            ZStack {
                EnergyGradientBackground(
                    stepsPoints: model.stepsPointsToday,
                    sleepPoints: model.sleepPointsToday,
                    hasStepsData: model.hasStepsData,
                    hasSleepData: model.hasSleepData,
                    showGrain: true,
                    gradientStyleOverride: liveGradientStyle,
                    gradientPaletteOverride: liveGradientPalette,
                    textureOverride: liveTextureRaw
                )

                GenerativeCanvasView(
                    elements: dayCanvas?.elements ?? [],
                    dayKey: dayKey,
                    sleepPoints: model.sleepPointsToday,
                    stepsPoints: model.stepsPointsToday,
                    sleepColor: Color(hex: liveSleepColorHex),
                    stepsColor: Color(hex: liveStepsColorHex),
                    decayNorm: liveDecayNorm,
                    backgroundColor: .clear,
                    labelColor: theme.textPrimary,
                    showLabelsOnCanvas: false,
                    showsOutlinedLabels: false,
                    showsBackgroundGradient: false,
                    hasStepsData: model.hasStepsData,
                    hasSleepData: model.hasSleepData,
                    fixedTime: isOffscreenRender ? .now : nil,
                    isOffscreenRender: isOffscreenRender
                )
            }

        case .savedPast:
            if let canvas = dayCanvas {
                ZStack {
                    EnergyGradientBackground(
                        stepsPoints: canvas.stepsPoints,
                        sleepPoints: canvas.sleepPoints,
                        hasStepsData: canvas.resolvedHasStepsData,
                        hasSleepData: canvas.resolvedHasSleepData,
                        showGrain: true,
                        gradientStyleOverride: canvas.gradientStyle,
                        gradientPaletteOverride: canvas.gradientPalette,
                        textureOverride: canvas.textureRaw
                    )

                    GenerativeCanvasView(
                        elements: canvas.elements,
                        dayKey: canvas.dayKey,
                        sleepPoints: canvas.sleepPoints,
                        stepsPoints: canvas.stepsPoints,
                        sleepColor: Color(hex: canvas.sleepColorHex),
                        stepsColor: Color(hex: canvas.stepsColorHex),
                        decayNorm: canvas.decayNorm,
                        backgroundColor: .clear,
                        labelColor: theme.textPrimary,
                        showLabelsOnCanvas: false,
                        showsOutlinedLabels: false,
                        showsBackgroundGradient: false,
                        hasStepsData: canvas.resolvedHasStepsData,
                        hasSleepData: canvas.resolvedHasSleepData,
                        fixedTime: canvas.lastModified,
                        isOffscreenRender: isOffscreenRender
                    )
                }
            }

        case .healthPast:
            let resolvedHealth = health ?? snapshot.map(MeDayHealth.init(snapshot:))
            EnergyGradientBackground(
                stepsPoints: resolvedHealth?.stepsPoints ?? 0,
                sleepPoints: resolvedHealth?.sleepPoints ?? 0,
                hasStepsData: resolvedHealth?.hasStepsData == true,
                hasSleepData: resolvedHealth?.hasSleepData == true,
                showGrain: true,
                gradientStyleOverride: liveGradientStyle,
                gradientPaletteOverride: liveGradientPalette,
                textureOverride: liveTextureRaw
            )

        case .emptyPast:
            ZStack {
                Color.black.opacity(0.12)

                if isLoading {
                    ProgressView()
                        .tint(.black.opacity(0.55))
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: "rectangle.portrait")
                            .font(.geist(.title3).weight(.light))
                        Text(String(localized: "No saved poster", comment: "Me poster – empty calendar day"))
                            .font(.geist(.caption))
                    }
                    .foregroundStyle(.black.opacity(0.42))
                }
            }
        }
    }

    @MainActor
    private func loadCanvas() async {
        isLoading = true
        dayCanvas = nil

        let key = dayKey
        var loaded = await Task.detached(priority: .userInitiated) {
            CanvasStorageService.shared.loadCanvas(for: key)
        }.value

        if MeCalendarTimeline.shouldAttemptRemoteRecovery(
            hasTrackedSnapshot: snapshot != nil,
            localCanvasMissing: loaded == nil
        ), let remote = await SupabaseSyncService.shared.fetchDayCanvas(for: key) {
            CanvasStorageService.shared.saveCanvas(remote)
            loaded = remote
        }

        guard !Task.isCancelled else { return }
        dayCanvas = loaded
        isLoading = false
    }

    @MainActor
    private func prepareShare() {
        guard canShare else { return }
        let frameSize = CGSize(width: 604, height: 842)
        let poster = MeGalleryPoster(
            date: displayDate,
            steps: displayedSteps,
            sleepHours: displayedSleep,
            events: displayEvents,
            unlocks: displayedUnlocks
        ) {
            canvasLayer(isOffscreenRender: true)
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .environment(\.appTheme, theme)

        let renderer = ImageRenderer(content: poster)
        renderer.scale = 2160 / frameSize.width
        renderer.proposedSize = .init(width: frameSize.width, height: frameSize.height)
        guard let image = renderer.uiImage else { return }
        shareImage = image
        showShareSheet = true
    }
}

enum MeFullScreenDestination: Identifiable {
    case calendar
    case day(String)

    var id: String {
        switch self {
        case .calendar: "calendar"
        case .day(let key): "day-\(key)"
        }
    }
}

/// Me-specific selection policy layered over the shared shape assignment and
/// renderer pipeline. The date is the only nonce: previews remain identical
/// for the whole logical day and naturally reroll on the next one.
enum MeHappeningPreviewStyle {
    private static let fallbackClosedShapes: [CanvasShapeType] = [
        .circle,
        .snowflake,
        .organicBlob,
    ]

    static func assignments(
        for ids: [String],
        dayKey: String,
        allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        palette: [String] = CanvasColorPalette.paletteHex
    ) -> [String: HappeningShapeAssignment] {
        let closedShapes = allowedShapes.filter { $0 != .rays }
        return HappeningShapeRoll.assignments(
            for: ids,
            dayKey: dayKey,
            nonce: 0,
            allowedShapes: closedShapes.isEmpty ? fallbackClosedShapes : closedShapes,
            palette: palette
        )
    }

    static func previewElement(
        optionId: String,
        label: String,
        assignment: HappeningShapeAssignment
    ) -> CanvasElement {
        HappeningShapeTile.previewElement(
            optionId: optionId,
            label: label,
            shapeType: assignment.shapeType,
            colorHex: assignment.colorHex,
            seed: assignment.seed,
            rotation: assignment.rotation
        )
    }
}

/// The week's most frequent happenings rendered by the exact same preview
/// surface as the palette and, underneath it, the production canvas renderers.
/// There is deliberately no Me-specific silhouette: renderer improvements and
/// the user's current allowed-shape selection flow through automatically.
struct MeWeekHappeningsView: View {
    let happenings: [MeWeekStats.HappeningFrequency]
    let resolveTitle: (String) -> String

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shapeSide: CGFloat {
        dynamicTypeSize >= .accessibility1 ? 64 : 72
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let figures = MeHappeningPreviewStyle.assignments(
                for: happenings.map(\.id),
                dayKey: AppModel.dayKey(for: context.date)
            )

            HStack(alignment: .top, spacing: 8) {
                ForEach(happenings, id: \.id) { happening in
                    if let figure = figures[happening.id] {
                        tile(happening, figure: figure)
                            .frame(maxWidth: .infinity)
                            // Renderer glows may extend beyond their Canvas.
                            // Clip each equal-width column independently so a
                            // preview can never paint over its neighbour.
                            .clipped()
                    }
                }
            }
            .accessibilityIdentifier("me_week_happenings")
        }
    }

    private func tile(
        _ happening: MeWeekStats.HappeningFrequency,
        figure: HappeningShapeAssignment
    ) -> some View {
        let title = resolveTitle(happening.id)
        let intensity = 0.42 + happening.relativeIntensity * 0.58
        let days = happening.count == 1
            ? String(localized: "1 day", comment: "MeView – happening occurred once this week")
            : String(
                localized: "\(happening.count) days",
                comment: "MeView – number of days a happening occurred this week"
            )

        return VStack(spacing: 5) {
            HappeningShapeTile(
                element: MeHappeningPreviewStyle.previewElement(
                    optionId: happening.id,
                    label: title,
                    assignment: figure
                ),
                side: shapeSide
            )
            .opacity(intensity)
            .id(figure)

            Text(title)
                .font(.geist(.caption).weight(.medium))
                .foregroundStyle(theme.textPrimary.opacity(0.92))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)

            Text(days)
                .font(.geist(.caption2))
                .foregroundStyle(theme.textSecondary.opacity(0.52))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(days)")
        .accessibilityIdentifier("me_week_happening_\(happening.id)")
    }
}

struct MeLifecycleModifier: ViewModifier {
    @ObservedObject var model: AppModel
    @Binding var cachedDayKeys: [String]
    @Binding var hasLoadedSnapshots: Bool
    @Binding var loadTask: Task<Void, Never>?
    @Binding var serverFetchTask: Task<Void, Never>?
    let onLoad: () -> Void
    let onDayEndChange: () -> Void
    let onTopConsumersChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !hasLoadedSnapshots else { return }
                hasLoadedSnapshots = true
                cachedDayKeys = MeView.computeDayKeys()
                onLoad()
            }
            .onChange(of: model.baseEnergyToday) { _, _ in
                let newKeys = MeView.computeDayKeys()
                if newKeys != cachedDayKeys {
                    cachedDayKeys = newKeys
                    onLoad()
                }
            }
            .onChange(of: model.dayEndHour) { _, _ in onDayEndChange() }
            .onChange(of: model.dayEndMinute) { _, _ in onDayEndChange() }
            .onChange(of: model.appStepsSpentByDay) { _, _ in onTopConsumersChange() }
            .onChange(of: model.ticketGroups.map(\.id)) { _, _ in onTopConsumersChange() }
            .onDisappear {
                loadTask?.cancel()
                serverFetchTask?.cancel()
            }
    }
}

struct MeSheetsModifier: ViewModifier {
    @ObservedObject var model: AppModel
    @ObservedObject var authService: AuthenticationService
    @Binding var showLogin: Bool
    @Binding var showProfileEditor: Bool
    @Binding var showFullCalendar: Bool
    @Binding var selectedDayKey: String?
    let pastDays: [String: PastDaySnapshot]
    let recentHealthByDay: [String: MeDayHealth]
    let unlockRecords: [MePosterUnlockRecord]

    private var fullScreenDestination: Binding<MeFullScreenDestination?> {
        Binding(
            get: {
                if showFullCalendar { return .calendar }
                return selectedDayKey.map(MeFullScreenDestination.day)
            },
            set: { destination in
                guard destination == nil else { return }
                showFullCalendar = false
                selectedDayKey = nil
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showLogin) {
                LoginView(authService: authService)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView(authService: authService)
            }
            .fullScreenCover(item: fullScreenDestination) { destination in
                switch destination {
                case .calendar:
                    MeFullCalendarView(
                        model: model,
                        pastDays: pastDays,
                        recentHealthByDay: recentHealthByDay,
                        unlockRecords: unlockRecords
                    )
                case .day(let key):
                    DayCanvasViewerView(
                        model: model,
                        dayKey: key,
                        snapshot: pastDays[key],
                        health: recentHealthByDay[key],
                        unlockRecords: unlockRecords
                    )
                }
            }
    }
}
