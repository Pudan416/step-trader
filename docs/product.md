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

New additions use one reviewed catalog of exactly **105** events. Labels are
English, at most 20 characters, and describe complete events. Broad duplicate
meal options are replaced by Had breakfast, Had lunch and Had dinner; Cooked
means preparing food. Creating or naming custom happenings is unavailable,
including in the old chooser and empty-search states. Health detections resolve
existing catalog choices and do not add new options. Archived custom and retired
records retain their IDs and titles; they
remain renderable and removable from today's Canvas, but cannot be added again
as new choices. Personal ranks familiar events from usage metadata and restored
day history. A larger adaptive catalog remains a future step.

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

The first explicit tap on the Canvas add control offers **A few questions first**.
Six optional multi-select questions cover routine, leisure, current feelings,
habits, relationships and aspirations. Questions live in the existing Happenings
Canvas: its shared field layout, Editorial assignments and DayObjects renderer
turn native circles into the day's production objects. The headings occupy the same
measured coach surface as the surrounding tour; its position animates between
steps. Questions show no optional badge, selection counter or repeated instruction.
Leisure includes Doomscrolling, Vibe coding, Watching movies and Watching series;
these seed the existing doomscroll, made, movie and show events. Relationship and
aspiration choices use staggered 3–2–1 rows. A double tap deselects a selected
answer and accessibility activation toggles it. Back and close retain a local
account-scoped draft. Skip questions marks this introduction as skipped. Completed
answers seed preferences only: they create no history, usage counters or colors.
Relationship context never implies an actual call or text. Emotion context expires
at the logical day boundary. Existing recorded uses outrank preference seeds;
without seeds, the existing two-use-day learning threshold remains in place.

Completion reveals **All**, first six distinct domain leaders, then remaining
canonical events in relevance order, at the same map positions used for selection.
The temporary **Finding your happenings** heading disappears when the reveal ends,
along with its reserved space. The ready field has no top prompt. Actual taps
use the ordinary atomic addition/removal path and the ten-addition limit. Reduced
Motion reveals the complete field immediately. Closing or a day change cancels
the reveal. The catalog includes separate **Smoked**, **Had a beer** and **Stayed
up late** events; Had a beer never aliases Got wasted. Canvas tour cards are
suspended while questions and this first All presentation are visible. Debug has
**Happenings onboarding (Debug)** and the `debug-happenings-onboarding` launch
argument. Replay begins with a fresh survey draft and starts the complete existing
tour at welcome. The explicit + at Add happening opens questions; completion reveals
All, and a real today addition advances to the remaining Health, Feeds and Me steps.
After the questions, progression requires an explicit tap on a real happening,
including in Debug. Tapping a happening already recorded today acknowledges that
choice and continues after the palette closes, without adding or removing it,
including at the ten-addition limit. Survey completion changes recommendations
only; existing recorded happenings remain selected. The balance coach enables
the energy pill's pull gesture as well as the drawer's 44pt handle target.
Committed preferences survive cancellation until replacement answers are completed.
Recorded days and legacy onboarding completion are retained.

Subsequent uses of the Canvas add control open **Personal**: six complete events surround the current
day's added-event count, such as **3 / 10**, in the Nowhere font. A small **Today**
label sits above the count in both Personal and All. The count updates
after additions and removals. The six positions represent Work & study, Leisure & play
(including feelings), Home & everyday, Body & wellbeing, Getting around, and People
& connection. Each position shows that sphere's most familiar event; the cold-start
leaders are Worked, Chilled, Stayed home, Went for a walk, Walked to work and Saw a
friend. At the intersections, the event fits both neighboring roots: Took a break
connects Worked and Chilled, Took a nap connects Chilled and Stayed home, and Cooked
connects Stayed home and Body & wellbeing. These are associations; revealing a meal
does not log its neighbors or earlier meals. Adding an event reveals up to three
adjacent whole events. Expansion history is retained for the day. **All** reveals
the same complete map around the same count; it retains the six roots and every
option's position. Switching modes preserves the open field and the day's additions.
Direct All additions are also visible along their path when returning to Personal.
Removing the last Canvas happening clears the day's expansion history and returns
the field to Personal with only the six roots. This cleared empty state survives
closing and reopening the field; sphere leaders and Health recommendations resume
after a new happening is added. All remains available with the complete catalog.

Personal chooses one leading event per sphere, so repeated activities cannot take
over the six positions. It ranks frequency with a 21-day recency half-life and
requires two distinct use days before replacing a cold-start leader. Repeated
additions on one custom day do not increase the usage counter. Restored snapshots
canonicalize old IDs and count each event once per day; their count is combined
with local counters by the maximum, avoiding double-counting overlapping history.
Recommendations do not exclude uncomfortable events such as Raged or Got wasted.

Pending Health workout hints and today's additions are also visible along their
sphere's path. Shared intersections remain anchored. The map is recomputed on
opening and after a successful addition, then stays fixed through taps and
Personal/All switches. The radial field remains pannable.

Health walking, running, swimming, dance, flexibility, yoga and cycling resolve
to Went for a walk, Went for a run, Swam, Danced, Stretched, Did yoga and Went
cycling. Other documented workouts use Worked out; cycling does not imply Biked
to work. Unsupported workout raw values do not create suggestions. A generic
Worked out addition does not satisfy a specific activity suggestion. Accepting
a suggestion dismisses it only after its catalog event is committed to Canvas.
Mindful-minutes and low-screen-time signals currently have no honest matching
event in the fixed catalog and are filtered out rather than inventing a feeling
or another choice.

Both modes use the same transparent field, figure assignments and interactions.
While the picker is open, a light native blur and subtle white wash soften and
lighten the Canvas artwork behind it, including in Dark Mode, so black picker
labels remain readable. Labels sit directly on selected figures with a light
contrast halo, and the two-tap removal preview uses a high-contrast Delete
control. After a successful addition or removal, the close control becomes a
checkmark until the picker closes. Closing it restores the clear Canvas.
In both modes,
one tap adds an available event, while an added event requires two taps to remove.
New tree nodes and mode changes animate the figures, labels and hit targets together.
Reduce Motion uses the settled layout without spatial animation.

## Adding and editing Feeds

The Choose apps to block banner stays above the bottom navigation while the feed
list scrolls. Its height is reserved outside the scroll viewport, keeping the
last feed and expanded unlock options reachable.

Adding a feed starts with the system app picker. Continue opens a selection
preview, name and optional widget-opening choice; Change apps returns to the
picker with the draft intact. Editing starts at those details. Cancel or swipe
dismissal discards the draft without changing saved groups. Exactly one app can
leave its name blank and use the system app title. A supported selection that
includes multiple apps, categories or websites requires a group name. Website-only
blocking remains unavailable. Selecting a widget target can suggest a name for
an empty draft; changing that target preserves manually edited and existing names.

## Widget app opening

An unlocked group containing one application can reopen that app through Nowhere.
In the group editor, **Open from widget** explicitly associates the selected app
with a supported launch target. Existing groups without that association open
Nowhere until the user chooses a target. Group names never determine launch identity.
Changing the Family Controls selection clears the association; canceling the editor
does not save it. Groups with multiple apps, categories or websites open Nowhere.
Grailed uses its verified `/feed/` Universal Link, without a custom-scheme fallback.
The app and widget share one supported target catalog, including four Supercell
games. New targets use associated HTTPS routes with no browser fallback. Pinterest
uses public ID `pinterest`; older saved `com.pinterest` associations remain valid.
See [widget app opening](architecture/widget-app-opening.md) for routes and checks.

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

The app and Screen Time callbacks apply shields through one shared rebuild. Its
budget read and settings write hold the same cross-process lock as purchase
commits, so an older callback cannot reapply an obsolete shield after a purchase.
Monitor registration runs outside that lock so synchronous callbacks can finish.

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
When colors are spent, digital traces become visible earlier at low and medium
strengths. Each of the nine seeded trace styles keeps its own character; scene
displacement is stronger but remains capped, and zero strength stays unchanged.
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
