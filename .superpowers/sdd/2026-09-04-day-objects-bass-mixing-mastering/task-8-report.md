# Task 8 Report — Diagnostic Audition and Level Readouts

## Delivered

- Debug-only Instrumental Diagnostics provides full-composition and five role-solo modes, the four approved Bass presets in manifest order, a production `Kick + Bass` sidechain demonstration, and read-only role/master level and voice metrics. The compact UI has stable accessibility identifiers, creates no AudioKit nodes, polls the existing persistent-master metrics at 10 Hz, and remains disabled until canvas Sound is explicitly enabled.
- Solo is persistent playback-world state. Live render callbacks, continuous-plan updates, mobile structural Remix, and world reconfiguration all preserve the selected role; restoring full composition reapplies the current `LayerMixPlan` with the existing 250 ms ramp.
- The sidechain demonstration uses the active production world, selected Bass preset (or deterministic Analog Boom fallback), exactly one scheduled `.kickSoft`, exactly one retained Bass gate, and exactly one real `BassDuckCommand`. Live and mobile take one monotonic clock reading, add a bounded 80 ms lead, and submit that single future deadline through the production Bass, Rhythm, and duck paths. The lead is 3,840 frames at 48 kHz, inside Audio Unit's documented sub-4,096-frame immediate-offset window. The same injected clock reaches all three backends, so the tonal gate and drum layers enter their scheduled branches while duck automation retains the requested deadline instead of being forced immediate.
- Diagnostic Bass ownership remains capacity one: an existing transport gate is released before the bounded diagnostic token is retained, and scheduling does not allocate voices or duplicate graph nodes. If release, collapse, or expiry wins before the deadline, the tonal scheduler resets the envelope Audio Unit to clear its queued MIDI note-on before closing the gate; advancing the controlled clock through the abandoned deadline remains silent. The displayed attenuation comes from the real duck command.
- Explicit release and automatic diagnostic expiry both release the gate/token, restore and reprepare the captured composition Bass preset, reconcile transport scheduling, and permit exactly one successful Bass attack at the next valid transport event without explicit diagnostic release.
- Collapse, Sound-off, interruption, inactive scene, disappearance, and direct `releaseLayers()` invalidate pending diagnostic work and release held gates. Mobile terminal release resets both the retained outer mode and playback-world mode; stop/reprepare/start cannot resurrect a stale solo. Diagnostic actions preserve Remix seed, Steps, Sleep, Happenings, and Glitch inputs.

## TDD evidence

- The final live/mobile timing regressions first exposed the old current-time submission path: downstream production schedulers could see the supplied host time as already elapsed. They now advance an injected clock during the synchronous Bass, kick, and duck submissions and require one exact `now + 0.08` deadline plus a non-immediate production duck attack.
- The controlled production tonal-scheduler regression first failed because the exact host deadline and cancellable gate boundary did not exist. Its cancellation phase then failed with the queued open still present; the final implementation clears that event before release and produces no open render after the clock crosses the old deadline, while retaining one allocated voice and one active token.
- The automatic-expiry regression selects Hey Jakob over a BB Roy's Phaser composition, waits within a one-second bound for token release and composition reprepare, snapshots the attack count immediately before subdivision 16, and requires exactly `+1` transport Bass attack. Mutating expiry to omit its restoration plan reproduced a bounded timeout; restoring the production path made the test green.
- The mobile lifecycle regression enters a Lead solo, calls `releaseLayers()` directly, and then performs stop/reprepare/start scheduling before rendering. Removing the two production mode resets made the regression observe an isolated Lead bus; restoring them made both outer and world modes remain full composition.
- Existing controller-first tests continue to cover the four stable Bass IDs, all five role commands, explicit Sound opt-in, meter publication, selected/fallback sidechain behavior, lifecycle release, and synchronous cancellation of pending preflight.

## Verification

- Exact final timing/cancellation regressions: 4 passed, 0 failures (live and mobile shared future deadlines, exact production tonal delivery, and pre-deadline queued-gate cancellation).
- Adjacent Bass/duck/tonal-pool/drum groups: 57 passed, 0 failures, including automatic preset restoration and exactly `+1` next transport attack.
- Production bank host-time/duck scheduling checks: 2 passed, 0 failures; one start-dependent duck-reset case could not reach assertions because this simulator returned `startFailed` without an audio output device.
- Deterministic adjacent live/mobile/runtime/lifecycle slice: 6 passed, 0 failures.
- Music Lab controller lifecycle group: 29 passed, 0 failures, including synchronous collapse cancellation.
- Focused diagnostic accessibility UI test: 1 passed, 0 failures.
- Broader category/preset UI case: bounded at 75 seconds after reaching the category menu interaction; its result records cancellation only and no failed assertion.
- Debug iPhone 17 simulator build with code signing disabled: succeeded.
- `git diff --check`: passed.

## Concern

- This simulator has no default audio output device. The final adjacent selection recorded one `startFailed` before the start-dependent duck-reset assertions; both production host-time scheduling siblings, the deterministic live/mobile lifecycle slice, and all new regressions passed without a changed-code assertion mismatch.
