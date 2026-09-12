# Day Objects generative playback — verification and performance record

**Verification date:** 2026-09-01

**Automated status:** PASS

**Physical-device status:** PENDING / UNTESTED

**Phase completion:** BLOCKED on the physical iPhone listening/performance gate

## Observed automated environment

- Host reported by xcresult: macOS 26.5.2.
- Simulator: iPhone 17 Pro, iOS 26.3.1 (23D8133), arm64.
- Xcode simulator SDK observed in build output: iPhoneSimulator 26.2.
- Source start point for Task 10: `fa94d077`.
- No physical device was connected, built to, installed on, or listened to.

## Automated results

| Gate | Observed result |
|---|---|
| Exact final Task 10 playback suite | 156 passed, 0 failed; selected suite time 198.240 s; log `/tmp/day-objects-task10-followup-final-playback.log` |
| Exact final Day Objects Lab UI suite | 6 passed, 0 failed; selected suite time 104.535 s; log `/tmp/day-objects-task10-followup-ui.log` |
| Focused review follow-up | 4 passed, 0 failed in 78.443 s: two live-runtime allocation/lifecycle tests and two integrated controller-policy tests; log `/tmp/day-objects-task10-followup-focused-green.log` |
| Existing fake command/lifecycle gates | 3 passed, 0 failed inside the baseline exact playback suite: 25 Sound command cycles; 10 combined background/interruption cycles; ten Happenings 0↔10 command-routing loops plus final removal |
| Grid/VoiceOver held-Lead cancellation | 2 integrated controller tests passed; each invokes the same policy method used by the view, forwards exactly one release to the recording playback boundary, and blocks later updates |
| Fresh Release simulator build | `BUILD SUCCEEDED` from `/tmp/day-objects-task10-followup-release.MAZIch` with code signing disabled |
| Release symbol audit | No `DayObjectsMusicPlaybackEngine`, live runtime, lab controller, Rhythm/Harmony/Happening/Lead/Glitch playback symbols or Sound/Lead runtime strings found in the built app binary |
| Production Canvas/store/model import scan | No playback-type references found in `StepsTrader/Views/Canvas`, `StepsTrader/Models`, `StepsTrader/Stores`, or `StepsTrader/Services` |

The exact playback run produced repeated AudioKit simulator diagnostics,
including `kAudioUnitErr_InvalidParameter` and mono-to-stereo buffer-copy
messages, while all selected tests passed. These messages are recorded as
simulator observations only. They are not treated as proof of a physical audio
failure or as proof that physical playback is clean.

## Deterministic fixed-allocation/load evidence

### Live runtime with real fixed bank pair

| Exercise | Observed invariant |
|---|---|
| 25 Sound-equivalent starts/stops | `DayObjectsMusicPlaybackEngine` drove an actual `DayObjectsLivePlaybackRuntime` and actual AudioKit shared bank pair/transport, with only the system audio-session boundary replaced by a recording session. A real allocation baseline was captured after graph preparation rather than hardcoded. Across all 25 cycles, node/pool counts, shared-node identities, instrument allocation fingerprints, and per-world tonal/piano/drum player allocations equaled baseline. Every stop returned the pair to prepared/not-running and left 0 transport, tasks, voices, Lead tokens, Happening tokens, and Happening records. |
| Happenings 0↔10 | With the live runtime and actual engine running from an empty Happening plan, ten add/remove loops reached the exact ten real scheduler record IDs and returned to 0 records and 0 Happening tokens each time. The aggregate ambient voice count, which also includes the still-running harmony/rhythm scene, stayed fixed after every removal and reached 0 on final stop. The same captured node/pool/fingerprint/player allocation snapshot survived every add/remove and final stop. |

This is simulator evidence for the real debug/internal runtime graph and
transport lifecycle. It does not exercise the real `AVAudioSession`, physical
audio hardware, or perceptual output.

### Controller and component boundaries

| Exercise | Observed invariant and test layer |
|---|---|
| Original 25 Sound starts/stops | Recording runtime/session only. Confirms engine command order, cumulative start accounting, and teardown convergence; it is not allocation evidence. |
| 10 background plus 10 interruption stops | `DayObjectsMusicLabController` plus recording playback. Confirms 20 explicit starts/stops, Sound-off convergence, and no automatic foreground/interruption restart; it does not run the live audio graph. |
| Original Happenings 0↔10 | Controller plus recording playback. Confirms stable Lab IDs and dedicated add/remove command routing; live scheduler allocation/removal is covered separately above. |
| 100 Remixes | 2 allocated/prepared banks; tonal, piano, drum, node and pool counts equal baseline; 1 transport; 0 extra tasks; 0 Lead/Happening tokens; 100 old-bank recycles; 0 post-cutoff old attacks. |
| 1,000 Lead updates | 1 reserved active Lead voice, 1 amplitude attack, 1,001 control updates including begin, no envelope retrigger. |
| Grid and VoiceOver cancellation | Controller plus recording playback. The tests begin a generative Lead, invoke the exact `leadAvailabilityChanged` policy method wired to both view change sites, then repeat policy/end/update calls. Each forwards exactly one `endLead` and no post-disable update. |
| 10 active Happenings | Active voices never exceed the fixed six-voice pool; all ten IDs receive births; deterministic density bounds hold. |
| 2,000 Happening bars | Recorded attack history remains bounded and retains recent events. |
| 1,000 harmony chord changes | Tonal, piano and drum allocations remain baseline; release leaves 0 active voices, pending release tokens, tonal tokens and piano tokens. |
| 10,000 rhythm subdivisions | Drum allocation remains baseline; release leaves 0 active logical hits. |
| 10,000 transport bars | Exact integer position 160,000 subdivisions / 10,000 bars; 1 scheduling task while running, 0 after stop. |

The table explicitly separates live-runtime evidence from recording/fake
boundaries and deterministic component coverage. None of these tests measures
physical CPU, memory pressure, render underruns, thermal behavior, or perceptual
balance.

## Release and product boundary

- Playback, controller, instrument-bank, and Lead surface declarations remain
  inside `#if DEBUG || INTERNAL_BUILD`.
- Release sets `ExperimentalFeatures.dayObjectsLab` to `false` and compiles the
  fallback `DayObjectsLabView` as `EmptyView`; the debug launch route remains
  under `#if DEBUG`.
- The fresh Release app binary contains no audited playback symbols/strings.
- The production Canvas/store/model/service paths contain no references to the
  playback protocol, plan, transport, scheduler, player, or lab controller.

## Pending physical observations

The following values are deliberately not reported because no physical iPhone
run occurred:

- device model and iOS build;
- CPU average/peak while Sound is on, during Lead motion, and through Remix;
- resident memory before Sound, after prepare, after 25 cycles, and after 100
  Remixes;
- thermal state and battery impact;
- audio render underruns, clicks, pops, stuck notes, and interruption behavior;
- speaker/headphone kick body, percussion variety, rhythm clarity, harmony
  movement, layer balance, Happening audibility, Lead softness, and Glitch onset;
- Metal frame pacing or visual smoothness with physical audio active.

No gains were calibrated during Task 10. Any physical balance change must be
recorded against the listening matrix and re-run through the automated suite.
