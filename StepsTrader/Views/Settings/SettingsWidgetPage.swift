import SwiftUI
import WidgetKit

struct SettingsWidgetPage: View {
    @ObservedObject var model: AppModel
    @State private var showingInstallation = false
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button { showingInstallation = true } label: {
                        SettingsActionLabel(title: String(localized: "Add widget"), icon: "plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.widgets.install")
                    .padding(.horizontal, 16)
                    SettingsGroupedSurface {
                        SettingsWidgetControls(model: model)
                            .padding(14)
                    }
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .overlay { }
        .settingsDetailPage(title: String(localized: "Widgets", comment: "Settings section title"))
        .sheet(isPresented: $showingInstallation) {
            NavigationStack {
                Text(String(localized: "Home Screen → Edit → Add Widget → Nowhere"))
                    .font(.geist(.body))
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .navigationTitle(String(localized: "Add widget"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Done")) { showingInstallation = false }
                                .foregroundStyle(theme.accentColor)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct SettingsWidgetControls: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(
        SharedKeys.widgetBackgroundMode,
        store: UserDefaults(suiteName: SharedKeys.appGroupId)
    ) private var backgroundMode: String = "basic"

    @AppStorage(SharedKeys.widgetWallpaperPosition, store: UserDefaults(suiteName: SharedKeys.appGroupId))
    private var wallpaperPosition = "top"
    @AppStorage(SharedKeys.widgetWallpaperTop, store: UserDefaults(suiteName: SharedKeys.appGroupId))
    private var wallpaperTop = 0.10
    @AppStorage(SharedKeys.widgetWallpaperBottom, store: UserDefaults(suiteName: SharedKeys.appGroupId))
    private var wallpaperBottom = 0.80
    @Environment(\.scenePhase) private var scenePhase
    @State private var wallpaperSnapshot: WidgetWallpaperSnapshot?
    @State private var wallpaperThumbnail: UIImage?
    @State private var previewLarge = false
    @State private var showingHelp = false
    @State private var previewingClear = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private func loadWallpaper() {
        guard let directory = WidgetWallpaperFile.directory else { return }
        wallpaperSnapshot = WidgetWallpaperFile.read(from: directory)
        if let data = wallpaperSnapshot?.imageData {
            wallpaperThumbnail = UIImage(data: data)
        } else {
            wallpaperThumbnail = UIImage(contentsOfFile: directory.appendingPathComponent("wallpaper_bg.jpg").path)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "For one widget: hold it → Edit Widget → Background."))
                .font(.geist(.caption))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.widgets.perWidgetHint")

            representativePreview

            HStack {
                Text(String(localized: "Default background"))
                    .font(.geist(.subheadline).weight(.semibold))
                Spacer()
                Button { showingHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.geist(size: 20))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Widget help"))
                .accessibilityIdentifier("settings.widgets.help")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 14) {
                backgroundChoice(title: String(localized: "No picture"), value: "basic")
                backgroundChoice(title: String(localized: "Picture inside"), value: "wallpaper")
                backgroundChoice(title: String(localized: "Continue wallpaper"), value: "aligned")
                backgroundChoice(title: String(localized: "Glass"), value: "clear")
            }

            if previewingClear {
                Text(String(localized: "Enable in iOS: Home Screen → Edit → Customize → Clear"))
                    .font(.geist(.caption))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.widgets.clearInstructions")
            }

            if !previewingClear && backgroundMode == "aligned" {
                wallpaperAlignment
            }
            if !previewingClear && backgroundMode != "basic" && (wallpaperThumbnail == nil || (backgroundMode == "aligned" && wallpaperSnapshot == nil)) {
                wallpaperStatus
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.widgets.controls")
        .foregroundStyle(.white)
        .onChange(of: backgroundMode) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: wallpaperPosition) { WidgetCenter.shared.reloadAllTimelines() }
        .onAppear { loadWallpaper() }
        .onChange(of: scenePhase) { if scenePhase == .active { loadWallpaper() } }
        .sensoryFeedback(.impact(weight: .light), trigger: backgroundMode)
        .sheet(isPresented: $showingHelp) {
            NavigationStack {
                List {
                    setupStep(title: String(localized: "Add a widget"), text: String(localized: "Home Screen → Edit → Add Widget → Nowhere"))
                    setupStep(title: String(localized: "Background"), text: String(localized: "For one widget: hold it → Edit Widget → Background."))
                    setupStep(title: String(localized: "App groups"), text: String(localized: "Hold a widget → Edit Widget → choose up to three groups."))
                    setupStep(title: String(localized: "Clear"), text: String(localized: "Home Screen → Edit → Customize → Clear"))
                    setupStep(title: String(localized: "Match wallpaper"), text: String(localized: "Use the same Canvas export as your wallpaper. Update Position after moving a widget."))
                }
                .navigationTitle(String(localized: "Widgets"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) { showingHelp = false }
                    }
                }
            }
            .foregroundStyle(.primary)
            .presentationDetents([.medium, .large])
        }
    }

    private func setupStep(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.geist(.subheadline).weight(.semibold))
            Text(text)
                .font(.geist(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var wallpaperPreview: some View {
        GeometryReader { geometry in
            Group {
                if let thumb = wallpaperThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                } else {
                    LinearGradient(colors: [.purple.opacity(0.4), .orange.opacity(0.3)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.geist(size: 14, weight: .light))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .allowsHitTesting(false)
    }

    private var alignedPreviewImage: UIImage? {
        guard let snapshot = wallpaperSnapshot, let image = wallpaperThumbnail?.cgImage else { return nil }
        let width = snapshot.screenSize.width * 0.86
        guard let rect = WidgetWallpaperGeometry.cropRect(
            imageSize: CGSize(width: image.width, height: image.height),
            screenSize: snapshot.screenSize,
            widgetSize: CGSize(width: width, height: width * 0.47),
            position: WidgetWallpaperPosition(rawValue: wallpaperPosition) ?? .top,
            top: wallpaperTop, bottom: wallpaperBottom),
            let cropped = image.cropping(to: rect.integral) else { return nil }
        return UIImage(cgImage: cropped)
    }

    private var wallpaperStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                SettingsShortcutPage(model: model)
            } label: {
                Label(String(localized: "Set up wallpaper"), systemImage: "arrow.right.circle")
                    .font(.geist(.subheadline).weight(.semibold))
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("settings.widgets.wallpaperSetup")
        }
    }

    private var representativePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "drop.fill")
                        .font(.onest(size: 12))
                        .foregroundStyle(previewingClear ? .white : AppColors.brandAccent)
                    Text("60").font(.onest(size: 24, weight: .medium))
                    Text(String(localized: "colors")).font(.onest(size: 12))
                    Spacer()
                    Text(String(localized: "80 earned")).font(.onest(size: 11))
                }
                GeometryReader { geometry in
                    Capsule().fill(.white.opacity(0.13))
                        .overlay(alignment: .leading) {
                            Capsule().fill(previewingClear ? .white : AppColors.brandAccent).frame(width: geometry.size.width * 0.8)
                        }
                }
                .frame(height: 4)
                HStack(spacing: 6) {
                    previewMetric(String(localized: "Steps"), icon: "shoeprints.fill", value: "20", maximum: "20")
                    previewMetric(String(localized: "Sleep"), icon: "bed.double.fill", value: "20", maximum: "20")
                    previewMetric(String(localized: "Happenings"), icon: "sparkles", value: "40", maximum: "60")
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .background {
                if previewingClear {
                    transparentPreview
                } else if backgroundMode == "aligned", let image = alignedPreviewImage {
                    GeometryReader { geometry in
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .overlay(.black.opacity(0.48))
                    }
                } else if backgroundMode != "basic" {
                    wallpaperPreview.overlay(.black.opacity(0.48))
                } else {
                    RoundedRectangle(cornerRadius: 20).fill(Color(red: 0x22/255, green: 0x28/255, blue: 0x31/255))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Example widget: 60 remaining, 80 earned, 100 daily maximum."))
        }
        .overlay(alignment: .topTrailing) {
            if previewingClear {
                Text(String(localized: "Preview"))
                    .font(.geist(size: 10))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: Capsule())
                    .offset(y: -12)
            }
        }
        .accessibilityIdentifier("settings.widgets.preview")
    }

    private func previewMetric(_ title: String, icon: String, value: String, maximum: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.onest(size: 10)).lineLimit(1).minimumScaleFactor(0.8).opacity(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.onest(size: 19, weight: .medium))
                Text("/ \(maximum)").font(.onest(size: 10)).opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    }

    private var wallpaperAlignment: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Position")).font(.geist(.subheadline).weight(.semibold))
            Picker(String(localized: "Default position"), selection: $wallpaperPosition) {
                Text(String(localized: "Top")).tag("top")
                Text(String(localized: "Middle")).tag("middle")
                Text(String(localized: "Bottom")).tag("bottom")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.widgets.position")
            DisclosureGroup(String(localized: "Adjust")) {
                VStack(alignment: .leading, spacing: 12) {
                    if let snapshot = wallpaperSnapshot, let image = wallpaperThumbnail,
                       snapshot.screenSize.width > 0, snapshot.screenSize.height > 0 {
                        alignmentDiagram(image: image, screen: snapshot.screenSize)
                        Picker(String(localized: "Preview size"), selection: $previewLarge) {
                            Text(String(localized: "Medium")).tag(false)
                            Text(String(localized: "Large")).tag(true)
                        }.pickerStyle(.segmented)
                    }
                    Text(String(localized: "Top edge: \(Int(wallpaperTop * 100))%"))
                        .font(.geist(.caption)).monospacedDigit()
                    Slider(value: $wallpaperTop, in: 0.04...0.20, step: 0.005, onEditingChanged: reloadAfterAdjustment)
                        .accessibilityLabel(String(localized: "Top edge"))
                    Text(String(localized: "Bottom edge: \(Int(wallpaperBottom * 100))%"))
                        .font(.geist(.caption)).monospacedDigit()
                    Slider(value: $wallpaperBottom, in: 0.70...0.92, step: 0.005, onEditingChanged: reloadAfterAdjustment)
                        .accessibilityLabel(String(localized: "Bottom edge"))
                    Button(String(localized: "Reset alignment")) {
                        wallpaperTop = 0.10; wallpaperBottom = 0.80
                        WidgetCenter.shared.reloadAllTimelines()
                    }.frame(minHeight: 44)
                }.padding(.top, 12)
            }
            .accessibilityIdentifier("settings.widgets.alignmentDetails")
        }
        .padding(.vertical, 12)
        // SettingsGroupedSurface is a dark-backed panel in both appearances.
        .foregroundStyle(.white)
        .tint(AppColors.brandAccent)
        .environment(\.colorScheme, .dark)
    }

    private func reloadAfterAdjustment(_ editing: Bool) {
        if !editing { WidgetCenter.shared.reloadAllTimelines() }
    }

    private func alignmentDiagram(image: UIImage, screen: CGSize) -> some View {
        let scale = 260 / screen.height
        let width = screen.width * 0.86
        let size = CGSize(width: width, height: width * (previewLarge ? 1.05 : 0.47))
        let position = WidgetWallpaperPosition(rawValue: wallpaperPosition) ?? .top
        let rect = WidgetWallpaperGeometry.cropRect(imageSize: screen, screenSize: screen,
                                                    widgetSize: size, position: position,
                                                    top: wallpaperTop, bottom: wallpaperBottom)
        return ZStack(alignment: .topLeading) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: screen.width * scale, height: 260).clipped()
            if let rect {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white, lineWidth: 2))
                    .overlay(Image(systemName: "rectangle.grid.1x2").foregroundStyle(.white))
                    .frame(width: rect.width * scale, height: rect.height * scale)
                    .offset(x: rect.minX * scale, y: rect.minY * scale)
            }
        }
        .frame(width: screen.width * scale, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(theme.adaptiveSecondaryText.opacity(0.3)))
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // A glass sample only: the Home Screen rendering mode is owned by iOS.
    private var transparentPreview: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.32, green: 0.42, blue: 0.48), Color(red: 0.45, green: 0.36, blue: 0.46)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.22))
                .frame(width: 100, height: 100)
                .offset(x: 34, y: -28)
                .blur(radius: 14)
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                }
                .padding(6)
        }
        .clipped()
        .allowsHitTesting(false)
    }

    // One shared scene makes the crop, separate picture and glass comparable.
    private func sampleWallpaper(size: CGSize) -> some View {
        Canvas { context, _ in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.76, green: 0.58, blue: 0.39)))
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.48, y: -size.height * 0.28,
                                               width: size.width * 0.86, height: size.width * 0.86)),
                         with: .color(Color(red: 0.31, green: 0.45, blue: 0.59)))
            context.fill(Path(ellipseIn: CGRect(x: -size.width * 0.32, y: size.height * 0.61,
                                               width: size.width * 0.94, height: size.width * 0.70)),
                         with: .color(Color(red: 0.53, green: 0.29, blue: 0.37)))
        }
        .frame(width: size.width, height: size.height)
    }

    private func backgroundExample(value: String) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            let inset: CGFloat = 12
            let top: CGFloat = 27
            let widget = CGSize(width: max(1, size.width - inset * 2), height: 68)
            ZStack(alignment: .topLeading) {
                sampleWallpaper(size: size)
                ZStack(alignment: .topLeading) {
                    if value == "basic" {
                        Color(red: 0x22/255, green: 0x28/255, blue: 0x31/255)
                    } else if value == "wallpaper" {
                        // A separate copy of the picture restarts inside the widget.
                        sampleWallpaper(size: widget)
                        Color.black.opacity(0.48)
                    } else {
                        // Use the exact same scene coordinates behind the widget.
                        sampleWallpaper(size: size)
                            .offset(x: -inset, y: -top)
                            .blur(radius: value == "clear" ? 5 : 0)
                        if value == "clear" { Color.white.opacity(0.22) }
                        else { Color.black.opacity(0.48) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: "drop.fill").font(.system(size: 8))
                            Text("60").font(.onest(size: 16, weight: .medium))
                            Spacer()
                        }
                        Capsule().fill(.white.opacity(0.9)).frame(height: 2)
                        HStack(spacing: 4) {
                            ForEach(0..<3) { _ in
                                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.18)).frame(height: 12)
                            }
                        }
                    }
                    .padding(9)
                    .frame(width: widget.width, height: widget.height)
                    .foregroundStyle(.white)
                }
                .frame(width: widget.width, height: widget.height, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(value == "clear" ? 0.65 : 0.25), lineWidth: 1)
                }
                .offset(x: inset, y: top)
            }
            .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func backgroundChoice(title: String, value: String) -> some View {
        let isSelected = !previewingClear && backgroundMode == value
        let isClearPreview = previewingClear && value == "clear"
        return Button {
            withMotionAnimation(.spring(response: 0.3, dampingFraction: 0.7), reduceMotion: reduceMotion) {
                previewingClear = value == "clear"
                if value != "clear" { backgroundMode = value }
            }
        } label: {
            VStack(spacing: 8) {
                backgroundExample(value: value)
                    .frame(height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder((isSelected || isClearPreview) ? AppColors.brandAccent : .white.opacity(0.12), lineWidth: (isSelected || isClearPreview) ? 2 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if value == "clear" {
                        Text("iOS").font(.geist(size: 10))
                            .padding(5)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(5)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(AppAccentInk.primary, AppColors.brandAccent)
                            .padding(5)
                    }
                }
                Text(title).font(.geist(.caption))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsSelectable(label: title, isSelected: isSelected)
        .accessibilityHint(value == "clear" ? String(localized: "Preview only. Enable Clear in iOS Home Screen customization.") : "")
        .accessibilityIdentifier(value == "aligned" ? "settings.widgets.matchWallpaper" : "settings.widgets.background.\(value)")
    }
}

#Preview {
    NavigationStack {
        SettingsWidgetPage(model: DIContainer.shared.makeAppModel())
    }
}
