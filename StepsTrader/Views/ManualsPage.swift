import SwiftUI

struct ManualsPage: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var isExpanded: Bool = false
    @State private var isLevelsExpanded: Bool = false
    @State private var isEntryExpanded: Bool = false
    @State private var showGallery: Bool = false
    @State private var galleryImages: [String] = []
    @State private var galleryIndex: Int = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header section
                        headerSection
                        
                        // Setup guide card
                        setupGuideCard
                        
                        // Levels explanation card
                        expandableCard(
                            title: appLanguage == "ru" ? "Как прокачивать уровни" : "How levels work",
                            icon: "chart.line.uptrend.xyaxis",
                            iconColor: .green,
                            expanded: $isLevelsExpanded,
                            content: levelsContent
                        )
                        
                        // Entry options card
                        expandableCard(
                            title: appLanguage == "ru" ? "Варианты входа" : "Entry options",
                            icon: "door.left.hand.open",
                            iconColor: .orange,
                            expanded: $isEntryExpanded,
                            content: entryOptionsContent
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .scrollIndicators(.hidden)
                .background(Color(.systemGroupedBackground))
                
                // Gallery overlay
                if showGallery {
                    galleryOverlay
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .onDisappear {
            showGallery = false
            galleryImages = []
            isExpanded = false
            isLevelsExpanded = false
            isEntryExpanded = false
        }
    }
    
    // Glass card style for ManualsPage
    private var manualsGlassCard: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(loc(appLanguage, "Field Manual"))
                    .font(.headline)
                Text(loc(appLanguage, "Level up your shield game 🎮"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Setup Guide Card
    private var setupGuideCard: some View {
        let pink = Color(red: 224/255, green: 130/255, blue: 217/255)
        
        return VStack(alignment: .leading, spacing: 0) {
            // Card header
                            Button {
                withAnimation(.spring(response: 0.3)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(pink.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.subheadline)
                            .foregroundColor(pink)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLanguage == "ru" ? "Как врубить щит" : "How to arm your shield")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text(appLanguage == "ru" ? "4 шага до контроля 💪" : "4 steps to take control 💪")
                            .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Circle().fill(Color(.tertiarySystemBackground)))
                }
                .padding(14)
                            }
                            
                            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    // Image carousel
                                    let manualImages = (1...11).map { "manual_1_\($0)" }
                                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                                            ForEach(Array(manualImages.enumerated()), id: \.offset) { index, name in
                                                Image(name)
                                                    .resizable()
                                                    .scaledToFit()
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                                                    .onTapGesture {
                                                        openGallery(images: manualImages, startAt: index)
                                                    }
                                            }
                                        }
                        .padding(.horizontal, 14)
                    }
                    
                    // Steps - edgy
                    VStack(alignment: .leading, spacing: 8) {
                        stepRow(number: 1, text: appLanguage == "ru" ? "Открой ссылку → добавь в Команды" : "Open link → Add to Shortcuts")
                        stepRow(number: 2, text: appLanguage == "ru" ? "Команды → Автоматизация → + → Приложение → включи 'Открыто' + 'Выполнять сразу'" : "Shortcuts → Automation → + → App → enable 'Is Opened' + 'Run Immediately'")
                        stepRow(number: 3, text: appLanguage == "ru" ? "Выбери [app] CTRL щит → Сохрани" : "Pick [app] CTRL shield → Save")
                        stepRow(number: 4, text: appLanguage == "ru" ? "Открой приложение один раз — щит активирован 🔥" : "Open the app once — shield is live 🔥")
                    }
                    .padding(.horizontal, 14)
                    
                    // Tip - edgy
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                                .font(.subheadline)
                        
                        Text(appLanguage == "ru" ? "Не работает? Проверь уведомления и доступ к Командам" : "Not working? Check notifications & Shortcuts access")
                            .font(.caption)
                                        .foregroundColor(.secondary)
                        }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
        .background(manualsGlassCard)
    }
    
    @ViewBuilder
    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Gallery Overlay
    private var galleryOverlay: some View {
                    ZStack {
            Color.black.opacity(0.9)
                            .ignoresSafeArea()
                            .onTapGesture { closeGallery() }
                        
            VStack {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        closeGallery()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding()
                }
                
                // Image viewer
                        TabView(selection: $galleryIndex) {
                            ForEach(Array(galleryImages.enumerated()), id: \.offset) { index, name in
                                if let uiImage = UIImage(named: name) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .tag(index)
                                .padding(.horizontal, 20)
                                } else {
                                    Color.clear.tag(index)
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                
                // Image counter
                Text("\(galleryIndex + 1) / \(galleryImages.count)")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 20)
            }
        }
        .zIndex(2)
        .transition(.opacity)
                        .gesture(
            DragGesture(minimumDistance: 50)
                                .onEnded { value in
                    if abs(value.translation.height) > 80 {
                                        closeGallery()
                                    }
                                }
                        )
    }

    @ViewBuilder
    private func levelsContent() -> some View {
        let items: [(icon: String, color: Color, ru: String, en: String)] = [
            ("flame.fill", .orange, "Чем больше тратишь — тем сильнее щит. Топливо = опыт 🔥", "More fuel burned = stronger shield. Fuel = XP 🔥"),
            ("star.fill", .yellow, "10 уровней: II на 10K, до X на 500K шагов", "10 levels: II at 10K, up to X at 500K steps"),
            ("bolt.fill", .green, "Выше уровень → дешевле вход: I=100, X=10 шагов", "Higher level → cheaper entry: I=100, X=10 steps"),
            ("chart.bar.fill", .blue, "Смотри прогресс на карточке щита", "Check progress on the shield card")
        ]
        
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.ru) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.icon)
                        .foregroundColor(item.color)
                        .font(.caption)
                        .frame(width: 20)
                    Text(appLanguage == "ru" ? item.ru : item.en)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private func entryOptionsContent() -> some View {
        let manualImages = ["manual_2_1", "manual_2_2", "manual_2_3"]
        let items: [(icon: String, color: Color, ru: String, en: String)] = [
            ("clock.fill", .purple, "Разным приложениям — разное время ⏰", "Different apps need different fuel ⏰"),
            ("door.left.hand.open", .orange, "Где-то хватит входа, где-то надо зависнуть", "Sometimes quick peek, sometimes deep dive"),
            ("square.grid.2x2.fill", .blue, "Выбирай: разовый, 5 мин, час или день", "Pick: single, 5 min, hour, or day pass"),
            ("bolt.fill", .green, "Цена зависит от уровня (10–100 за вход)", "Cost scales with level (10–100 per entry)"),
            ("slider.horizontal.3", .gray, "Лишнее отключи в настройках щита", "Turn off unused modes in shield settings")
        ]

        VStack(alignment: .leading, spacing: 14) {
            // Image carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(manualImages.enumerated()), id: \.offset) { index, name in
                        Image(name)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                            .onTapGesture {
                                openGallery(images: manualImages, startAt: index)
                            }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.ru) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.icon)
                            .foregroundColor(item.color)
                            .font(.caption)
                            .frame(width: 20)
                        Text(appLanguage == "ru" ? item.ru : item.en)
                            .font(.caption)
                        .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        }
        .padding(14)
    }

    private func openGallery(images: [String], startAt index: Int) {
        galleryImages = images
        galleryIndex = index
        withAnimation(.spring(response: 0.3)) {
            showGallery = true
        }
    }
    
    private func closeGallery() {
        withAnimation(.spring(response: 0.3)) {
            showGallery = false
        }
    }

    private func expandableCard(title: String, icon: String, iconColor: Color, expanded: Binding<Bool>, content: @escaping () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundColor(iconColor)
                    }
                    
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Circle().fill(Color(.tertiarySystemBackground)))
                }
                .padding(14)
            }

            if expanded.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(manualsGlassCard)
    }
}
