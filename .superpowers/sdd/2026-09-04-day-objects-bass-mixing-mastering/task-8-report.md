# Task 8 Report — Diagnostic Audition and Level Readouts

## Delivered

- Debug-only Instrumental Diagnostics provides full-composition and five role-solo modes, the four approved Bass presets in manifest order, a production `Kick + Bass` sidechain demonstration, and read-only role/master level and voice metrics. The compact UI has stable accessibility identifiers, creates no AudioKit nodes, polls the existing persistent-master metrics at 10 Hz, and remains disabled until canvas Sound is explicitly enabled.
- Solo is persistent playback-world state. Live render callbacks, continuous-plan updates, mobile structural Remix, and world reconfiguration all preserve the selected role; restoring full composition reapplies the current `LayerMixPlan` with the existing 250 ms ramp.
- The sidechain demonstration uses the active production world, selected Bass preset (or deterministic Analog Boom fallback), exactly one scheduled `.kickSoft`, exactly one retained Bass gate, and exactly one real `BassDuckCommand`. A production tonal/pool scheduling boundary now opens the Bass envelope at the same audio host time as the kick and duck; the integration test observes that time at the recording pool/backend rather than through result metadata.
- Diagnostic Bass ownership remains capacity one: an existing transport gate is released before the bounded diagnostic token is retained, and scheduling does not allocate voices or duplicate graph nodes. The displayed attenuation comes from the real duck command.
- Explicit release and automatic diagnostic expiry both release the gate/token, restore and reprepare the captured composition Bass preset, reconcile transport scheduling, and permit exactly one successful Bass attack at the next valid transport event without explicit diagnostic release.
- Collapse, Sound-off, interruption, inactive scene, disappearance, and direct `releaseLayers()` invalidate pending diagnostic work and release held gates. Mobile terminal release resets both the retained outer mode and playback-world mode; stop/reprepare/start cannot resurrect a stale solo. Diagnostic actions preserve Remix seed, Steps, Sleep, Happenings, and Glitch inputs.

## TDD evidence

- The production scheduling integration test first failed because no scheduled Bass gate reached the recorder, and the lower tonal-pool test first failed to compile because the host-time API did not exist. The minimal protocol/pool/backend boundary made both tests green while retaining one allocated voice and one active token.
- The automatic-expiry regression selects Hey Jakob over a BB Roy's Phaser composition, waits within a one-second bound for token release and composition reprepare, snapshots the attack count immediately before subdivision 16, and requires exactly `+1` transport Bass attack. Mutating expiry to omit its restoration plan reproduced a bounded timeout; restoring the production path made the test green.
- The mobile lifecycle regression enters a Lead solo, calls `releaseLayers()` directly, and then performs stop/reprepare/start scheduling before rendering. Removing the two production mode resets made the regression observe an isolated Lead bus; restoring them made both outer and world modes remain full composition.
- Existing controller-first tests continue to cover the four stable Bass IDs, all five role commands, explicit Sound opt-in, meter publication, selected/fallback sidechain behavior, lifecycle release, and synchronous cancellation of pending preflight.

## Verification

- Exact new regressions: 4 passed, 0 failures (production host-time integration, tonal-pool forwarding/capacity, automatic expiry/next attack, and mobile direct-release lifecycle).
- Adjacent Bass/duck/tonal-pool groups: 38 passed, 0 failures.
- Deterministic adjacent live/mobile/runtime/lifecycle slice: 7 passed, 0 failures.
- Instrument audition and Music Lab controller groups: 56 passed, 0 failures.
- Focused diagnostic accessibility UI test: 1 passed, 0 failures.
- Broader category/preset UI case: bounded at 75 seconds after reaching the category menu interaction; its result records cancellation only and no failed assertion.
- Debug iPhone 17 simulator build with code signing disabled: succeeded.
- `git diff --check`: passed.

## Concern

- This simulator has no default audio output device. The adjacent Instrument Bank aggregate completed 29 of 44 tests before 15 uniform `startFailed` failures; the broader playback-engine run completed 30 tests before the same audio-environment failures/restarts and cancellation. The deterministic live/mobile lifecycle slice and all new regressions pass, and neither aggregate exposed a changed-code assertion mismatch.
