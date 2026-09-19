import Foundation

protocol NotificationServiceProtocol {
    func requestPermission() async throws
    func sendTimeExpiredNotification()
    func sendUnblockNotification(remainingMinutes: Int)
    func sendRemainingTimeNotification(remainingMinutes: Int)
    func sendMinuteModeSummary(bundleId: String, minutesUsed: Int, stepsCharged: Int)
    func sendTestNotification()
    func sendAccessWindowReminder(remainingSeconds: Int, bundleId: String)
    func scheduleAccessWindowStatus(remainingSeconds: Int, bundleId: String)
}
