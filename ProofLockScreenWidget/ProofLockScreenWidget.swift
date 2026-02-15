import SwiftUI
import WidgetKit

private enum WidgetSharedStore {
    static let appGroupId = "group.personal-project.StepsTrader"
    static let experienceKey = "stepsBalance"

    static var experienceBalance: Int {
        let defaults = UserDefaults(suiteName: appGroupId) ?? .standard
        return Int(defaults.double(forKey: experienceKey))
    }
}

struct ExperienceEntry: TimelineEntry {
    let date: Date
    let experience: Int
}

struct ExperienceProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExperienceEntry {
        ExperienceEntry(date: Date(), experience: 120)
    }

    func getSnapshot(in context: Context, completion: @escaping (ExperienceEntry) -> Void) {
        completion(ExperienceEntry(date: Date(), experience: WidgetSharedStore.experienceBalance))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExperienceEntry>) -> Void) {
        let currentDate = Date()
        let entry = ExperienceEntry(date: currentDate, experience: WidgetSharedStore.experienceBalance)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct ExperienceLockScreenWidgetView: View {
    var entry: ExperienceProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("experience \(entry.experience)")
        case .accessoryCircular:
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 2)
                Text("\(entry.experience)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("experience")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(entry.experience)")
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text("\(entry.experience)")
        }
    }
}

struct ProofLockScreenWidget: Widget {
    let kind: String = "ProofLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExperienceProvider()) { entry in
            ExperienceLockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Experience")
        .description("Shows your current experience on the Lock Screen.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct ProofLockScreenWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProofLockScreenWidget()
    }
}
