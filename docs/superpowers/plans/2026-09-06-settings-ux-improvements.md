# Settings UX improvements implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement and review bounded tasks.

**Goal:** Implement the UX/UI improvements approved in the Settings design review.
**Architecture:** Keep current SwiftUI navigation and preference stores. Appearance edits use a local draft and one Apply action; other settings remain immediate. Preview work must not change the actual Canvas renderer or audio.
**Tech Stack:** SwiftUI, UserDefaults, XCTest, existing Metal/Canvas preview rendering.
**Spec:** The approved Settings UX/UI review in this conversation, 2026-09-06.

## Global constraints
- Work only in `.worktrees/current-integration`; preserve existing WIP including localization edits, Smudge, audio and Day Objects.
- No commits, push, merge or installation as part of this pass.
- Maintain accessibility identifiers where semantics remain applicable; update obsolete UI tests.
- No fabricated sync or installation success. Use real evidence or explain verification honestly.
- Use localizable English source strings; preserve existing translations.

## Task 1: Goals and day schedule
Files: SettingsEnergyPage.swift, StepGoalDrumPicker.swift, SleepGoalArcPicker.swift and relevant tests.
- [x] Replace per-digit step editing with a whole-value stepper at 500 steps and precise numeric entry, preserving range.
- [x] Keep sleep +/- and compact native time selection with existing allowed day-boundary range. Honor locale in both hub and detail.
- [x] Explain goals' effect on Canvas; standardize goals and day-start labels; do not mutate day boundary on mere opening.
- [x] Test step bounds/increments, day-boundary persistence and accessible interactions.

## Task 2: Permissions, widget/wallpaper and account trust
Files: SettingsPermissionPresentation.swift, SettingsPermissionsPage.swift, NotificationSettingsView.swift, AppModel.swift (permission warning only), SettingsWidgetPage.swift, SettingsShortcutPage.swift, SettingsAccountPage.swift and tests.
- [x] Make missing notification warnings depend on enabled reminders; show consequence and keep Health manage access available.
- [x] Present wallpaper setup as visible install/automation/check steps. Do not claim system automation is installed from a file's existence.
- [x] Add widget-add instructions, representative content preview, actionable wallpaper setup link.
- [x] Distinguish sync enabled from verified sync status using existing state if available; otherwise honest explanatory copy.
- [x] Cover warning-policy cases and recovery navigation.

## Task 3: Appearance and Settings hub
Files: SettingsAppearancePage.swift, SettingsHomeCards.swift, SettingsSheet.swift, new appearance draft/preview support and Help page if needed.
- [x] Capture current preferences into a draft on entry; all palette/style/mode/ingredient choices modify only the draft. Apply writes once; Cancel/back discards. Protect accidental dismissal of an edited draft.
- [x] Use visual style cards, selected-style preview and explanatory copy. Draft automatic reroll must not mutate stored theme until Apply.
- [x] Reduce home card empty space, show current summaries, label goals clearly and provide Help & feedback while retaining Notes.
- [x] Add behavior tests for apply/discard and update affected navigation tests.

## Task 4: Integrated verification
- [x] Review each task diff for scope and behavior, then review combined diff.
- [x] Build and run targeted unit/UI tests, capture default/light/accessibility screenshots and inspect visual layout.
- [x] Record remaining limits; leave all changes reviewable in the worktree.
