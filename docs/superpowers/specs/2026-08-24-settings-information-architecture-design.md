# Settings Information Architecture Redesign

**Date:** 2026-08-24

## Goal

Make Settings understandable at a glance and remove the accidental dependency
between authentication and personal daily preferences. Step goal, sleep goal,
and custom-day boundary must be available to every user, including someone who
has never signed in.

The approved visual direction is the card-based concept: a compact account
status card at the top, a larger `Your day` summary card beneath it, a two-column
grid of product settings, and a compact information group at the bottom.

## Product principles

- Authentication controls identity and automatic cross-device sync. It does not
  unlock local preferences.
- The user's day is the primary settings task even though account status appears
  first.
- Cards summarize state before asking the user to navigate.
- Similar destinations share one visual treatment and one interaction model.
- Account management contains only identity, sync explanation, sign out, and
  deletion.
- Existing local persistence, calculations, permissions, and sync behavior stay
  authoritative; this redesign changes their presentation and navigation.

## Settings home

The screen keeps the existing energy-gradient background and large `Settings`
title. Content appears in this order:

```text
Settings

[ Account status                                      > ]

[ Your day                                              ]
[ 10,000 Steps | 8 h Sleep | 12:00 AM New day          ]
[ Goals & schedule                                    > ]

[ Appearance       > ]  [ Notifications             > ]
[ Permissions    1 > ]  [ Widgets & wallpaper       > ]

[ Notes from Kosta                                    > ]
[ About                                               > ]

[ Developer                                           > ]  DEBUG only
```

### Account status card

Signed-in state:

- avatar image or initials;
- current display name;
- subtitle `Automatic sync on`;
- chevron to the Account page.

Signed-out state:

- Apple symbol;
- title `Sign in with Apple`;
- subtitle `Sync settings and history across devices`;
- tapping presents the existing login flow directly instead of opening an empty
  Account page.

The card is visually compact. Its purpose is orientation and sync status, not
to dominate the screen.

### Your day card

This is the largest card and the primary visual anchor. It shows three current
values read from existing local state:

- daily step target;
- sleep target in hours;
- the configured time at which a new custom day begins.

The bottom action row is titled `Goals & schedule`. The whole card is one
navigation target and opens the existing energy-settings experience, renamed
from `Limits` to `Your day`.

The values are summaries, not independent buttons. This avoids ambiguous hit
targets and keeps VoiceOver navigation predictable.

### Settings grid

Four equal cards form a two-column grid:

1. `Appearance` opens the existing appearance page.
2. `Notifications` opens the existing notifications page.
3. `Permissions` opens the existing permissions page and displays a text or
   numeric warning badge when action is needed.
4. `Widgets & wallpaper` opens one combined detail page containing the current
   widget and wallpaper settings as sections on a single scroll surface. It is
   not an intermediate menu that adds another navigation level.

On narrow widths or accessibility Dynamic Type sizes, the grid becomes one
column. Cards use the same corner radius, outline, icon treatment, pressed
state, and minimum height.

### Information and developer tools

`Notes from Kosta` and `About` remain a compact two-row group below the grid.

Debug tools no longer expand inline on the main page. In `DEBUG` builds, one
`Developer` row appears at the bottom and opens a dedicated page containing the
existing diagnostics and reset actions. Release builds contain no developer
entry.

## Your day detail page

`SettingsEnergyPage` becomes the sole settings UI for:

- daily step goal;
- sleep goal;
- start of the next custom day.

The page title changes from `Limits` to `Your day`. The current controls and
immediate-apply behavior remain. There is no Save button and no authentication
check.

The duplicate goal and custom-day controls are removed from the profile editor.
The backing values continue to use the existing app-group `AppStorage` keys so
widgets, extensions, calculations, and signed-out sessions see the same data.

Changing goals continues to recalculate daily energy. Changing the custom-day
boundary continues to route only through `AppModel.updateDayEnd` so the existing
re-anchor and reset safeguards remain intact.

## Account detail page

The signed-in account card opens a dedicated Account page with four areas.

### Identity

- avatar/photo;
- display name or nickname;
- Apple-managed email shown read-only;
- the existing photo-library and profile-save behavior.

Profile edits retain explicit Save and Cancel actions because they perform a
network operation that can fail. Local daily settings are not shown here.

### Automatic sync

The page states that settings and history sync automatically across the user's
devices. Sync is read-only product behavior, not a toggle.

The first version displays `Automatic sync` with value `On`. It does not display
`Up to date` or `Last synced` because the current sync service does not expose a
reliable user-facing completion timestamp. This avoids presenting invented
precision. Adding live progress, retry, and last-success state is separate
future work.

Signing in triggers the existing Supabase synchronization workflow. Signing out
stops authenticated sync but does not delete or disable locally stored goals.
This redesign does not change the existing server/local conflict policy.

### Session action

`Sign out` is a standard account action with the existing behavior.

### Destructive action

`Delete account` is visually separated from sign out, retains confirmation, and
keeps existing failure reporting.

## Component boundaries

### `SettingsSheet`

Owns the home-screen ordering and navigation. It selects signed-in or signed-out
account-card content from `AuthenticationService` and reads summary values from
the existing local stores. It does not implement goal editing or sync logic.

### Reusable card components

Add focused components for:

- account status;
- Your day summary;
- square settings destination;
- grouped information rows.

These components own layout and accessibility semantics only. Destinations and
business actions remain with their parent screens.

### `SettingsEnergyPage`

Remains the single owner of the three daily preference controls and their
existing model callbacks.

### Account page

The current profile-editing functionality is reshaped into an Account page.
Identity edits may remain isolated in the existing editor or a focused child
view, but goal controls must not remain in either account surface.

### Widgets and wallpaper page

The existing widget and shortcut UI is composed into one scrollable detail
screen. Each section keeps its current state bindings and side effects. Shared
subviews should be extracted only where required to compose the page; unrelated
settings refactors are out of scope.

### Developer page

The existing `#if DEBUG` diagnostics move without behavior changes to a focused
destination. Destructive debug actions keep their current confirmation and
feedback behavior.

## State and data flow

```text
App-group UserDefaults
    ├── step target ────────┐
    ├── sleep target ───────┼──> Your day summary
    └── day boundary ───────┘           |
                                      tap
                                       v
                              SettingsEnergyPage
                                       |
                         existing AppModel callbacks

AuthenticationService ──> account card state ──> login or Account page
                                       |
                                signed-in session
                                       v
                           existing Supabase sync
```

Signed-out changes are applied locally immediately. Authentication is never
consulted before displaying or editing the Your day values.

## Error and empty states

- A missing avatar falls back to initials.
- A missing display name falls back to the current user-display-name behavior.
- A denied photo-library request keeps the existing alert.
- Profile-save and account-deletion failures keep explicit error alerts.
- Background sync failure never blocks local editing. The UI says sync is on,
  not that every write has completed.
- Permission issues use both a label/badge and color; color alone never conveys
  the state.
- If a summary value is absent, the same defaults used by the energy model are
  displayed, preventing blank or contradictory UI.

## Accessibility

- Every card has a minimum 44-point hit target; grid cards should be at least
  120 points tall at default type size.
- Each card is exposed as one accessibility element with its title, relevant
  value, and `button` trait.
- The Your day card announces all three values in a predictable order.
- Decorative icons are hidden from VoiceOver.
- Warning states include spoken text such as `Action needed`.
- Dynamic Type may increase card height and collapse the grid to one column;
  text must not truncate critical status or values.
- Text and card outlines maintain readable contrast over the brightest part of
  the energy gradient.
- Reduce Motion uses the existing navigation and pressed-state behavior without
  adding card-scale or parallax animation.

## Localization and copy

All new copy is added to the string catalog. The source-language labels are:

- `Your day`
- `Goals & schedule`
- `New day`
- `Automatic sync on`
- `Sign in with Apple`
- `Sync settings and history across devices`
- `Widgets & wallpaper`
- `Automatic sync`
- `Settings and history sync automatically across your devices.`
- `Developer`

Metric formatting uses locale-aware number, duration, and time formatting. The
summary must not hard-code 12-hour time or English separators.

## Verification

- A signed-out user can open Your day and change all three values.
- Relaunching while signed out preserves the changed values.
- Signing in or out does not hide, reset, or disable Your day.
- The signed-in card opens Account; the signed-out card opens Login directly.
- Account contains no daily-goal or day-boundary controls.
- No sync toggle exists on either screen.
- The Your day summary updates after returning from its detail page.
- Goal changes still recalculate energy, and day-boundary changes still use the
  single-writer update path.
- Permission warning state is visible and accessible.
- Appearance, Notifications, Permissions, Widgets & wallpaper, Notes, and About
  navigate to the intended destinations.
- Widget and wallpaper controls retain their existing behavior on the combined
  page.
- Debug builds expose one Developer destination; release builds expose none.
- VoiceOver, Dynamic Type, light/dark app themes, signed-in/signed-out states,
  permission-warning states, and compact iPhone widths receive simulator review.

## Out of scope

- changing authentication providers;
- adding a manual sync switch, manual sync button, or sync-history interface;
- changing the server/local preference conflict policy;
- adding subscription or billing management to Account;
- redesigning the destination pages beyond the composition needed for Your day,
  Account, Widgets & wallpaper, and Developer;
- changing energy calculations, custom-day semantics, or permission behavior;
- shipping generated mockup images as application assets.
