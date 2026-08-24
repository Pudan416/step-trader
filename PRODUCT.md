<!-- impeccable:product-schema 1 -->

# Nowhere

## Platform

ios

## Users

People who want to spend less of their life inside their phone and notice more of the day they actually lived. They may still value health signals and app-use boundaries, but they do not want another quantified-self dashboard.

## Product Purpose

Nowhere helps a person exchange real-world actions for a limited creative resource, then turn that resource into a personal visual trace of the day. The product should make stepping away from the phone feel constructive and expressive rather than punitive.

The Me surface is a personal archive for brief reflection: remember the last week, revisit days that left a trace, and see gentle context about how those days were lived. It is not primarily an analytics or profile screen.

## Positioning

Nowhere is a quiet anti-compulsion companion and visual diary, not a conventional screen-time blocker, fitness tracker, or productivity dashboard. Its differentiated mechanism is that lived activity and intentional restraint become colors and marks on a daily canvas.

## Operating Context

- Used in short mobile sessions throughout the day, often around moments of choosing whether to open distracting apps.
- The Me surface is most useful during a calm evening or weekly reflection.
- A person may not open the app for several consecutive days. Missing app activity must never be presented as a recorded zero or as a saved day.
- The current calendar week context and the long-term archive serve different jobs and should be modeled separately.

## Capabilities and Constraints

- A daily canvas exists as the default working surface, but an archived day only exists when there is a meaningful persisted trace.
- The recent-week strip represents the latest seven calendar days, including empty days, so it stays aligned with the seven-day context above it.
- Empty recent-day cards communicate absence honestly; they are not archive records and should not imply failure.
- The full archive contains only days with a real saved trace.
- Health and activity data can be incomplete, unavailable, or delayed. Unknown data must remain unknown rather than becoming zero.
- The interface must remain usable with Dynamic Type, VoiceOver, increased contrast, and reduced transparency.

## Brand Commitments

- Calm, humane, and non-judgmental.
- Expressive and tactile without becoming decorative noise.
- Honest about what was and was not recorded.
- Personal memory before performance measurement.
- Native to iOS while retaining a distinctive hand-made visual character.

## Evidence on Hand

- Existing SwiftUI implementation in `StepsTrader/Views/MeView.swift`, `StepsTrader/Views/MeViewSupport.swift`, `StepsTrader/Views/Me/MeCalendarStrip.swift`, and `StepsTrader/Views/Me/MeWeekStats.swift`.
- Simulator review of the Me surface, full calendar, and saved-day viewer.
- Current implementation always creates a seven-calendar-day strip, while persisted snapshots and rendered canvases can diverge.
- User-confirmed product direction: Me is a personal archive for short reflection, not an analytics dashboard.
- User-confirmed data rule: the recent strip always shows the last seven calendar days as seven cards, even when six or seven are empty; the full archive shows only real saved traces.

## Product Principles

1. Show time honestly. A calendar slot can exist without pretending a record exists.
2. Preserve traces, not scores. The canvas is the primary memory object; metrics provide context.
3. Separate recent rhythm from lasting archive. Seven calendar days explain the week; saved traces build the collection.
4. Reward return without punishing absence. Empty days are quiet space, not broken streaks.
5. Prefer recognition over interpretation. A person should understand a day's state and tap result before interacting.

## Accessibility & Inclusion

- Never communicate saved, empty, selected, or unavailable states by color alone.
- Maintain legible text and touch targets at accessibility sizes.
- Support reduced transparency without losing hierarchy or state meaning.
- Use language that avoids shame, streak anxiety, and moral judgment about inactivity or app use.
