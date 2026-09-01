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
| Exact final Task 10 playback suite | 152 passed, 0 failed; selected suite time 122.576 s; includes the three added lifecycle/load gates |
| Exact final Day Objects Lab UI suite | 6 passed, 0 failed; selected suite time 104.203 s |
| Added lifecycle/load gates | 3 passed, 0 failed inside the exact final playback suite: 25 Sound cycles; 10 combined background/interruption cycles; ten Happenings 0↔10 loops plus final removal |
| Grid/VoiceOver held-Lead cancellation | 2 passed, 0 failed; each policy releases once and disables the gesture path |
| Fresh Release simulator build | `BUILD SUCCEEDED` from `/tmp/day-objects-task10-release.NjSZvy` with code signing disabled |
| Release symbol audit | No `DayObjectsMusicPlaybackEngine`, live runtime, lab controller, Rhythm/Harmony/Happening/Lead/Glitch playback symbols or Sound/Lead runtime strings found in the built app binary |
| Production Canvas/store/model import scan | No playback-type references found in `StepsTrader/Views/Canvas`, `StepsTrader/Models`, `StepsTrader/Stores`, or `StepsTrader/Services` |

The exact playback run produced repeated AudioKit simulator diagnostics,
including `kAudioUnitErr_InvalidParameter` and mono-to-stereo buffer-copy
messages, while all selected tests passed. These messages are recorded as
simulator observations only. They are not treated as proof of a physical audio
failure or as proof that physical playback is clean.

## Deterministic fixed-allocation/load evidence

| Exercise | Observed invariant |
|---|---|
| 25 Sound starts/stops | On every start: 1 transport, 1 task, 64 fake-runtime nodes, 4 active voices, 2 active Happenings, 0 pending Remix, 0 Lead voices. After every stop: transport/task/voice/Happening/pending Remix/Lead counts all 0; node allocation remains 64; session inactive. Engine start count ends at 25. |
| 10 background plus 10 interruption stops | 20 explicit starts and 20 stops; every inactive/interruption path converges to Sound off; foreground and interruption end never add a start. |
| Happenings 0↔10 | Ten full loops preserve exactly `lab-happening-01` through `lab-happening-10`; every zero state has 0 active records; final state has no active Happening record. |
| 100 Remixes | 2 allocated/prepared banks; tonal, piano, drum, node and pool counts equal baseline; 1 transport; 0 extra tasks; 0 Lead/Happening tokens; 100 old-bank recycles; 0 post-cutoff old attacks. |
| 1,000 Lead updates | 1 reserved active Lead voice, 1 amplitude attack, 1,001 control updates including begin, no envelope retrigger. |
| Grid and VoiceOver cancellation | Each repeated enable path releases the held Lead exactly once and leaves gesture audition disabled. |
| 10 active Happenings | Active voices never exceed the fixed six-voice pool; all ten IDs receive births; deterministic density bounds hold. |
| 2,000 Happening bars | Recorded attack history remains bounded and retains recent events. |
| 1,000 harmony chord changes | Tonal, piano and drum allocations remain baseline; release leaves 0 active voices, pending release tokens, tonal tokens and piano tokens. |
| 10,000 rhythm subdivisions | Drum allocation remains baseline; release leaves 0 active logical hits. |
| 10,000 transport bars | Exact integer position 160,000 subdivisions / 10,000 bars; 1 scheduling task while running, 0 after stop. |

These are deterministic simulator/fake-backend invariants. They do not measure
real-time physical CPU, memory pressure, render underruns, thermal behavior, or
perceptual balance.

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
