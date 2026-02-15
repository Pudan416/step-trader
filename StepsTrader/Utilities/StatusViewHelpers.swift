import SwiftUI

#if DEBUG
enum StatusViewHelpers {
    static func colorForBundle(_ bundleId: String) -> Color {
        switch bundleId {
        case "com.burbn.instagram": return .pink
        case "com.zhiliaoapp.musically": return .red
        case "com.google.ios.youtube": return Color(red: 1, green: 0, blue: 0)
        case "com.facebook.Facebook": return .blue
        case "com.linkedin.LinkedIn": return Color(red: 0, green: 0.47, blue: 0.71)
        case "com.atebits.Tweetie2": return .black
        case "com.toyopagroup.picaboo": return .yellow
        case "net.whatsapp.WhatsApp": return .green
        case "ph.telegra.Telegraph": return .cyan
        case "com.duolingo.DuolingoMobile": return Color(red: 0.35, green: 0.8, blue: 0.2)
        case "com.pinterest": return .red
        case "com.reddit.Reddit": return .orange
        default: return .purple
        }
    }
    
    static func formatMinutes(_ minutes: Int, appLanguage: String = "en") -> String {
        let clamped = max(0, minutes)
        let hours = clamped / 60
        let mins = clamped % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins) min"
    }
    
    static func formatNumber(_ num: Int) -> String {
        let absValue = abs(num)
        let sign = num < 0 ? "-" : ""
        
        func trimTrailingZero(_ s: String) -> String {
            s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        }
        
        if absValue < 1000 { return "\(num)" }
        
        if absValue < 10_000 {
            let v = (Double(absValue) / 1000.0 * 10).rounded() / 10
            let s = String(format: "%.1f", v)
            return sign + trimTrailingZero(s) + "K"
        }
        if absValue < 1_000_000 {
            return sign + "\(Int((Double(absValue) / 1000.0).rounded()))K"
        }
        let v = (Double(absValue) / 1_000_000.0 * 10).rounded() / 10
        let s = String(format: "%.1f", v)
        return sign + trimTrailingZero(s) + "M"
    }
}
#endif
