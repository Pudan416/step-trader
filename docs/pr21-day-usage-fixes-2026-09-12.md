# Daily appearance and purchased Screen Time usage

## Evidence

Diagnosis baseline: PR #21 integration `4d8150170f325ef2b35e554fc36bd62983a8aa2e`.
Published on top of `d07810ab00ab5f8e9fc07b58479b4f9f69442711`, preserving the
app-hosted background widget purchase. That path also resumes a paid failed
monitor without requiring enough colors for a new purchase.
Device custom day: Europe/Belgrade, 01:00. September 12 began at September 11 23:00 UTC.

Sanitized device preferences captured before the later purchases show a new-day
anchor, `spentStepsToday = 0`, earned/balance = 6. After two subsequent purchases,
spent = 4 and balance = 2. Those later charges do not explain the earlier visual
observation. No device credits were added or reset.

The stored interface palette did roll over, but both days were reduced to almost
identical sage colors: rounded accent RGB changed from (209, 233, 173) to
(213, 231, 178). The old resolver averaged gradient stops and mixed only 18% of
the result into one of four fixed accents. Controls now use a chromatic pigment
from the saved canvas directly, with tone/contrast adjustment. The same resolved
colors feed mounted controls and the persisted extension palette.

The day-boundary throttle could skip a necessary reset immediately after a
previous check. A regression reproduces this. The throttle now applies only when
the custom day and persisted anchor are current. Backdrop refresh resolves the
boundary before collecting metrics; queued appearance callbacks no longer replay
an obsolete day snapshot. Gallery avoids persisting bootstrap/old-day metrics.

A native Metal regression for September 12 with earned=6, spent=0 and no health
data produces identical pixels for automatic trace strength and explicitly zero
trace strength, after JSON round-trip. This verifies the automatic zero-spend
path; it does not identify the particular effect seen on the physical phone.
Physical visual confirmation is still required. Do not describe that observation
as fully resolved based on simulator output.

## Usage contract

The old purchase registered an empty event dictionary and a deadline of purchase
plus minutes. That implements elapsed time. New purchases register cumulative
DeviceActivity events for 1, 2, …, purchased usage minutes, with
`includesPastActivity: false`. The calendar schedule lasts until the custom day
boundary. Idle time does not change the persisted remaining minutes. Unspent
minutes continue to expire at the daily reset.

A generation identifies each registration. Duplicate, older and out-of-order
callbacks cannot consume a later session. Additional purchases queue behind the
current measurement segment; they do not restart its fractional usage. At most
60 events are registered per segment. Callback continuation starts the next
paid segment without another charge.

A shared file lock serializes purchase, threshold, recovery and day-setting
changes across processes. A failed recovery retains paid minutes but closes
access until monitoring succeeds. Group selection edits invalidate the old
monitor's applicability and recover against the updated tokens before unshielding.

Widgets display confirmed usage minutes. They no longer precompute clock-based
minute decrements; usage callbacks request timeline reloads. WidgetKit can delay
visible refreshes. Screen Time owns measurement and callback delivery; these APIs
do not expose a synchronous sub-minute usage reading to the host. A missing OS
monitor can be recovered from the last confirmed minute, but any unreported
fraction of a minute cannot be reconstructed exactly. Healthy monitors are never
replaced on ordinary foregrounding. Already expired legacy clock windows remain
expired on upgrade.

## Apple references

- [DeviceActivityEvent.includesPastActivity](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent/includespastactivity): false excludes usage before registration; true can include usage from the nearest preceding hour.
- [startMonitoring(_:during:events:)](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)): empty events produce interval callbacks only; replacing an activity overwrites its schedule/events; callbacks can begin immediately.
- [eventDidReachThreshold(_:activity:)](https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor/eventdidreachthreshold(_:activity:)): callback is tied to accumulated usage reaching a threshold.

## Device acceptance

After installing the published combined revision, purchase 10 min for one app,
leave it unused for more than 10 calendar minutes, then verify it still opens.
Use it for approximately 10 foreground minutes (with an idle gap) and verify the
shield returns. Check the monitor's generation-specific thresholds and stored
remaining count alongside the user's observation. Do not count a successful
install/launch or simulator tests as this physical acceptance test.
