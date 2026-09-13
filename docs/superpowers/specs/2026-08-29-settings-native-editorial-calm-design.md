# Settings Native Editorial Calm

**Date:** 2026-08-29

## Goal

Keep the successful card-based Settings home while making every deeper settings flow feel native to iOS, calmer than the home, honest about system state, and complete under Dynamic Type, VoiceOver, Increase Contrast, and Reduce Motion.

## Approved Direction

Native Editorial Calm preserves the Nowhere identity through the energy wash, Geist typography, restrained matte surfaces, and `Your day` hierarchy. It does not replace iOS navigation, gestures, controls, or accessibility semantics with branded alternatives.

The Settings home remains:

1. compact account status;
2. prominent `Your day` summary;
3. four app destinations;
4. quiet information and developer destinations;
5. the existing philosophical footer.

The deeper the navigation level, the quieter the visual treatment becomes. Detail pages use a subdued form of the energy background, system navigation bars, system edge-swipe behavior, and consistently grouped content.

## Navigation

- The root Settings sheet uses a system large navigation title and a visible `Close` action.
- Every pushed destination uses a system inline navigation title and the system Back button.
- The full-surface custom swipe-to-dismiss gesture is removed.
- Horizontal carousels remain available where they aid recognition, but never compete with a global dismiss gesture.
- Existing feature-tip deep links to Widget and Wallpaper continue to resolve.

## Permission Truth

Permission UI distinguishes what the app knows from what it merely infers.

- HealthKit successfully returning a query — including a real zero — means data access is functioning.
- A lack of returned Health data is neutral `Check access`, not `Not granted` and not a home-level warning.
- Health unavailable on the device is `Unavailable`.
- Screen Time authorization is known and may be `Enabled` or `Action needed`.
- Notification authorization is known and may be `Allowed`, `Not requested`, or `Off in System Settings`.
- Only known, actionable problems contribute to the Settings warning badge.
- Permission failures produce visible, plain-language recovery copy; they are not log-only events.

## Appearance

Appearance begins with an explicit `Automatic / Manual` mode choice.

- Automatic shows the active daily result and the existing re-roll action. Manual controls are hidden, not merely dimmed.
- Manual reveals two groups: `Background` and `Canvas ingredients`.
- Background contains palette and gradient style.
- Canvas ingredients contains shapes, fills, and textures and may use progressive disclosure.
- Existing values and persistence keys remain authoritative; no new preference domain is introduced.
- Every selectable item exposes its label and `Selected` state to VoiceOver and uses a non-color visual indicator.
- User-facing labels use scalable styles and remain at least the semantic equivalent of Caption 2 (11 pt) at the default size.

## Notifications

The Notifications page starts with the real system authorization state.

- `Allowed` is calm and read-only.
- `Not requested` offers `Allow notifications`.
- `Off in System Settings` offers `Open Settings`.
- Reminder preferences remain persisted even when delivery is unavailable, but the page clearly states that they will not be delivered until system permission is restored.
- Copy uses the product concept `access` instead of generic timer language: `1 minute before access ends` and `When access ends`.

## Destructive Actions

- Account deletion keeps its existing confirmation and progress behavior.
- Deleting a Feed/Ticket group requires a confirmation naming the group, or a recoverable Undo. The first implementation uses confirmation for consistency and lower complexity.
- The screen remains open until the user confirms deletion.
- Failure messages are user-readable and preserve the current state.

## Detail Surfaces

- A shared detail background subdues the animated gradient so controls lead.
- Related rows sit on one shared matte grouped surface.
- Section labels, dividers, row padding, control tint, and footer copy follow one component vocabulary.
- Appearance may retain richer previews, but ordinary controls do not use glass purely for decoration.
- Wallpaper places the install CTA before optional setup details, then provides a short expandable checklist.

## Accessibility

- Minimum interactive target is 44×44 pt.
- All custom interface fonts scale relative to a semantic text style.
- No user-facing label is rendered below the semantic Caption 2 floor.
- Selection is not communicated by color alone.
- Controls with adjacent visible text use that text as their actual accessibility label.
- Reduce Motion replaces springs and move transitions with no animation or a short opacity transition.
- Increase Contrast preserves card boundaries and status meaning.

## Data and Behavior Constraints

- Do not change existing AppStorage keys, energy calculations, custom-day semantics, Supabase payloads, or sync conflict policy.
- `AppModel.updateDayEnd(hour:minute:)` remains the sole writer for the custom-day boundary.
- Signed-out users retain full access to `Your day`.
- Automatic sync remains read-only product behavior, not a toggle.
- Widget and Wallpaper standalone pages remain available for feature-tip deep links.

## Verification

- Unit tests cover permission presentation, warning contribution, appearance mode mapping, and localized summaries.
- UI tests cover Close/Back navigation, horizontal Appearance interaction, truthful permission states, Dynamic Type, selected VoiceOver state, notification authorization copy, and destructive confirmation.
- Simulator review covers Light and Dark Mode, default and accessibility text sizes, Increase Contrast, and Reduce Motion on iPhone 17.
- Hardware remains required for the final edge-swipe posture and tactile interaction check.
