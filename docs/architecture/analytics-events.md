# Analytics event contract

`user_analytics_events` stores one row per event. Event context that applies to
every row lives in columns; event-specific, privacy-reviewed fields live in the
`properties` JSON object.

## Version 3 context

- `event_stage`: `onboarding`, `navigation`, `canvas`, `access`, `adoption`,
  `sync`, `reliability`, or `product`.
- `schema_version`: event envelope version. Version 1 is assigned to queued
  events written by older app builds; the structured context uses version 3.
- `app_version`, `app_build`, `os_version`, `device_model`, `session_id`:
  release and runtime context for comparing behavior across app sessions and
  device classes.
- `identity_type`: whether the account was anonymous or registered when the
  event occurred. The queued event also keeps that moment's `user_id`; it is
  uploaded only while that same account is active.
- `properties`: event-specific string fields. Never include custom titles,
  HealthKit values, account identifiers, or Canvas element IDs.

Current stage examples include `tab_switched` (navigation),
`happening_added` / `canvas_viewed` (canvas), `experience_spent` /
`ticket_created` (access), `sync_failed` (sync), and `app_diagnostic`
(reliability). `tab_switched.selection_latency_ms` measures time spent in the
selection handler; it is not a frame-time or rendered-transition measurement.

The first-launch tour emits `onboarding_started` (or `onboarding_resumed`),
`onboarding_step_reached`, and `onboarding_completed` / `onboarding_skipped`.
Step names and flow version are stable labels; tutorial replays are excluded.
`widget_added` / `widget_removed` are emitted when WidgetKit's installed
inventory changes, with only widget kind, family, and count. The first inventory
read seeds a baseline, so widgets already installed are not reported as new.

The client keeps its offline event queue and event IDs. Deploy the matching SQL
migration before shipping a client that writes structured context columns. Existing
clients continue to write because the new columns have defaults. RLS remains
scoped to the authenticated user's own rows.
