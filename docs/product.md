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

When the Canvas is empty, one evening reflection question appears from 20:00 until
midnight in local time. It offers three happenings and the full picker; adding a
moment or dismissing the question hides it for that evening. Existing activity
suggestions take priority. The optional 20:00 notification is off by default and
is cancelled for the evening when the Canvas is filled or the question is dismissed.

Onboarding introduces these surfaces in context. Its implementation lives in
`Nowhere/Views/Onboarding/`; check the current coordinator and tour transitions
when changing the sequence rather than using an old slide specification.

## Happenings field

New additions use one reviewed catalog of exactly **100** events. Labels are
English, at most 20 characters, and describe complete events. Broad duplicate
meal options are replaced by Had breakfast, Had lunch and Had dinner; Cooked
means preparing food. Creating or naming custom happenings is unavailable,
including in the old chooser and empty-search states. Health detections and
evening reflection answers resolve existing catalog choices and do not add new
options. Archived custom and retired records retain their IDs and titles; they
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

The Canvas add control opens **Personal**: six complete events surround the current
day's added-event count, such as **3 / 10**, in the Nowhere font. The count updates
after additions and removals. The initial six are Worked, Chilled, Stayed home,
Had breakfast, Went for a walk and Saw a friend. Each has one catalog identity,
including those promoted from outer positions. The six roots remain fixed. At the intersections,
the event fits both neighboring roots: Took a break connects Worked and Chilled,
Took a nap connects Chilled and Stayed home, and Cooked connects Stayed home
and Had breakfast. These are associations; revealing a meal does not log its
neighbors or earlier meals. Adding an event reveals up to three adjacent whole events.
Expansion history is retained for the day. **All** reveals the same complete map
around the same count; it retains the six roots and every option's position.
Switching modes preserves the open field and the day's additions. Direct All additions
are also visible along their path when returning to Personal.

Personal pre-reveals up to three familiar events beside the six roots. It ranks
frequency with a 21-day recency half-life, requires two use days, and excludes
the six roots from extra recommendations. Repeated additions on one custom day
do not increase the usage counter. Restored snapshots canonicalize old IDs and
count each event once per day; their count is combined with local counters by
the maximum, avoiding double-counting overlapping history. Recommendations do
not exclude uncomfortable events such as Raged or Got wasted.

Current Health workout hints and today's additions are also visible. The first
recommendation in each sector moves to that root's nearest outward position;
remaining recommendations reveal their paths. Shared intersections remain
anchored. The map is recomputed on opening and then stays fixed through taps
and Personal/All switches. The radial field remains pannable.

Health walking, running, swimming, dance and flexibility resolve to Went for a
walk, Went for a run, Swam, Danced and Stretched. Other documented workouts use
Worked out; cycling does not imply Biked to work. Unsupported workout raw values
do not create suggestions. A generic Worked out addition does not satisfy a
specific running or swimming suggestion. Accepting a suggestion logs its catalog
ID and reveals that same choice in Personal. Mindful-minutes and low-screen-time
signals currently have no honest matching event in the fixed catalog and are
filtered out rather than inventing a feeling or another choice.

Both modes use the same transparent field, figure assignments and interactions.
While the picker is open, a light native blur and subtle white wash soften and
lighten the Canvas artwork behind it, including in Dark Mode, so black picker
labels remain readable. Closing it restores the clear Canvas.
In both modes,
one tap adds an available event, while an added event requires two taps to remove.
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
New days share one of six shape families: circles, organic blobs, squares,
four-lobe clovers, flowers or directed light beams. A calendar shuffle avoids
consecutive repeats. Figures share a family and a related color group, with
pigments borrowed from nearby palettes in the selected categories. The numeric
pigments are frozen with the day. Adding or removing an event preserves the
other figures. Triangle and hexagon days
are excluded from new generation, while historical artwork retains its saved
appearance. Today's unlocked Editorial canvas adopts the common family even
if it was started before this policy, retaining its added events and saved
placements and manual rotations. Figures vary their contours and orientations
within that family: flowers keep one petal count and squares keep one daily mode.
Today's unlocked Canvas upgrades its generated contours and initial angles once;
manual poses and historical artwork remain saved. The selected A appearance mixes one-tone fills,
outlines and soft two-color shading, with approximately a 2.7-fold diameter
range. Directed beams retain their diffuse silhouette and a larger size floor.
Independent drift and bounded turns take 12 seconds; breathing takes six.
Large figures mainly drift, while smaller ones breathe more noticeably. Noir
keeps a monochrome color group. Historical recipes retain their saved policy.
An unlocked Remix selects a different shape family from the previous composition,
with every figure sharing that family. All six families remain available. The
background and color group change with it, using the enabled palette categories
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
