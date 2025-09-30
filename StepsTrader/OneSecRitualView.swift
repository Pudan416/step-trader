import SwiftUI

struct OneSecRitualView: View {
    @ObservedObject var model: AppModel
    @State private var currentStep = 0
    @State private var breathingPhase = 0 // 0: inhale, 1: hold, 2: exhale
    @State private var breathingTimer: Timer?
    @State private var ritualTimer: Timer?
    @State private var timeRemaining = 10
    @State private var isCompleted = false
    @State private var showQuestions = false
    @State private var questionIndex = 0
    @State private var answer = ""
    
    let questions = [
        "Зачем вы хотите открыть это приложение?",
        "Что вы планируете там делать?",
        "Сколько времени потратите?",
        "Это действительно важно сейчас?"
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // App icon and name
                VStack(spacing: 16) {
                    Image(systemName: getAppIcon())
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                    
                    Text("Вы пытаетесь открыть")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(model.interceptedAppName ?? "Приложение")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                if !isCompleted {
                    // Breathing circle
                    if currentStep == 0 {
                        breathingView
                    }
                    
                    // Questions phase
                    if currentStep == 1 {
                        questionsView
                    }
                    
                    // Wait phase
                    if currentStep == 2 {
                        waitView
                    }
                } else {
                    // Completion
                    completionView
                }
                
                Spacer()
                
                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index <= currentStep ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            startRitual()
        }
        .onDisappear {
            stopTimers()
        }
    }
    
    private var breathingView: some View {
        VStack(spacing: 30) {
            Text("Сделайте глубокий вдох")
                .font(.title2)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 4)
                    .frame(width: 200, height: 200)
                
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: breathingPhase == 0 ? 50 : 150, height: breathingPhase == 0 ? 50 : 150)
                    .animation(.easeInOut(duration: 4), value: breathingPhase)
            }
            
            Text(breathingPhase == 0 ? "Вдох" : breathingPhase == 1 ? "Задержка" : "Выдох")
                .font(.title3)
                .foregroundColor(.white)
        }
    }
    
    private var questionsView: some View {
        VStack(spacing: 30) {
            Text("Ответьте на вопрос")
                .font(.title2)
                .foregroundColor(.white)
            
            Text(questions[questionIndex])
                .font(.title3)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            TextField("Ваш ответ...", text: $answer)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal, 40)
            
            Button("Далее") {
                nextQuestion()
            }
            .buttonStyle(.borderedProminent)
            .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    private var waitView: some View {
        VStack(spacing: 30) {
            Text("Подождите...")
                .font(.title2)
                .foregroundColor(.white)
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: CGFloat(timeRemaining) / 10.0)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timeRemaining)
                
                Text("\(timeRemaining)")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }
    
    private var completionView: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Ритуал завершен")
                .font(.title2)
                .foregroundColor(.white)
            
            Button("Открыть \(model.interceptedAppName ?? "приложение")") {
                openTargetApp()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    private func getAppIcon() -> String {
        guard let bundleId = model.interceptedTargetBundleId else { return "app" }
        
        switch bundleId {
        case "com.burbn.instagram":
            return "camera"
        case "com.zhiliaoapp.musically":
            return "music.note"
        case "com.twitter.ios":
            return "bird"
        case "com.facebook.Facebook":
            return "person.2"
        default:
            return "app"
        }
    }
    
    private func startRitual() {
        // Start breathing phase
        startBreathingTimer()
        
        // Move to questions after 15 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if !isCompleted {
                currentStep = 1
                stopBreathingTimer()
            }
        }
    }
    
    private func startBreathingTimer() {
        breathingTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            breathingPhase = (breathingPhase + 1) % 3
        }
    }
    
    private func stopBreathingTimer() {
        breathingTimer?.invalidate()
        breathingTimer = nil
    }
    
    private func nextQuestion() {
        if questionIndex < questions.count - 1 {
            questionIndex += 1
            answer = ""
        } else {
            // Move to wait phase
            currentStep = 2
            startWaitTimer()
        }
    }
    
    private func startWaitTimer() {
        timeRemaining = 10
        ritualTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 1 {
                timeRemaining -= 1
            } else {
                completeRitual()
            }
        }
    }
    
    private func completeRitual() {
        stopTimers()
        isCompleted = true
        
        // Mark ritual as completed
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.set(Date(), forKey: "lastRitualCompleted")
        
        // Auto-open target app after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            openTargetApp()
        }
    }
    
    private func stopTimers() {
        breathingTimer?.invalidate()
        ritualTimer?.invalidate()
        breathingTimer = nil
        ritualTimer = nil
    }
    
    private func openTargetApp() {
        guard let bundleId = model.interceptedTargetBundleId else { return }
        
        // Try to open the app using URL scheme
        var urlString = ""
        switch bundleId {
        case "com.burbn.instagram":
            urlString = "instagram://app"
        case "com.zhiliaoapp.musically":
            urlString = "tiktok://"
        case "com.twitter.ios":
            urlString = "twitter://"
        case "com.facebook.Facebook":
            urlString = "fb://"
        default:
            // Try generic app opening
            if let url = URL(string: "\(bundleId)://") {
                UIApplication.shared.open(url)
                return
            }
        }
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url) { success in
                if !success {
                    // Fallback to App Store
                    openAppStore(for: bundleId)
                }
            }
        } else {
            openAppStore(for: bundleId)
        }
        
        // Close our app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        }
    }
    
    private func openAppStore(for bundleId: String) {
        let appStoreURL = "https://apps.apple.com/app/id\(bundleId)"
        if let url = URL(string: appStoreURL) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    OneSecRitualView(model: AppModel(
        healthKitService: HealthKitService(),
        familyControlsService: FamilyControlsService(),
        notificationService: NotificationManager(),
        budgetEngine: BudgetEngine()
    ))
}
