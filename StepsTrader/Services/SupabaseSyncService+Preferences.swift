import Foundation
import os.log

// MARK: - User Preferences Sync
extension SupabaseSyncService {
    
    /// Sync user preferences (targets, day boundary, preferred options, canvas slots)
    func syncUserPreferences(
        stepsTarget: Double,
        sleepTarget: Double,
        dayEndHour: Int,
        dayEndMinute: Int,
        restDayOverride: Bool,
        preferredBody: [String],
        preferredMind: [String],
        preferredHeart: [String],
        canvasSlots: [DayCanvasSlot],
        hasWallpaperShortcut: Bool,
        wallpaperShortcutUses: Int,
        notifyOneMinBefore: Bool = true,
        notifyWhenTimerOver: Bool = true,
        notifyCanvasReminder: Bool = true,
        canvasReminderHour: Int = 21,
        canvasReminderMinute: Int = 0,
        notifyDayResetWarning: Bool = true,
        dayResetWarningHours: Int = 1,
        hasMediumWidget: Bool = false,
        hasLargeWidget: Bool = false,
        lastOpenedAt: Date? = nil
    ) {
        let payload = UserPreferencesPayload(
            stepsTarget: stepsTarget,
            sleepTarget: sleepTarget,
            dayEndHour: dayEndHour,
            dayEndMinute: dayEndMinute,
            restDayOverride: restDayOverride,
            preferredBody: preferredBody,
            preferredMind: preferredMind,
            preferredHeart: preferredHeart,
            canvasSlots: canvasSlots,
            hasWallpaperShortcut: hasWallpaperShortcut,
            wallpaperShortcutUses: wallpaperShortcutUses,
            notifyOneMinBefore: notifyOneMinBefore,
            notifyWhenTimerOver: notifyWhenTimerOver,
            notifyCanvasReminder: notifyCanvasReminder,
            canvasReminderHour: canvasReminderHour,
            canvasReminderMinute: canvasReminderMinute,
            notifyDayResetWarning: notifyDayResetWarning,
            dayResetWarningHours: dayResetWarningHours,
            hasMediumWidget: hasMediumWidget,
            hasLargeWidget: hasLargeWidget,
            lastOpenedAt: lastOpenedAt
        )
        
        if payload == pendingPreferences { return }
        if payload == lastSentPreferences {
            pendingPreferences = nil
            preferencesSyncTask?.cancel()
            return
        }
        
        pendingPreferences = payload
        preferencesSyncTask?.cancel()
        preferencesSyncTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 sec debounce
            guard !Task.isCancelled else { return }
            guard let latest = pendingPreferences else { return }
            await performPreferencesSync(payload: latest)
        }
    }
    
    /// Track wallpaper shortcut usage (lightweight, called from Intent)
    func trackWallpaperShortcutUsage() async {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Wallpaper shortcut tracking skipped: no auth")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_preferences")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id")]
            guard let url = urlComps.url else { return }
            
            let g = UserDefaults(suiteName: SharedKeys.appGroupId) ?? UserDefaults.standard
            let hasShortcut = g.bool(forKey: "hasWallpaperShortcut")
            let uses = g.integer(forKey: "wallpaperShortcutUses")
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            
            let row: [String: Any] = [
                "user_id": userId,
                "has_wallpaper_shortcut": hasShortcut,
                "wallpaper_shortcut_uses": uses,
                "updated_at": iso8601String(Date())
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: row)
            
            let (_, response) = try await network.data(for: request)
            if response.statusCode < 400 {
                AppLogger.network.debug("📡 Wallpaper shortcut usage tracked: uses=\(uses)")
            }
        } catch {
            AppLogger.network.error("📡 Failed to track wallpaper shortcut: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Perform Preferences Sync
    
    func performPreferencesSync(payload: UserPreferencesPayload) async {
        if payload == lastSentPreferences { return }
        
        defer {
            if pendingPreferences == payload {
                pendingPreferences = nil
            }
        }
        
        await AuthenticationService.shared.waitForInitialization()
        if Task.isCancelled { return }
        
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Preferences sync skipped: no auth")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_preferences")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id")]
            guard let url = urlComps.url else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            
            let slotsData = (try? JSONEncoder().encode(payload.canvasSlots)) ?? Data("[]".utf8)
            let slotsJson = try JSONSerialization.jsonObject(with: slotsData)
            
            var row: [String: Any] = [
                "user_id": userId,
                "steps_target": payload.stepsTarget,
                "sleep_target": payload.sleepTarget,
                "day_end_hour": payload.dayEndHour,
                "day_end_minute": payload.dayEndMinute,
                "rest_day_override": payload.restDayOverride,
                "preferred_body": payload.preferredBody,
                "preferred_mind": payload.preferredMind,
                "preferred_heart": payload.preferredHeart,
                "gallery_slots": slotsJson,
                "has_wallpaper_shortcut": payload.hasWallpaperShortcut,
                "wallpaper_shortcut_uses": payload.wallpaperShortcutUses,
                "notify_one_min_before": payload.notifyOneMinBefore,
                "notify_when_timer_over": payload.notifyWhenTimerOver,
                "notify_canvas_reminder": payload.notifyCanvasReminder,
                "canvas_reminder_hour": payload.canvasReminderHour,
                "canvas_reminder_minute": payload.canvasReminderMinute,
                "notify_day_reset_warning": payload.notifyDayResetWarning,
                "day_reset_warning_hours": payload.dayResetWarningHours,
                "has_medium_widget": payload.hasMediumWidget,
                "has_large_widget": payload.hasLargeWidget,
                "updated_at": iso8601String(Date())
            ]
            if let lastOpened = payload.lastOpenedAt {
                row["last_opened_at"] = iso8601String(lastOpened)
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: row)
            
            let (data, response) = try await network.data(for: request)
            if Task.isCancelled { return }
            if response.statusCode < 400 {
                lastSentPreferences = payload
                AppLogger.network.debug("📡 User preferences synced")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Preferences sync failed: HTTP \(response.statusCode) - \(body)")
                enqueueForRetry(request)
            }
        } catch {
            AppLogger.network.error("📡 Preferences sync error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Restore from Server
    
    /// Load user preferences from Supabase
    func loadUserPreferencesFromServer() async -> (
        stepsTarget: Double, sleepTarget: Double,
        dayEndHour: Int, dayEndMinute: Int,
        restDayOverride: Bool,
        preferredBody: [String], preferredMind: [String], preferredHeart: [String],
        canvasSlots: [DayCanvasSlot],
        hasWallpaperShortcut: Bool, wallpaperShortcutUses: Int,
        notifyOneMinBefore: Bool, notifyWhenTimerOver: Bool,
        notifyCanvasReminder: Bool, canvasReminderHour: Int, canvasReminderMinute: Int,
        notifyDayResetWarning: Bool, dayResetWarningHours: Int,
        hasMediumWidget: Bool, hasLargeWidget: Bool
    )? {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            return nil
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/user_preferences")
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "1")
            ]
            guard let finalURL = comps.url else { return nil }
            
            var request = URLRequest(url: finalURL)
            request.httpMethod = "GET"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            
            let (data, response) = try await network.data(for: request)
            guard response.statusCode < 400 else { return nil }
            
            let rows = try JSONDecoder().decode([UserPreferencesRow].self, from: data)
            guard let row = rows.first else {
                AppLogger.network.debug("📡 No preferences found on server")
                return nil
            }
            
            var canvasSlots: [DayCanvasSlot] = []
            if let rawSlots = row.canvasSlots?.value {
                let slotsData = try JSONSerialization.data(withJSONObject: rawSlots)
                canvasSlots = (try? JSONDecoder().decode([DayCanvasSlot].self, from: slotsData)) ?? []
            }
            
            AppLogger.network.debug("📡 Loaded user preferences from server")
            return (
                stepsTarget: row.stepsTarget,
                sleepTarget: row.sleepTarget,
                dayEndHour: row.dayEndHour,
                dayEndMinute: row.dayEndMinute,
                restDayOverride: row.restDayOverride,
                preferredBody: row.preferredBody,
                preferredMind: row.preferredMind,
                preferredHeart: row.preferredHeart,
                canvasSlots: canvasSlots,
                hasWallpaperShortcut: row.hasWallpaperShortcut,
                wallpaperShortcutUses: row.wallpaperShortcutUses,
                notifyOneMinBefore: row.notifyOneMinBefore,
                notifyWhenTimerOver: row.notifyWhenTimerOver,
                notifyCanvasReminder: row.notifyCanvasReminder,
                canvasReminderHour: row.canvasReminderHour,
                canvasReminderMinute: row.canvasReminderMinute,
                notifyDayResetWarning: row.notifyDayResetWarning,
                dayResetWarningHours: row.dayResetWarningHours,
                hasMediumWidget: row.hasMediumWidget,
                hasLargeWidget: row.hasLargeWidget
            )
        } catch {
            AppLogger.network.error("📡 Failed to load preferences: \(error.localizedDescription)")
            return nil
        }
    }
}
