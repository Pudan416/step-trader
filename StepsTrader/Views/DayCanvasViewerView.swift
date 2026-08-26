import SwiftUI

// MARK: - Day poster viewer

/// Full-screen presentation of the same gallery poster used on Me. Keeping the
/// poster itself shared guarantees that the calendar, viewer and exported image
/// never drift into different typography or metadata layouts.
struct DayCanvasViewerView: View {
    @ObservedObject var model: AppModel
    let dayKey: String
    let health: MeDayHealth?
    let unlockRecords: [MePosterUnlockRecord]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var snapshot: PastDaySnapshot?
    @State private var shareRequestID = 0
    @State private var posterCanShare = false

    init(
        model: AppModel,
        dayKey: String,
        snapshot: PastDaySnapshot? = nil,
        health: MeDayHealth? = nil,
        unlockRecords: [MePosterUnlockRecord] = []
    ) {
        self.model = model
        self.dayKey = dayKey
        self.health = health
        self.unlockRecords = unlockRecords
        _snapshot = State(initialValue: snapshot)
    }

    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()

            VStack(spacing: 12) {
                topBar

                Spacer(minLength: 0)

                MeSelectedDayPoster(
                    model: model,
                    dayKey: dayKey,
                    snapshot: snapshot,
                    health: health ?? snapshot.map(MeDayHealth.init(snapshot:)),
                    unlockRecords: unlockRecords,
                    shareRequestID: shareRequestID,
                    onShareAvailabilityChange: { posterCanShare = $0 }
                )
                .padding(.horizontal, 28)

                Spacer(minLength: 16)
            }
            .padding(.top, 8)
        }
        .energyGradientBackground(model: model, showGrain: false)
        .preferredColorScheme(theme.colorScheme)
        .task(id: dayKey) {
            guard snapshot == nil else { return }
            snapshot = model.loadPastDaySnapshots()[dayKey]
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.geist(size: 13, weight: .bold))
                    .foregroundStyle(theme.adaptivePrimaryText)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close", comment: "DayCanvasViewer – close VoiceOver"))

            Spacer()

            Button {
                shareRequestID &+= 1
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.geist(size: 16, weight: .regular))
                    .foregroundStyle(theme.adaptivePrimaryText)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!posterCanShare)
            .opacity(posterCanShare ? 1 : 0.3)
            .accessibilityIdentifier("day_poster_share")
            .accessibilityLabel(String(localized: "Share canvas", comment: "DayCanvasViewer – share VoiceOver"))
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    DayCanvasViewerView(
        model: DIContainer.shared.makeAppModel(),
        dayKey: AppModel.dayKey(for: .now)
    )
}
