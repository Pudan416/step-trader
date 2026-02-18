import SwiftUI
import WidgetKit

private enum WidgetSharedStore {
    static let appGroupId = "group.personal-project.StepsTrader"
    static let inkKey = "stepsBalance"

    static var inkBalance: Int {
        let defaults = UserDefaults(suiteName: appGroupId) ?? .standard
        return Int(defaults.double(forKey: inkKey))
    }
}

struct InkEntry: TimelineEntry {
    let date: Date
    let ink: Int
}

struct InkProvider: TimelineProvider {
    func placeholder(in context: Context) -> InkEntry {
        InkEntry(date: Date(), ink: 120)
    }

    func getSnapshot(in context: Context, completion: @escaping (InkEntry) -> Void) {
        completion(InkEntry(date: Date(), ink: WidgetSharedStore.inkBalance))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InkEntry>) -> Void) {
        let currentDate = Date()
        let entry = InkEntry(date: currentDate, ink: WidgetSharedStore.inkBalance)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct InkLockScreenWidgetView: View {
    var entry: InkProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("ink \(entry.ink)")
        case .accessoryCircular:
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 2)
                Text("\(entry.ink)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("ink")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(entry.ink)")
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text("\(entry.ink)")
        }
    }
}

struct ProofLockScreenWidget: Widget {
    let kind: String = "ProofLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InkProvider()) { entry in
            InkLockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Ink")
        .description("Shows your current ink on the Lock Screen.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct ProofLockScreenWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProofLockScreenWidget()
    }
}
