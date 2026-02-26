import AppIntents

struct StepsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ExportCanvasWallpaperIntent(),
            phrases: [
                "Export canvas wallpaper with \(.applicationName)",
                "Get my canvas wallpaper from \(.applicationName)",
                "Canvas wallpaper \(.applicationName)",
                "Set \(\.$gradientStyle) wallpaper with \(.applicationName)",
                "Export \(\.$colorPalette) canvas from \(.applicationName)"
            ],
            shortTitle: "Canvas Wallpaper",
            systemImageName: "photo.artframe"
        )
    }
}
