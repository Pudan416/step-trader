import SwiftUI
import UserNotifications

struct BlockScreenNew: View {
    @ObservedObject var model: AppModel
    let bundleId: String
    let appName: String
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    @State private var showPushState = false
    @State private var pushSent = false
    @State private var waitingForPush = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.red.opacity(0.1), .orange.opacity(0.3), .red.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                if showPushState {
                    pushStateView
                } else {
                    blockedStateView
                }
            }
            .padding()
        }
        .onAppear {
            checkPushState()
        }
    }
    
    // MARK: - Blocked State
    private var blockedStateView: some View {
        VStack(spacing: 24) {
            // Shield icon
            Image(systemName: "shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)
            
            // Title
            Text(loc(appLanguage, "App Blocked"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // App name
            Text(appName)
                .font(.title2)
                .foregroundColor(.secondary)
            
            // Description
            Text(loc(appLanguage, "This app is protected by a shield. Unlock it to continue."))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            // Unlock button
            Button {
                requestPushNotification()
            } label: {
                HStack {
                    Image(systemName: "lock.open.fill")
                    Text(loc(appLanguage, "Unlock"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Push State
    private var pushStateView: some View {
        VStack(spacing: 24) {
            // Notification icon
            Image(systemName: pushSent ? "bell.fill" : "bell.slash.fill")
                .font(.system(size: 80))
                .foregroundColor(pushSent ? .green : .orange)
            
            // Title
            Text(loc(appLanguage, "Check Your Notifications"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // Description
            Text(loc(appLanguage, "We sent you a push notification. Tap on it to open the paygate and choose how long to unlock the app."))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            // Push not received button
            Button {
                requestPushNotification()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text(loc(appLanguage, "Push Not Received"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
                .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Helpers
    private func checkPushState() {
        // Check if we should show push state
        // This would be set when a push was sent
        let defaults = UserDefaults.stepsTrader()
        if defaults.bool(forKey: "pushSentFor_\(bundleId)") {
            showPushState = true
            pushSent = true
        }
    }
    
    private func requestPushNotification() {
        Task {
            await sendPushNotification()
        }
    }
    
    private func sendPushNotification() async {
        let center = UNUserNotificationCenter.current()
        
        // Request permission if needed
        let settings = await center.notificationSettings()
        if settings.authorizationStatus != .authorized {
            do {
                try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("❌ Failed to request notification permission: \(error)")
                return
            }
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = loc(appLanguage, "Unlock \(appName)")
        content.body = loc(appLanguage, "Tap to choose unlock time")
        content.sound = .default
        content.categoryIdentifier = "UNLOCK_APP"
        content.userInfo = [
            "bundleId": bundleId,
            "appName": appName,
            "action": "unlock"
        ]
        
        // Create request
        let request = UNNotificationRequest(
            identifier: "unlock_\(bundleId)_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        // Add notification
        do {
            try await center.add(request)
            print("✅ Push notification sent for \(bundleId)")
            
            // Mark as sent
            let defaults = UserDefaults.stepsTrader()
            defaults.set(true, forKey: "pushSentFor_\(bundleId)")
            defaults.set(Date(), forKey: "pushSentAt_\(bundleId)")
            
            // Switch to push state
            await MainActor.run {
                showPushState = true
                pushSent = true
            }
        } catch {
            print("❌ Failed to send push notification: \(error)")
        }
    }
}

