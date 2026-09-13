# Day Objects Happening Bank Retimbre Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the rejected Happening sample bank with thirty clearly distinct, chord-safe ambient one-shots whose loudness, transient sharpness, and shared effects remain comfortable on an iPhone speaker and headphones.

**Architecture:** Keep the existing thirty recipe IDs, 102 processed assets, chord resolver, four-player Happening pool, one AudioKit engine, and one final limiter. Move timbral identity into deterministic offline attack/body/tail renders, master each event by perceived energy instead of independent peak normalization, and leave only quiet glue effects in the live graph.

**Tech Stack:** Python 3 standard library offline DSP and WAV rendering, JSON source and asset manifests, Swift 6, AudioKit 5, AVFAudio, XCTest, Xcode 26, `xcrun devicectl`.

**Spec:** `docs/superpowers/specs/2026-09-02-day-objects-happening-bank-retimbre-design.md`

## Global Constraints

- Work only on branch `codex/day-objects-generative-audio` in `.worktrees/day-objects-generative-audio`; do not merge, push, publish, or modify `main`.
- Preserve the user-owned changes in `docs/superpowers/specs/2026-08-30-day-objects-native-instrument-bank-design.md` and `docs/day-objects-instrument-bank-listening-checklist.md`; never stage either file.
- Keep exactly thirty stable IDs and exactly 102 processed assets: four roots for tonal IDs `01–24`, one source asset for each texture ID `25–30`.
- Keep the aggregate Happening bundle at or below 30 MiB and decoded buffers at or below 48 MiB.
- Keep one `DayObjectsAudioRuntime`, one final limiter, and the existing shared four-voice Happening pool.
- Retain VCSL only at revision `c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e` under CC0-1.0, for IDs `09`, `10`, `11`, `17`, and `18`.
- Add no Splice, account-bound, generated-service, or unverified third-party audio.
- Render mono, 44.1 kHz, 16-bit PCM WAV files with duration `0.12...6.0` seconds and deterministic bytes.
- Enforce a sample peak at or below `-6 dBFS`; tonal and organic audible-event RMS `-22...-18 dBFS`; texture RMS `-26...-21 dBFS`; sensitive 50 ms onset RMS at or below `-15 dBFS`; DC at or below `-50 dBFS`.
- Keep `17–18` at least 4 dB down above 5.5 kHz with a rendered low-pass ceiling no higher than 7.5 kHz.
- Render each recipe-specific tail offline. Runtime delay, feedback, and plate reverb remain conservative glue.
- Implement every production change test-first and commit only the files named by that task.

## File map

- Create `Scripts/day_objects_audio/happening_audio_metrics.py`: PCM measurement, loudness targeting, onset/peak/DC gates, and comparison fingerprints.
- Create `Scripts/day_objects_audio/happening_synthesis.py`: deterministic authored attack/body/tail DSP and the thirty topology dispatch names.
- Modify `Scripts/day_objects_audio/build_happening_bank.py`: orchestration, VCSL transforms, v3 render identity, mastering integration, manifest/catalog updates, and verify-only behavior.
- Modify `Scripts/day_objects_audio/happening-source-map.json`: exact thirty identities, palette kinds, topology names, tail definitions, mastering family, inputs, outputs, and hashes.
- Modify `Scripts/day_objects_audio/test_build_happening_bank.py`: orchestration, provenance, determinism, inventory, and historical near-clone regression tests.
- Create `Scripts/day_objects_audio/test_happening_audio_metrics.py`: focused mastering and analysis unit tests.
- Create `Scripts/day_objects_audio/test_happening_synthesis.py`: focused topology, determinism, envelope, and tail tests.
- Replace `StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings/**/*.wav`: the 102 processed production renders.
- Modify `StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json`: new render identities and processed hashes.
- Modify `StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/SOURCES.json`: exact retained VCSL input paths.
- Modify `StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundRecipe.swift`: working identity, palette kind, topology, and tail metadata.
- Modify `StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundCatalog.swift`: exact recipe metadata, mix trims, filter bounds, and generated hashes.
- Modify `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsHappeningSamplePool.swift`: quieter shared effect defaults and bounded active-recipe glue.
- Modify `StepsTrader/Experiments/DayObjects/Sound/Lab/HappeningSoundPadGrid.swift`: expose the working identity in the accessibility label while keeping visible labels `01–30`.
- Modify `Steps4Tests/HappeningSoundCatalogTests.swift`: exact palette and safe runtime trim contracts.
- Modify `Steps4Tests/DayObjectsAudioResourceTests.swift`: v3 render format and physical PCM gates.
- Modify `Steps4Tests/DayObjectsHappeningSamplePoolTests.swift`: shared-bus glue regression tests.

---

### Task 1: Add deterministic event measurement and bounded mastering

**Files:**

- Create: `Scripts/day_objects_audio/happening_audio_metrics.py`
- Create: `Scripts/day_objects_audio/test_happening_audio_metrics.py`

**Interfaces:**

```python
@dataclass(frozen=True)
class MasteringTarget:
    rms_min_dbfs: float
    rms_max_dbfs: float
    peak_ceiling_dbfs: float = -6.0
    onset_ceiling_dbfs: float = -15.0
    maximum_gain_db: float = 12.0

@dataclass(frozen=True)
class EventMetrics:
    sample_peak_dbfs: float
    audible_rms_dbfs: float
    onset_rms_dbfs: float
    dc_dbfs: float
    duration_seconds: float
    spectral_bands: tuple[float, ...]
    envelope_windows: tuple[float, ...]

# Public functions implemented by this task:
# measure_event(samples: list[float], sample_rate: int = 44_100) -> EventMetrics
# master_event(samples: list[float], target: MasteringTarget, sample_rate: int = 44_100) -> list[float]
# fingerprint_similarity(lhs: EventMetrics, rhs: EventMetrics) -> float
```

- [ ] **Step 1: Write failing mastering tests.** Cover a full-scale sine, a 20 ms transient followed by a quiet tail, a DC-biased event, a silent event, and two identical fingerprints. Assert `master_event` never exceeds `-6 dBFS`, never applies more than `+12 dB`, keeps the first 50 ms under `-15 dBFS`, preserves zero at both boundaries, and raises `AudioMetricError` for silence or non-finite input.

```python
def test_mastering_honors_rms_peak_onset_and_gain_limits(self):
    samples = rendered_transient_fixture()
    mastered = metrics.master_event(samples, metrics.MasteringTarget(-22, -18))
    result = metrics.measure_event(mastered)
    self.assertLessEqual(result.sample_peak_dbfs, -6.0 + 0.05)
    self.assertLessEqual(result.onset_rms_dbfs, -15.0 + 0.05)
    self.assertGreaterEqual(result.audible_rms_dbfs, -22.0 - 0.05)
    self.assertLessEqual(result.audible_rms_dbfs, -18.0 + 0.05)
    self.assertEqual(mastered[0], 0.0)
    self.assertEqual(mastered[-1], 0.0)
```

- [ ] **Step 2: Run the focused tests and verify the expected import failure.**

Run: `python3 -m unittest Scripts.day_objects_audio.test_happening_audio_metrics -v`

Expected: FAIL because `happening_audio_metrics.py` does not exist.

- [ ] **Step 3: Implement measurement.** Use samples at or above `-60 dBFS` for audible RMS, the first 50 ms after the first audible frame for onset RMS, arithmetic mean for DC, 24 normalized Goertzel bands from 80 Hz to 12 kHz, and 12 equal-energy envelope windows. Convert zero energy to `-120 dBFS` and reject NaN/Infinity before calculation.

```python
def amplitude_to_dbfs(value: float) -> float:
    return 20.0 * math.log10(max(abs(value), 1.0e-6))

def rms(values: list[float]) -> float:
    return math.sqrt(sum(value * value for value in values) / len(values))

def fingerprint_similarity(lhs: EventMetrics, rhs: EventMetrics) -> float:
    a = lhs.spectral_bands + lhs.envelope_windows
    b = rhs.spectral_bands + rhs.envelope_windows
    denominator = math.sqrt(sum(x * x for x in a) * sum(y * y for y in b))
    return 0.0 if denominator == 0 else sum(x * y for x, y in zip(a, b)) / denominator
```

- [ ] **Step 4: Implement bounded mastering.** Trim at `-60 dBFS`, apply the existing 5 ms boundary fades, aim at the midpoint of the family RMS range, then choose the minimum gain allowed by RMS target, `-6 dBFS` peak, `-15 dBFS` onset, and `+12 dB` maximum gain. Reject the event if the resulting RMS misses its family range; do not add a compressor or peak-normalize afterward.

- [ ] **Step 5: Re-run the focused tests.**

Run: `python3 -m unittest Scripts.day_objects_audio.test_happening_audio_metrics -v`

Expected: PASS with zero failures and zero errors.

- [ ] **Step 6: Commit the independent metrics module.**

```bash
git add Scripts/day_objects_audio/happening_audio_metrics.py Scripts/day_objects_audio/test_happening_audio_metrics.py
git commit -m "feat: add happening event mastering metrics"
```

### Task 2: Implement the distinct attack/body/tail synthesis library

**Files:**

- Create: `Scripts/day_objects_audio/happening_synthesis.py`
- Create: `Scripts/day_objects_audio/test_happening_synthesis.py`

**Interfaces:**

```python
@dataclass(frozen=True)
class RenderedEvent:
    samples: list[float]
    topology: str
    attack_topology: str
    tail_topology: str

# Public functions implemented by this task:
# render_authored(definition: dict, root_midi: int, seed: int) -> RenderedEvent
# apply_rendered_tail(samples: list[float], root_midi: int, tail: dict, seed: int) -> list[float]
```

The topology dispatch is exact and stable:

```python
AUTHORED_RENDERERS = {
    "analog-ping": render_analog_ping,
    "fm-droplet": render_fm_droplet,
    "pulse-pluck": render_pulse_pluck,
    "waveguide-string": render_waveguide_string,
    "reed-blip": render_reed_blip,
    "reverse-pluck": render_reverse_pluck,
    "kalimba-modal": render_kalimba_modal,
    "ceramic-modal": render_ceramic_modal,
    "felt-key": render_felt_key,
    "metal-bowl-modal": render_metal_bowl,
    "glass-reverse": render_glass_reverse,
    "chorus-kalimba": render_chorus_kalimba,
    "nylon-waveguide": render_nylon_waveguide,
    "sub-bloom": render_sub_bloom,
    "filter-ping": render_filter_ping,
    "formant-droplet": render_formant_droplet,
    "phase-distortion": render_phase_distortion,
    "rubber-fm": render_rubber_fm,
    "harmonic-stab": render_harmonic_stab,
    "breath-resonator": render_breath_resonator,
    "modal-glass-cloud": render_modal_glass_cloud,
    "granular-shimmer": render_granular_shimmer,
    "reverse-glass-unpitched": render_reverse_glass_unpitched,
    "dust-impact": render_dust_impact,
    "breath-exhale": render_breath_exhale,
}
```

- [ ] **Step 1: Write failing synthesis tests.** Assert every dispatch name above renders finite non-silent mono samples, repeated `(definition, root, seed)` calls are byte-identical after PCM quantization, changing the root changes tonal pitch but not duration by more than one frame, and the reported attack/tail pair is unique for all authored recipe definitions.

```python
def test_every_authored_topology_is_deterministic_and_declares_identity(self):
    for definition in authored_definition_fixtures():
        first = synthesis.render_authored(definition, root_midi=60, seed=37)
        second = synthesis.render_authored(definition, root_midi=60, seed=37)
        self.assertEqual(first, second)
        self.assertTrue(all(math.isfinite(sample) for sample in first.samples))
        self.assertGreater(max(map(abs, first.samples)), 1.0e-4)
        self.assertEqual(first.topology, definition["kind"])
```

- [ ] **Step 2: Run the synthesis tests and verify the expected import failure.**

Run: `python3 -m unittest Scripts.day_objects_audio.test_happening_synthesis -v`

Expected: FAIL because `happening_synthesis.py` does not exist.

- [ ] **Step 3: Implement shared deterministic DSP primitives.** Provide seeded white/brown noise, sine/triangle/pulse oscillators, one-pole low/high-pass filters, biquad modal resonators, Karplus–Strong delay, exponential/raised-cosine envelopes, reverse, bounded feedback echo, four-tap diffusion, micro-detuned chorus collapsed safely to mono, and windowed deterministic grains. Every feedback path must clamp absolute output below `2.0` before mastering.

```python
TAIL_RENDERERS = {
    "dry-damping": tail_dry_damping,
    "short-room": tail_short_room,
    "tape-echo": tail_tape_echo,
    "dark-diffusion": tail_dark_diffusion,
    "reverse-bloom": tail_reverse_bloom,
    "chorus-decay": tail_chorus_decay,
    "modal-decay": tail_modal_decay,
    "filtered-breath": tail_filtered_breath,
}
```

- [ ] **Step 4: Implement the 25 authored renderers.** Follow the exact construction and role in the approved spec. Keep attacks between 3 and 80 ms, bodies between 80 and 700 ms, and complete rendered tails within 0.8 and 4.5 seconds. IDs `28–30` must have no stable pitch center; IDs `25–27` render at reference MIDI 60 for runtime retuning.

- [ ] **Step 5: Run the focused synthesis and metrics suites.**

Run: `python3 -m unittest Scripts.day_objects_audio.test_happening_audio_metrics Scripts.day_objects_audio.test_happening_synthesis -v`

Expected: PASS without touching the v2 builder, source map, manifests, catalog, or checked-in WAVs.

- [ ] **Step 6: Commit the independent synthesis library.**

```bash
git add Scripts/day_objects_audio/happening_synthesis.py Scripts/day_objects_audio/test_happening_synthesis.py
git commit -m "feat: render distinct happening sound topologies"
```

### Task 3: Replace the thirty recipes and all 102 processed assets

**Files:**

- Modify: `Scripts/day_objects_audio/happening-source-map.json`
- Modify: `Scripts/day_objects_audio/build_happening_bank.py`
- Modify: `Scripts/day_objects_audio/test_build_happening_bank.py`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings/**/*.wav`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/SOURCES.json`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundRecipe.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundCatalog.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Lab/HappeningSoundPadGrid.swift`
- Modify: `Steps4Tests/HappeningSoundCatalogTests.swift`
- Modify: `Steps4Tests/DayObjectsAudioResourceTests.swift`

**Interfaces:**

```swift
enum HappeningPaletteKind: String, Codable, CaseIterable, Sendable {
    case synth, organic, hybrid
}

struct HappeningSoundRecipe: Equatable, Codable, Sendable {
    let id: HappeningSoundRecipeID
    let label: String
    let workingName: String
    let paletteKind: HappeningPaletteKind
    let topology: String
    let attackTopology: String
    let tailTopology: String
    // Keep the existing family, sources, pitch, gain, envelope, effect, and filter fields.
}
```

Use this exact category and topology assignment:

| Kind | IDs and topology |
|---|---|
| synth | `01 analog-ping`, `02 fm-droplet`, `03 pulse-pluck`, `04 waveguide-string`, `05 reed-blip`, `08 ceramic-modal`, `19 sub-bloom`, `20 filter-ping`, `21 formant-droplet`, `22 phase-distortion` |
| organic | `07 kalimba-modal`, `09 vcsl-marimba-dark`, `10 vcsl-balafon-dry`, `12 felt-key`, `16 nylon-waveguide`, `17 vcsl-tubular-dark`, `18 vcsl-chime-dark`, `28 reverse-glass-unpitched`, `29 dust-impact`, `30 breath-exhale` |
| hybrid | `06 reverse-pluck`, `11 vcsl-vibe-chorus`, `13 metal-bowl-modal`, `14 glass-reverse`, `15 chorus-kalimba`, `23 rubber-fm`, `24 harmonic-stab`, `25 breath-resonator`, `26 modal-glass-cloud`, `27 granular-shimmer` |

- [ ] **Step 1: Write failing catalog and resource tests.** Assert the exact working names from the spec, the category/topology assignment above, ten recipes per palette kind, unique attack/tail pairs, only IDs `09`, `10`, `11`, `17`, `18` using VCSL, exactly 102 files, the v3 render format, family RMS/peak/onset/DC gates, high-frequency attenuation for `17–18`, and localized nonstationary envelopes for `28–30`.

```swift
func testRetimbreCatalogHasExactIdentityAndPaletteKind() {
    XCTAssertEqual(HappeningSoundCatalog.recipes.map(\.workingName), [
        "Warm analog ping", "Glass FM droplet", "Muted pulse pluck",
        "Hollow string", "Air reed blip", "Reverse pluck bloom",
        "Wooden kalimba", "Ceramic knock", "Soft marimba", "Balafon brush",
        "Muted vibraphone", "Felt key", "Soft metal bowl", "Glass tap bloom",
        "Chorus kalimba", "Nylon pizzicato", "Dark tubular bell", "Distant chime",
        "Sub bloom", "Analog filter ping", "Vocal droplet", "Phase-distortion bead",
        "Rubber FM bubble", "Bowed harmonic stab", "Breath resonator",
        "Bowed glass cloud", "Granular shimmer", "Reverse glass gesture",
        "Soft dust impact", "Airy exhale",
    ])
    XCTAssertEqual(Dictionary(grouping: HappeningSoundCatalog.recipes, by: \.paletteKind).mapValues(\.count),
                   [.synth: 10, .organic: 10, .hybrid: 10])
}
```

- [ ] **Step 2: Run the focused tests and verify they fail against the rejected bank.**

Run:

```bash
python3 -m unittest Scripts.day_objects_audio.test_build_happening_bank -v
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4Tests/HappeningSoundCatalogTests \
  -only-testing:Steps4Tests/DayObjectsAudioResourceTests
```

Expected: FAIL because the source map is v2, catalog metadata is absent, peaks are `-3 dBFS`, and the historical groups remain near-clones.

- [ ] **Step 3: Integrate the new modules into the bank builder.** Bump `RENDERER_VERSION` to `happening-bank-v3`; replace `trim_fade_normalize` with `trim_fade_master`; include `workingName`, `paletteKind`, `topology`, `attackTopology`, `tailTopology`, `masteringFamily`, and the complete tail dictionary in `render_identity_for_recipe`; remove production dispatch to `additive-pluck`, `fm-soft`, `resonant-noise`, and `texture-noise`.

```python
def render_generated(recipe: dict, root_midi: int) -> synthesis.RenderedEvent:
    return synthesis.render_authored(
        recipe["definition"], root_midi=root_midi, seed=recipe["seed"]
    )

def trim_fade_master(samples: list[float], target: metrics.MasteringTarget) -> list[int]:
    mastered = metrics.master_event(samples, target=target, sample_rate=SAMPLE_RATE)
    return [int(round(max(-1.0, min(1.0, sample)) * 32767.0)) for sample in mastered]
```

- [ ] **Step 4: Extend builder validation.** Require 30 ordered IDs, 10 `synth`, 10 `organic`, 10 `hybrid`, at least 12 distinct topology names, no three adjacent equal topology names, no duplicate `(attackTopology, tailTopology)` pair, four roots for `01–24`, one root for `25–30`, and exactly 102 outputs.

- [ ] **Step 5: Replace the source map definitions.** Use the 30 exact working identities from the spec, the category/topology table above, four roots with pitch classes C/D♯/F♯/A for IDs `01–24`, and one reference asset for IDs `25–30`. Assign mastering family `tonal-organic` with RMS target `-22...-18 dBFS` to `01–24`, and `texture` with target `-26...-21 dBFS` to `25–30`, independently of palette kind. Assign a different attack/tail pair to every ID. Use these five pinned VCSL recordings and update `SOURCES.json` selected paths to match:

```text
09 Idiophones/Struck Idiophones/Marimba/Marimba_hit_Outrigger_C4_soft_01.wav
10 Idiophones/Struck Idiophones/Balafon/Soft Mallet/EthnicXylo_softM_C4_vl2_rr1_Mid.wav
11 Idiophones/Struck Idiophones/Vibraphone/Soft Mallets/Vibes_soft_C5_v1_rr1_Main.wav
17 Idiophones/Struck Idiophones/Tubular Bells 1/chimes_C4_p_rr1.wav
18 Idiophones/Struck Idiophones/Tubular Bells 1/chimes_D4_p_rr1.wav
```

- [ ] **Step 6: Add exact Swift recipe metadata.** Extend `HappeningSoundRecipe`, replace the old six-per-family catalog-block expectation, and populate `workingName`, `paletteKind`, `topology`, `attackTopology`, and `tailTopology` for all thirty entries. Keep existing stable IDs, paths, pitch behavior, and four-root resolver contract.

- [ ] **Step 7: Expose identity without changing the grid layout.** Keep visible pad text as `01–30`; set the accessibility label to `"Happening 01, Warm analog ping"` through `"Happening 30, Airy exhale"`, and retain the existing loading/disabled behavior.

- [ ] **Step 8: Validate the pinned VCSL checkout.**

Run: `git -C /tmp/day-objects-vcsl rev-parse HEAD`

Expected: exactly `c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e`. If the checkout is absent, create it with `git clone --filter=blob:none https://github.com/sgossner/VCSL.git /tmp/day-objects-vcsl`, then run `git -C /tmp/day-objects-vcsl checkout c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e` and repeat the validation command.

- [ ] **Step 9: Regenerate all production files and metadata.**

Run:

```bash
DAY_OBJECTS_VCSL_CHECKOUT=/tmp/day-objects-vcsl python3 Scripts/day_objects_audio/build_happening_bank.py \
  --vcsl-checkout /tmp/day-objects-vcsl \
  --output-root StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings
```

Expected: 102 deterministic WAV files, updated source-map output hashes, updated asset-manifest records, updated catalog SHA-256 values, and no other resource changes.

- [ ] **Step 10: Add historical-group fingerprint gates.** For representative root C of tonal IDs and the only asset of texture IDs, require every nonidentical pair inside `01–06`, `07–08`, `09–12`, `13–16`, `19–24`, `25–27`, and `28–30` to have combined spectral/envelope cosine below `0.97`. Also require no byte-identical files anywhere in the bank. In the Python builder test, compare retained `17–18` VCSL inputs with their processed representative roots and require at least 4 dB less energy above 5.5 kHz.

- [ ] **Step 11: Verify deterministic reproduction and focused tests.**

Run:

```bash
DAY_OBJECTS_VCSL_CHECKOUT=/tmp/day-objects-vcsl python3 Scripts/day_objects_audio/build_happening_bank.py \
  --vcsl-checkout /tmp/day-objects-vcsl \
  --output-root StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings \
  --verify-only
python3 -m unittest Scripts.day_objects_audio.test_happening_audio_metrics Scripts.day_objects_audio.test_happening_synthesis Scripts.day_objects_audio.test_build_happening_bank -v
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4Tests/HappeningSoundCatalogTests \
  -only-testing:Steps4Tests/DayObjectsAudioResourceTests
```

Expected: all commands exit 0; Python reports zero failures/errors; XCTest reports both suites passing.

- [ ] **Step 12: Commit the catalog and replacement bank.** Before committing, run `git diff --cached --name-only` and confirm neither protected user-owned document is present.

```bash
git add Scripts/day_objects_audio/happening-source-map.json \
  Scripts/day_objects_audio/build_happening_bank.py \
  Scripts/day_objects_audio/test_build_happening_bank.py \
  StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings \
  StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json \
  StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/SOURCES.json \
  StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundRecipe.swift \
  StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundCatalog.swift \
  StepsTrader/Experiments/DayObjects/Sound/Lab/HappeningSoundPadGrid.swift \
  Steps4Tests/HappeningSoundCatalogTests.swift \
  Steps4Tests/DayObjectsAudioResourceTests.swift
git commit -m "assets: replace happening bank with distinct one-shots"
```

### Task 4: Reduce the shared runtime effects to transparent glue

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundCatalog.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsHappeningSamplePool.swift`
- Modify: `Steps4Tests/HappeningSoundCatalogTests.swift`
- Modify: `Steps4Tests/DayObjectsHappeningSamplePoolTests.swift`

**Interfaces:** Existing `HappeningEffectCommand`, `DayObjectsHappeningSamplePool.play`, pitch resolution, voice priority, and four-player allocation remain unchanged.

- [ ] **Step 1: Write failing effect-bound tests.** Assert every recipe has `delayMix <= 0.10`, `delayFeedback <= 0.18`, and `reverbMix <= 0.14`; a newly initialized pool uses `filterCutoffHz: 8_000`, `delayMix: 0.04`, `delayFeedback: 0.12`, `reverbMix: 0.05`; active recipes are order-independent; four simultaneous maximum-wet recipes cannot exceed the recipe bounds; IDs `17–18` finish at or below 7.5 kHz. Keep `HappeningSamplePoolMetrics.inactive` dry because it represents an absent pool.

```swift
func testRenderedTailRecipesUseOnlyConservativeRuntimeGlue() {
    for recipe in HappeningSoundCatalog.recipes {
        XCTAssertLessThanOrEqual(recipe.delayMix, 0.10, recipe.label)
        XCTAssertLessThanOrEqual(recipe.delayFeedback, 0.18, recipe.label)
        XCTAssertLessThanOrEqual(recipe.reverbMix, 0.14, recipe.label)
    }
    XCTAssertLessThanOrEqual(HappeningSoundCatalog.recipes[16].filterEndHz, 7_500)
    XCTAssertLessThanOrEqual(HappeningSoundCatalog.recipes[17].filterEndHz, 7_500)
}
```

- [ ] **Step 2: Run the runtime tests and verify they fail on the current wet catalog.**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' -only-testing:Steps4Tests/HappeningSoundCatalogTests -only-testing:Steps4Tests/DayObjectsHappeningSamplePoolTests`

Expected: FAIL because current recipe wet values reach roughly `0.76` and the default bus is wetter than the new contract.

- [ ] **Step 3: Recalibrate catalog glue.** Use these exact safe ranges: IDs `01–06` delay `0.02...0.08`, feedback `0.06...0.15`, reverb `0.04...0.10`; `07–12` delay `0.01...0.06`, feedback `0.04...0.12`, reverb `0.03...0.08`; `13–18` delay `0.02...0.07`, feedback `0.05...0.14`, reverb `0.04...0.10`; `19–24` delay `0.02...0.08`, feedback `0.06...0.15`, reverb `0.04...0.09`; `25–30` delay `0.01...0.06`, feedback `0.04...0.12`, reverb `0.03...0.08`. Set `17` filter end to 7,000 Hz and `18` to 6,500 Hz.

- [ ] **Step 4: Recalibrate the shared bus.** Set `defaultEffects` to `(8_000, 0.04, 0.12, 0.05)`. Preserve the existing order-independent active-recipe averaging, ramping, priority, voice stealing, limiter, and one-engine graph.

- [ ] **Step 5: Re-run catalog and sample-pool suites.**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' -only-testing:Steps4Tests/HappeningSoundCatalogTests -only-testing:Steps4Tests/DayObjectsHappeningSamplePoolTests`

Expected: PASS with zero XCTest failures.

- [ ] **Step 6: Commit the runtime glue adjustment.**

```bash
git add StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundCatalog.swift \
  StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsHappeningSamplePool.swift \
  Steps4Tests/HappeningSoundCatalogTests.swift \
  Steps4Tests/DayObjectsHappeningSamplePoolTests.swift
git commit -m "fix: keep happening runtime effects transparent"
```

### Task 5: Verify the branch and install the listening build on iPhone Costa

**Files:**

- Verify only: all files changed by Tasks 1–4
- Install artifact: `/tmp/steps4-happening-retimbre/Build/Products/Debug-iphoneos/Steps4.app`

**Interfaces:** No repository interface changes. Device target is paired `iPhone Costa`, identifier `43B6B950-DBCA-50C3-AE14-FBD518808E3B`.

- [ ] **Step 1: Run the complete Python audio suite.**

Run: `python3 -m unittest discover -s Scripts/day_objects_audio -p 'test_*.py' -v`

Expected: zero failures and zero errors.

- [ ] **Step 2: Run deterministic bank verification against pinned VCSL.**

Run: `DAY_OBJECTS_VCSL_CHECKOUT=/tmp/day-objects-vcsl python3 Scripts/day_objects_audio/build_happening_bank.py --vcsl-checkout /tmp/day-objects-vcsl --output-root StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings --verify-only`

Expected: exit 0 with all 102 checked files reproduced byte-for-byte.

- [ ] **Step 3: Run the complete Steps4 unit-test target.**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' -only-testing:Steps4Tests`

Expected: `** TEST SUCCEEDED **` with zero failures.

- [ ] **Step 4: Audit branch scope and asset budgets.** Confirm only intended production files and the new plan/spec commits differ from the pre-retimbre base; confirm 30 recipe directories, 102 WAVs, total WAV bytes `<= 31,457,280`, and no protected user document is staged.

Run:

```bash
find StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings -type f -name '*.wav' | wc -l
du -sk StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings
git diff --check 56949525..HEAD
git status --short
```

Expected: file count `102`, size no more than `30720` KiB, clean committed production changes, plus only the pre-existing protected user-owned edits remaining outside commits.

- [ ] **Step 5: Build a signed Debug device app without changing project settings.**

Run:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS,id=43B6B950-DBCA-50C3-AE14-FBD518808E3B' \
  -derivedDataPath /tmp/steps4-happening-retimbre \
  -allowProvisioningUpdates
```

Expected: `** BUILD SUCCEEDED **` and the app at `/tmp/steps4-happening-retimbre/Build/Products/Debug-iphoneos/Steps4.app`.

- [ ] **Step 6: Install the branch build on iPhone Costa.**

Run: `xcrun devicectl device install app --device 43B6B950-DBCA-50C3-AE14-FBD518808E3B /tmp/steps4-happening-retimbre/Build/Products/Debug-iphoneos/Steps4.app`

Expected: installation succeeds for bundle `personal-project.StepsTrader`. Do not merge, push, or publish.

- [ ] **Step 7: Perform the two-pass physical listening gate.** First switch Canvas Sound off and press `01–30` once each; record only pad numbers that remain too similar, harsh, bright, noisy, or badly balanced. Then switch Canvas Sound on and repeat over at least three Remix harmonic worlds, checking consonance and separation from Harmony/Piano. Use both the iPhone speaker and headphones.

- [ ] **Step 8: Report evidence and await listening feedback.** Report Python test counts, XCTest result, WAV count/size, build/install result, branch/commit, and the fact that no merge or publication occurred. Treat user listening as the release gate; do not describe the bank as accepted before that feedback.
