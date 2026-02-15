import Foundation

#if DEBUG
struct DailyOpen: Identifiable {
    let id = UUID()
    let day: Date
    let bundleId: String
    let count: Int
    let appName: String
}

struct AppUsageToday: Identifiable {
    let id = UUID()
    let bundleId: String
    let name: String
    let imageName: String?
    let opens: Int
    let steps: Int
}
#endif
