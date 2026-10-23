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
Health refreshes publish and cache only their current logical day's latest result;
late responses from a previous refresh, observation session or day are discarded.

## Surfaces

- **Canvas** — the current day's saved composition, happenings palette, artwork interaction,
  Remix, generative music and export. Historical Canvas formats remain renderable.
- **Feeds** — selected app groups, color prices and access windows. Timed passes and
  Screen Time access coordinate through the app, App Group and Screen Time extensions.
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

New additions use one reviewed catalog of exactly **106** events. Labels are
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
aspiration choices use staggered 3–2–1 rows. Routine and habit answers describe
ongoing activities, while feelings, people and aspirations describe their own
contexts. A tap on a selected answer previews deselection with a monochrome
figure and Delete badge; another tap confirms. Accessibility uses the same
selection and confirmation sequence. Back and close retain a local
account-scoped draft. Skip questions marks this introduction as skipped. Completed
answers seed preferences only: they create no history, usage counters or colors.
Relationship context never implies an actual call or text. Emotion context expires
at the logical day boundary. Existing recorded uses outrank preference seeds. Outward suggestions can reflect
one recorded day; the six actionable starter events remain fixed.

Completion reveals **All**, first the six actual starter events, then remaining
canonical events in relevance order, at the same map positions used for selection.
The same framed coach displays **Choose one thing you’ve done today.** throughout
the reveal and while scrolling or exploring the field, until an explicit real
happening choice. One immutable reveal clock scales circles and their labels in
their final cells; the complete scroll world, coach reservation and Today hub
keep the same geometry at completion. The unchanged production scene is reused
between animation samples. Actual taps use the ordinary atomic addition/removal
path and the ten-addition limit. Reduced Motion reveals the complete field immediately. Closing or a day change cancels
the reveal. The catalog includes separate **Smoked**, **Had a beer**, **Had a
drink**, **Got drunk** and **Stayed up late** events. Beer, a general alcoholic
drink and intoxication retain separate identities and counters. Got drunk keeps
the existing `event_wasted` identity; saved copy and entries are retained. Habit
preferences include Drinking alcohol and Getting drunk; a historical beer answer
keeps its beer-only meaning. Canvas tour cards are
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

Subsequent uses of the Canvas add control open **Personal** with six actual
happenings: **Worked**, **Chilled**, **Stayed home**, **Went for a walk**,
**Had coffee**, and **Saw a friend**. These are actionable starter events for
work, rest, home, movement, food and drink, and people. The shared native field
and DayObjects renderer surround the current day's added-event count, such as
**3 / 10**, with a small **Today** label above it. Tapping an available starter
records that event once through the ordinary addition path and reveals up to
three relevant neighboring events in the same continuous field. Further actual
event additions unfold their neighbors. There are no category screens or Back
controls. The six starters remain stable even with a familiar usage profile.

Outward suggestions rank once when the field opens, within their domains, using
frequency with a 21-day recency half-life. Restored snapshots canonicalize aliases
and count each event once per day, combined with local counters by their maximum.
Recorded usage ranks before survey preferences; unused choices retain a
deterministic useful order. Rest and leisure share a direction; travel remains
with everyday life. Ranking changes suggestion occupants without changing the
six starters, catalog identities, or saved artwork. Health suggestions and today's
added events reveal their canonical paths without logging extra events.

**All** retains the complete 106-event atlas and the first onboarding reveal.
Personal and All use the same opening atlas, native cells and authoritative
assignment snapshot, including frozen actors for today's saved UUIDs. Their
positions stay fixed during additions, deletion previews, removals and mode
switches. Expansion consumes the opening map without rereading history or
ranking the catalog again. Reopening ranks suggestions again and restores that
day's expanded paths; a day change clears those paths. Authentication changes
close the field and clear the previous account's expansion state.

Actual event taps retain the existing atomic addition/removal path and ten-addition
limit. Removing the final event resets Personal visibility to its six starter
events while retaining the opening atlas and native actor assignments. The native
field remains pannable. During the first All introduction, switching to Personal
uses the same actual events and retains the first-choice coach; only an explicit
real event tap completes that step. Survey answers never log events.

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
The full visible Delete capsule confirms that same event, including its edges;
its hit region follows the capsule and rises above neighboring hit targets with
the preview figure. Panning is retained through field layout updates. Automatic
focus applies after a layout transition without a second scroll animation, and
waits while a removal preview is armed. The initial All reveal focuses its fixed
Today hub immediately so it does not jump when the reveal finishes.
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

## Timed access passes

Colors buy 10, 30 or 60 minutes of wall-clock access to a feed group. The timer
starts after payment and keeps running while Nowhere is closed, the phone is locked
or the selected apps are unused. A group has one active pass at a time; another
purchase is available after it expires. Passes are independent of the custom day
reset.

An active pass applies to the group's current app, category and website selection.
Adding a selection while the pass is active opens it for the remaining time;
removing one stops including it. A paid pass overrides overlapping group and legacy
blockers for the same selected tokens. Paid apps remain exceptions to other category
shields.

The app stores one start time and deadline in the App Group. DeviceActivity monitors
that deadline with no usage-threshold events, and the app and extensions rebuild
shields through the shared cross-process lock. Old usage-budget balances are cleared
on first launch after the change. The widget shows the system timer text and also
gets a timeline entry at the deadline; WidgetKit may apply that entry later.

DeviceActivity delivers interval callbacks when the device is used during or after
the scheduled interval. Screen Time re-shielding at the deadline must be checked on a
physical device, especially after the phone has stayed locked past expiry.

## Music and artwork

The production Canvas uses native Metal artwork with versioned deterministic recipes.
New days use a seeded mix of compatible Metal catalog families. Stable actor slots
can show ordinary circles and squares, flower forms, the three directed-blur
shapes, dimpled spheres, water ripples and spiral rays. A composition uses distinct
silhouettes before repeating one. Each blur family keeps its own shape; water
ripples, spiral rays and volume spheres keep their dedicated rendering behavior.
The Soft Drift form and procedural light/flow/striped-contour fills are excluded
from new scenes. Circles remain round. Figures share a related color group, with
pigments borrowed from nearby palettes in the selected categories. New and
remixed recipes increase pigment chroma while keeping each hue recognizable;
saved recipes without that policy version keep their original colors.
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
