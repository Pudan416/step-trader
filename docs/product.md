# Current product

Implementation is authoritative. This page describes the integrated app, not earlier proposals.
For tone and product intent, read [PRODUCT.md](../PRODUCT.md).

## Daily loop

Sleep, activity and happenings create up to 100 colors per custom day:
20 from sleep, 20 from activity and 60 from happenings. Activity currently uses
HealthKit step counts. Every day starts with 5 activity colors; measured steps
raise that amount up to 20, without adding a second grant. Sleep has a 10-color
fallback after six hours from the day boundary. Refreshing does not accumulate
extra fallback grants.

The configured day boundary can differ from calendar midnight. Existing `steps*`
and `energy*` storage names are compatibility identifiers, not a second currency.

## Surfaces

- **Canvas** — the current day's saved composition, happenings palette, artwork interaction,
  Remix, generative music and export. Historical Canvas formats remain renderable.
- **Feeds** — selected app groups, color prices and access windows. Purchases and actual
  Screen Time usage coordinate through the app, App Group and Screen Time extensions.
- **Me** — recent-week context and the archive. An empty day is not a recorded zero or a
  saved artwork. Settings opens from Me.
- **Settings** — permissions, appearance, goals, widgets/wallpaper, account and app information.
  Developer controls have separate build guards.

Canvas shows activity suggestions from Health when they are available. The
optional 20:00 reminder is off by default and opens the ordinary Canvas; it is
cancelled for the evening when the Canvas is filled. Canvas has no automatic
evening reflection card.

Onboarding introduces these surfaces in context. Its implementation lives in
`Nowhere/Views/Onboarding/`; check the current coordinator and tour transitions
when changing the sequence rather than using an old slide specification.

## Happenings field

The reviewed catalog contains **278** available definitions. `HappeningCatalog` owns
editorial IDs, English labels (at most 20 characters), browsing categories and
recommendation eligibility independently of field geometry. The original 100 IDs,
labels and tags retain their meanings. New events cover work and learning, movement,
food, rest, care, people, home, outdoors, travel, making, culture and feelings.
Custom creation and renaming remain unavailable. Retired and custom records remain
readable and removable in saved days, but cannot be added as new choices.

The list button opens the searchable catalog with category filtering and per-event
Personal settings. **All** switches the Canvas to the full two-dimensional field;
the list remains available for direct search. All 278 definitions have a position
in that field. Additions use the existing Canvas transaction: one event per day, up to ten,
six Colors per addition.

Cloud compatibility is independent of the selectable catalog. Archived custom
titles, including titles longer than 20 characters, and original event IDs remain
unchanged. Custom metadata restores page by page; shared system identities are
excluded from the globally keyed custom-activity table, including old retry
batches. Initial restoration reads the catalog, additions, snapshots and routines
successfully before applying history; an empty result succeeds, while a failed
section remains pending. Local startup must classify the installation before
seeding its day anchor. For a legacy-only account, today's additions can restore
from a saved Canvas, old option entries or category selections. A saved empty
Canvas is authoritative; upgraded accounts do not resurrect stale legacy entries.
Old category arrays and fractional timestamps remain readable.

The Canvas add control opens the compact **Personal** field around the current
day's count, such as **3 / 10**, in the Nowhere font. Worked, Chilled, Stayed home,
Had breakfast, Went for a walk and Saw a friend anchor the center. Personal choices
appear nearby. **All** expands into a pannable two-dimensional constellation of all
278 definitions. The first six roots, personal recommendations and today's events
stay close to the center; the rest fill a centered, staggered spiral in a
checkerboard-like pattern. Circle size and the day-count hub stay fixed as the
catalog grows. Existing visible positions stay fixed while the field is open;
new semantic suggestions appear in nearby empty cells. The former 100-node event
tree remains a source of semantic relationships, not a limit on the field.

Recommendations are local and deterministic. Personal shows up to eight choices,
ranked by explicit intentions and pins, recorded distinct days with a 21-day recency
half-life, a bounded old-counter fallback when there are no day snapshots, selected
interests, then optional discovery. Today's snapshot is excluded from history and
today's additions are excluded from new recommendation snapshots. Repeat additions
within a day and overlapping aliases do not increase distinct-day familiarity.
Old counters include subsequently removed choices, so the fallback is labelled
Previously chosen and never presented as an exact count of habits.

Automatic candidates are limited to two per category and two digital events. Pins
and intentions take priority over these diversity limits. A populated Personal can
include at most two discovery choices, with one place reserved when possible;
a cold start offers up to three. Each list choice explains its source. Opening the
field or the browser takes a recommendation snapshot; taps and additions do not
reshuffle that open selection. The map's geometry stays fixed until the next opening.

Personal settings are optional. A person can choose interests, pin or hide an event,
and set Observe, More often, Less often or Try it. Less often keeps logging convenient
with the explanation Tracking: less often; it does not suggest performing the action.
Hidden choices remain accessible in All and existing Canvas entries remain visible.
Reset clears all Personal preferences and excludes recorded days up to the current
custom day from future ranking; it does not erase the archive. Preferences are stored
in app-private device defaults, outside App Group, cloud payloads, analytics, day
names, widgets and exports. The open list clears old recommendation signals after a
reset and recomputes on its next opening.

Took my medicine, Went to therapy and Had my period are ordinary loggable events.
They use the same Canvas history and Supabase sync as other events. Their own
recorded history can bring them into Personal; broad discovery does not suggest them.
Masturbated is not offered as a new choice. Older saved entries remain readable and
removable from Canvas.

Habit events are available to log and use the ordinary Canvas and Supabase sync:
Got wasted, Had a hangover, Smoked a cigarette, Vaped, Drank beer, Drank wine,
Drank spirits, Used a substance and Smoked hookah. A person's own history can bring
these events into Personal recommendations. They are not included in discovery
suggestions that introduce something new to try. This rule is based on the event's
recommendation role, not a judgment about the person or habit.

Saved event history follows the ordinary Canvas and Supabase sync path; there is no
separate private event store. Older records keep their IDs and labels and remain
readable and removable. No new sexual event or sensitive day-title tag is added.

Removing the last Canvas happening clears expansion history and returns the field
to its starting state (respecting hidden choices). The cleared field survives
closing and reopening. The recommendation field and complete catalog remain
available; Personal recommendations resume after a new happening is added.

Health walking, running, swimming, dance and flexibility resolve to Went for a
walk, Went for a run, Swam, Danced and Stretched. Other documented workouts use
Worked out; cycling does not imply Biked to work. Unsupported workout raw values
do not create suggestions. A generic Worked out addition does not satisfy a
specific running or swimming suggestion. Accepting a suggestion logs its catalog
ID and reveals that same choice in Personal. Mindful-minutes and low-screen-time
signals still have no configured Health-to-catalog mapping and are filtered out.
Catalog expansion does not infer that a detected signal equals a new manual event.

The compact field retains its transparent figure assignments and interactions.
While the picker is open, a light native blur and subtle white wash soften and
lighten the Canvas artwork behind it, including in Dark Mode, so black picker
labels remain readable. Closing it restores the clear Canvas.
In the field, one tap adds an available event, while an added event requires two taps
to remove. Catalog additions can be removed through the existing Canvas controls.
New tree nodes and mode changes animate the figures, labels and hit targets together.
Reduce Motion uses the settled layout without spatial animation.

## Screen Time accounting and recovery

Purchased minutes are spent by cumulative Screen Time usage thresholds, not by
elapsed idle time. Duplicate and previous-generation events cannot spend a balance
twice. Delayed callbacks are checked against the total time since that monitoring
session started; arrival spacing is not treated as measured usage.

An impossible threshold pauses access and preserves the confirmed unused balance.
The rejected generation cannot spend further minutes. Recovery runs when the app
returns to the foreground or the user retries through the widget/Feeds, without
charging again, within the existing custom-day expiry. Healthy monitors are retained
on top-up so Apple's partial-minute usage is not reset.

Screen Time is the source of usage measurements. Local checks can reject impossible
early values, but cannot distinguish a plausible incorrect OS measurement from a
valid delayed callback. Real-device testing remains necessary after iOS updates.

## Music and artwork

The production Canvas uses native Metal artwork with versioned deterministic recipes.
New days use a seeded mix of compatible Metal catalog families. Stable actor slots
can show ordinary circles and squares, flower forms, the three directed-blur
shapes, dimpled spheres, water ripples and spiral rays. A composition uses distinct
silhouettes before repeating one. Each blur family keeps its own shape; water
ripples, spiral rays and volume spheres keep their dedicated rendering behavior.
The Soft Drift form and procedural light/flow/striped-contour fills are excluded
from new scenes. Circles remain round. Figures share a related color group, with
pigments borrowed from nearby palettes in the selected categories.
With zero automatically spent colors, there is no global scene blur. Blur
collections retain their own softness, and manual Trace overrides stay available.
The numeric pigments and mixed look order are frozen with the day. Adding or
removing an event preserves the other figures. A seeded Remix creates a new look
order; saved days keep their prior recipe version. Today's unlocked Editorial
canvas adopts the current policy after confirmed hydration, retaining event IDs,
slots, placements and manual rotations. Figures vary size, color and orientation.
Flowers retain their own contour parameters, and each material remains within its
Metal compatibility rules. Circle size varies from small to large, including the
water and spiral forms. Historical Sunset artwork remains decodable and unchanged.
Gradient stops use nearby pigments for soft transitions; directed blur retains
its corresponding silhouette and distinct color treatment.
Independent drift and bounded turns take 12 seconds; breathing takes six.
Large figures mainly drift, while smaller ones breathe more noticeably. Noir
keeps a monochrome color group. Historical recipes retain their saved policy.
An unlocked Remix changes the seeded mix of catalog looks. The background and
color group change with it, using the enabled palette categories
and coordinated figure pigments. The complete composition stays saved with the
day; Undo restores the previous composition. With only one eligible color group,
Remix keeps that group and changes its background mesh.

While music is off, new Canvas figures gently drift, breathe or turn around their
saved positions with independent phases. Idle motion pauses behind the Happenings
picker and while the Canvas is inactive; Reduce Motion disables it. Playback
smoothly hands placement to lunar physics and returns to the calm composition.

Four sound worlds and their moods are selected from the bundled catalogs. Planners
build music from the day's inputs; the playback engine owns audio execution.
The same saved day must not change because a catalog was casually reordered.
During playback, [lunar physics](features/lunar-physics-player.md) turns current figures into
a tilt-responsive, wall-bouncing ecosystem without changing the saved composition.
See [Canvas ownership](architecture/canvas-components.md) and [audio](audio.md).

## Widget and wallpaper suggestions

Widget and wallpaper offers first become eligible after cold launches 5 and 7,
respectively, after onboarding. Wallpaper also needs a saved Canvas. Suggestions
and App Store review requests share a 48-hour cooldown; at most one suggestion
appears per process session, and never together with a review request.

“Maybe later” or swipe dismissal permits one repeat after at least seven days and
Canvas visits on three distinct later calendar days. The dismissal day does not
count. Canvas must be foregrounded and visible without an intervening sheet or
handoff. A second dismissal, accepting the settings link, a confirmed widget or a
successful wallpaper export ends the corresponding automatic offer. An unknown
WidgetKit response does not prove absence. Existing v1 seen flags remain terminal;
Developer “Reset Feature Tips” clears the history.

## System integration

- HealthKit reads steps and sleep; authorization and real data vary by user/device.
- Family Controls, Device Activity and ManagedSettings implement app selection and shielding.
- App Group `group.personal-project.StepsTrader` shares state with the extensions.
- `stepstrader://` and `steps-trader://` are compatibility URL schemes.
- Authentication and cloud synchronization preserve local Canvas recovery and ownership.

Do not remove migration paths, stored values or resources just because the current
UI no longer offers them for new selections.
