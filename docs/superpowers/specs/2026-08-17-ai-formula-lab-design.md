# AI Formula Lab Design

**Date:** 2026-08-17

**Status:** Proposed for implementation

## Purpose

AI Formula Lab is a private, device-only creative-coding environment inside
the existing Rich Canvas experiment. It turns written artistic direction into
an animated Metal formula, lets Kosta refine or reject the result, preserves
successful candidates, and exports both media and a production-integration
package.

The Lab is deliberately separate from the production canvas. Runtime-generated
Metal source is experimental content. A candidate reaches production only after
an explicit export, source review, performance validation, and normal Xcode
compilation.

## Goals

- Run on a physical iPhone without a Mac companion.
- Accept typed feedback; voice input is outside this version.
- Use an LLM as an art director and constrained Metal formula author.
- Compile generated Metal source on device and animate it at 60 FPS.
- Support a fast `Generate → Feedback / Keep / Skip` selection loop.
- Preserve every kept candidate reproducibly.
- Export a still PNG, a looped MP4, a portable formula document, and a
  production handoff containing Metal source plus its manifest.
- Keep API credentials out of source control, persistence, diagnostics, and
  exported packages.

## Non-goals

- Automatically modify production canvas code on device.
- Download generated code in the App Store production experience.
- Make generated formulas available to ordinary users.
- Generate arbitrary Swift, vertex shaders, compute kernels, system code, or
  unrestricted Metal programs.
- Replace the existing Rich Canvas renderer, canvas persistence, history,
  thumbnails, wallpaper export, or Supabase sync.
- Build the separate Seed Atlas for existing Rich Canvas families. That remains
  an independent follow-up project.

## User flow

### First launch

1. Open Rich Canvas Lab and enter AI Formula Lab.
2. If no API key exists, show a secure key-entry screen.
3. Save the key to a dedicated Keychain item with
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
4. Never show the complete value again. The user can replace or delete it.

### Creation loop

1. Enter an initial direction such as: "a fragile asymmetric coral that seems
   to remember its previous movement."
2. Tap `Generate`.
3. The art-director request creates a structured algorithmic philosophy.
4. The formula request creates a constrained Metal distance and color function.
5. The device validates the source, compiles it, probes it offscreen, and starts
   the animated preview.
6. Choose one action:
   - `Feedback`: describe a change and generate a child candidate.
   - `Keep`: save the candidate to the local collection.
   - `Skip`: reject the candidate and immediately generate a structurally
     different successor.
7. A back action returns to the previous preview during the current session.

### Saved collection

- Saved candidates appear in a local grid using deterministic preview stills.
- Opening one restores its source, seed, parameters, palette, and animation.
- The detail screen supports export, duplicate-and-refine, production handoff,
  and confirmed deletion.

## Architecture

The subsystem lives under `StepsTrader/Experiments/FormulaLab/`. Rich Canvas
Lab receives only a navigation entry or mode switch; the production renderer
does not import Formula Lab types.

### Components

#### FormulaLabStore

An `@MainActor` observable state machine owns the screen state and coordinates
the other components. Its externally visible states are:

```text
needsKey
ready
directing
generating
compiling
probing
previewing
saving
exporting
requestFailed
compileFailed
probeFailed
```

Only the most recent generation token may update the preview. Starting a new
request cancels the previous network task and makes any late response inert.

#### AlgorithmicArtDirector

The first model pass transforms the user's initial direction into an
`AlgorithmicArtDirection`. It adapts the useful principles from Anthropic's
Apache-2.0 algorithmic-art skill:

- process over a single static frame;
- a named computational philosophy;
- a subtle conceptual seed;
- seeded and controlled variation;
- emergent motion and mathematical relationships;
- deliberate composition and color behavior;
- reproducibility and real-time performance;
- original work rather than imitation of a named living artist.

The app does not copy the p5.js viewer, Anthropic branding, or HTML templates.
Attribution for the adapted instruction source is included in project notices
and the Formula Lab documentation.

The structured result contains:

```swift
struct AlgorithmicArtDirection: Codable, Equatable {
    var name: String
    var philosophy: String
    var conceptualSeed: String
    var geometryIntent: String
    var motionIntent: String
    var compositionIntent: String
    var colorIntent: String
    var parameterAxes: [String]
    var avoid: [String]
}
```

The philosophy is concise: no more than 900 characters. `parameterAxes` is
limited to eight entries and `avoid` to six.

#### MetalFormulaGenerator

The second model pass receives:

- the current art direction;
- the user's latest feedback;
- the parent candidate, when refining;
- a 512×512 preview image of the parent, when available;
- the rejected-trait memory for `Skip`;
- the exact generated-function contract;
- the names and signatures of allowed helper functions;
- the performance and source restrictions.

It returns structured data rather than prose:

```swift
struct FormulaDraft: Codable, Equatable {
    var title: String
    var rationale: String
    var distanceFunctionBody: String
    var colorFunctionBody: String
    var parameters: [FormulaParameterDescriptor]
    var seed: UInt64
    var palette: [FormulaRGBA]
    var expectedMotion: String
}
```

There are at most eight float parameters and four palette colors. The model
does not return a complete Metal file, entry points, buffers, textures, or
pipeline declarations.

#### OpenAIFormulaClient

The Lab calls the OpenAI Responses API using the existing `NetworkClient` for
transport, cancellation, retry, and connectivity behavior. Requests use
structured output schemas. The default model is configurable in Formula Lab;
the initial default is `gpt-5.6-terra`, balancing coding quality with cost and
latency. The model identifier is persisted as a non-secret Lab preference.

The first art-direction call occurs once per new creative session. Generate,
Feedback, and Skip reuse that direction. A candidate normally costs one formula
request. A compiler failure permits one automatic repair request containing
only normalized diagnostics. Further repair requires an explicit user action.

The client must never log the Authorization header, request body, returned
source, API key, or preview image. User-facing errors contain a category and a
short recovery message, not raw server payloads.

#### FormulaAPIKeyStore

A dedicated Keychain helper stores the OpenAI key under a Formula Lab-specific
service and account. It is separate from the Supabase session Keychain item.

- Key material is accepted only through a secure text field.
- The value is never copied into `UserDefaults`, an xcconfig, Info.plist,
  analytics, crash metadata, candidate files, or exports.
- The UI exposes `Replace key` and destructive `Delete key` actions.
- Tests use an injected in-memory credential store and never access a real key.

#### MetalFormulaSourceBuilder

The source builder combines three inputs:

1. a versioned, app-owned Metal prelude;
2. generated distance and color function bodies;
3. fixed vertex and fragment entry points.

Generated code implements these contracts:

```metal
float formulaDistance(
    float2 p,
    float phase,
    uint seed,
    constant FormulaParameters& params
);

float3 formulaColor(
    float2 p,
    float distance,
    float phase,
    uint seed,
    constant FormulaParameters& params
);
```

`phase` is normalized to `0...1` and wraps. The prompt instructs formulas to
use the prelude's periodic helpers so phase 0 and 1 form a visual loop.

The prelude supplies bounded, reviewed implementations of:

- scalar/vector math, mapping, easing, and rotation;
- hash-based seeded random values;
- value/simplex-style noise, FBM, and periodic noise;
- circle, ellipse, box, rounded box, capsule, segment, polygon, and star SDFs;
- union, intersection, subtraction, smooth union, and smooth subtraction;
- repetition, radial repetition, symmetry, bend, twist, and domain warp;
- palette lookup, luminance, saturation, and safe color conversion.

#### FormulaSourceValidator

Validation occurs before Metal compilation. It is a bounded-risk guard, not a
general proof of shader safety.

- Each generated body is limited to 12,000 UTF-8 bytes.
- The candidate may not contain preprocessor directives, includes, entry-point
  attributes, address-space declarations, textures, samplers, atomics,
  threadgroup operations, function declarations, recursion, or pointer syntax.
- Forbidden tokens include `#`, `kernel`, `vertex`, `fragment`, `device`,
  `threadgroup`, `texture`, `sampler`, `atomic`, `discard_fragment`, and
  `while`.
- `for` loops require a literal upper bound no greater than 64.
- Parameter references must resolve to the generated eight-slot parameter
  structure.
- Non-ASCII control characters and null bytes are rejected.

Validation failures are sent to the one-shot repair path in the same normalized
form as compiler failures.

#### MetalFormulaCompiler

The compiler uses `MTLDevice.makeLibrary(source:options:)` away from the main
actor, then creates a render pipeline compatible with the Formula Lab view and
offscreen targets. Pipelines are cached in memory by SHA-256 of the complete
source plus prelude version and pixel format.

Compiler diagnostics are normalized to line, column, severity, and message.
The UI shows them in an expandable diagnostics panel. Raw generated source is
available in a read-only source inspector.

#### FormulaProbeRunner

Before interactive preview, the candidate renders offscreen at 128×128 for
phases `0`, `0.25`, `0.5`, `0.75`, and `1`.

The probe rejects candidates that:

- fail to complete a command buffer;
- produce non-finite or invalid output;
- have less than 1% or more than 90% foreground coverage in every sampled
  frame;
- are static across all sampled phases when motion was requested;
- differ excessively between phase 0 and phase 1, preventing a clean loop;
- exceed 16.7 ms GPU time for any 128×128 probe frame.

Warnings are allowed for low motion or imperfect loop closure. Hard failures
enter `probeFailed` and permit repair or Skip.

#### FormulaMetalRenderer

The renderer follows the existing `MTKViewDelegate` and `UIViewRepresentable`
patterns used by the app's Metal overlays, but owns no production-canvas state.

- Preferred refresh rate is 60 FPS.
- The display link pauses when the Formula Lab is not visible, the scene is not
  active, or Reduce Motion is enabled.
- Under Reduce Motion, the renderer shows the deterministic phase-zero frame.
- Resolution begins at at most 1.25 pixels per point, matching the existing
  expensive-overlay policy, and can be lowered automatically if the rolling
  frame budget is missed.
- Parameter sliders update uniforms without recompilation.
- Source, prelude version, or pixel format changes trigger compilation.
- The last valid pipeline remains visible while a new candidate compiles.

#### FormulaCandidateStore

Kept candidates live in:

```text
Application Support/
  formula_lab/
    index.json
    candidates/<uuid>/
      candidate.json
      formula.metal
      preview.png
      preview.mov        # created lazily on first video export
```

Writes use a temporary sibling directory followed by an atomic replacement.
`index.json` is rebuildable by scanning candidate directories. A corrupt
candidate is omitted from the grid and reported in diagnostics; it does not
prevent other candidates from loading.

The persisted `FormulaCandidate` includes:

- stable UUID and optional parent UUID;
- creation and last-edit dates;
- algorithmic art direction;
- initial prompt and feedback history;
- normalized rejection context inherited from skipped parents;
- generated bodies and assembled-source hash;
- prelude and package schema versions;
- parameter descriptors and current values;
- seed and palette;
- model identifier;
- compiler and probe summaries;
- preview filenames and export status.

The API key and Authorization metadata are never Codable fields.

## Keep, Feedback, and Skip semantics

### Keep

- Captures a deterministic 1024×1024 phase-zero preview.
- Atomically persists the candidate and updates the collection index.
- Does not block on video generation.
- Leaves the candidate on screen and enables Export and Duplicate-and-refine.

### Feedback

- Creates a child candidate; it never mutates the parent in place.
- Sends the parent source, parameters, 512×512 preview, latest text feedback,
  art direction, and relevant prior feedback.
- Keeps an in-memory session trail so the user can go back to the parent even
  when it was not kept.
- A kept parent remains untouched if the child is rejected.

### Skip

- Does not persist the candidate package or preview media.
- Adds a compact rejection record to a session-local diversity memory capped at
  20 entries. The record includes structural traits, not the entire shader.
- Immediately requests a successor using the same art direction and an
  instruction to change topology or motion logic rather than merely numeric
  values.
- Clears the rejected pipeline from the Lab cache after the successor becomes
  active.

## UI design

### Formula Lab root

- Full-bleed animated Metal preview.
- Existing app background and typography; no copied Anthropic viewer styling.
- Compact top header with `Formula Lab`, collection access, source/diagnostics,
  and API-key settings.
- Bottom material panel with a multiline direction or feedback field.
- Primary `Generate` action before the first candidate.
- Once previewing, three equally available actions: `Feedback`, `Keep`, and
  `Skip`. Keep is visually positive; Skip is neutral, not destructive red.
- Progress copy distinguishes `Directing`, `Writing formula`, `Compiling`, and
  `Checking motion`.
- The current philosophy name and one-line rationale are inspectable but do not
  cover the art.

### Parameter inspector

- Up to eight sliders generated from parameter descriptors.
- Current value, default reset, and min/max are visible.
- Slider changes are local uniform edits and do not call the API.
- `Regenerate seed` changes only the seed for cheap exploration of the same
  formula.
- `Refine with AI` sends the current slider state as part of Feedback.

### Source and diagnostics

- Read-only assembled-source view with copy and share actions.
- Separate generated-body and compiler-diagnostics tabs.
- Automatic repair is labeled and limited to one attempt.
- The source inspector never displays the API key or request headers.

### Collection

- Grid of square preview stills, newest first.
- Detail view restores animation and exposes Export, Duplicate and refine,
  Production handoff, and Delete.
- Delete requires confirmation and removes the candidate directory; an already
  exported external file is unaffected.

## Export

### PNG

- Offscreen Metal render at 2048×2048, phase selected by the user or phase zero
  by default.
- sRGB PNG with opaque or transparent background selection.
- Metadata contains candidate UUID, seed, package version, and philosophy name,
  but no prompt text unless explicitly enabled.

### Looped video

- Four seconds, 30 FPS, 1080×1080, H.264 MP4.
- Frames cover phase `[0, 1)` so the first frame is not duplicated at the end.
- Rendering uses a dedicated offscreen texture and `AVAssetWriter`.
- Export runs as a cancellable task and leaves no partial final file.
- The phase-zero/phase-one probe warning remains visible before export.

### Portable formula document

`<name>.formulaart.json` contains the complete `FormulaCandidate` manifest and
generated function bodies, excluding preview media and credentials. The JSON is
human-readable, versioned, and sufficient to reconstruct the animation in a
compatible Formula Lab build.

The share sheet may export the JSON, PNG, and MP4 together as separate items.

### Production handoff

The handoff exports:

- `<slug>.metal` with the approved generated functions and required prelude
  version declaration;
- `<slug>.formula.json` with parameters, palette, seed, art direction, probe
  results, and source hash;
- `<slug>-preview.png`;
- `<slug>-preview.mp4` when available;
- an attribution notice for the adapted algorithmic-art instruction source.

On-device export does not edit the Xcode project. Production adoption is a
normal repository change: review source, add it to the target, compile at build
time, add fallbacks, verify performance, and update production exports. Runtime
formula download remains disabled outside the private Lab.

## Error handling

- Missing key: return to `needsKey`; never substitute a bundled credential.
- Authentication failure: offer Replace key, without exposing server content.
- Connectivity or retryable server failure: existing exponential backoff, then
  a visible Retry action.
- Structured-output decode failure: preserve the current preview and offer
  Retry; do not try to scrape source from arbitrary prose.
- Source validation failure: one normalized repair attempt.
- Metal compiler failure: show diagnostics and allow one automatic repair,
  manual feedback, or Skip.
- Probe failure: keep the previous valid pipeline visible and offer repair or
  Skip.
- Save/export failure: leave the candidate in memory, clean temporary files,
  and offer Retry.
- Backgrounding: cancel network/export work where safe and pause rendering.
- Low Power Mode: preview may reduce resolution or FPS, but exported media uses
  the requested deterministic settings.

## Performance budgets

- Interactive target: 60 FPS on the development iPhone at Formula Lab's capped
  render scale.
- A rolling p95 frame duration above 16.7 ms for three seconds triggers a
  resolution reduction and a visible performance warning.
- Generated bodies: maximum 24 combined calls to expensive prelude functions
  per fragment by prompt contract; constant loops remain bounded at 64.
- Pipeline cache: maximum eight compiled candidates, LRU-evicted.
- Session trail: maximum ten unkept candidates with preview images held in
  memory; older unkept previews are discarded.
- Formula request: one normal generation plus at most one automatic repair.

## Privacy and security

- This is a private DEBUG-only experiment unless a later design explicitly
  changes the gate.
- API requests send the user's direction, art direction, generated source,
  selected parameter state, and optionally a 512×512 preview.
- The Lab explains that payload before the first request.
- App analytics do not receive prompt, philosophy, source, compiler diagnostics,
  model output, API usage, or candidate images.
- Keychain uses a Formula Lab-specific service/account and ThisDeviceOnly
  accessibility.
- Generated shader code is treated as untrusted input and never gains access to
  buffers, textures, atomics, device pointers, or arbitrary entry points.
- Production builds do not expose Formula Lab navigation or runtime-generated
  pipelines.

## Testing strategy

### Pure unit tests

- `FormulaLabStore` state transitions, cancellation, and stale-response
  rejection.
- Art-direction and formula structured-output decoding.
- Prompt construction, including Skip diversity memory and Feedback ancestry.
- Source builder line mapping and deterministic hashes.
- Source validator accepted and forbidden constructs, body-size limits, loop
  bounds, and parameter references.
- Candidate Codable round trips and schema migration.
- Atomic candidate-store save/load/index rebuild and corrupt-entry isolation.
- Key-store behavior through an in-memory protocol implementation.
- Export filenames, manifests, metadata redaction, and cleanup on cancellation.

### Metal characterization tests

- A fixture body compiles into the fixed template on Metal-capable test hosts.
- Invalid fixture source returns normalized diagnostics.
- Probe coverage detects empty, full-screen, static, and non-looping fixtures.
- Parameter uniform changes do not rebuild the pipeline.
- Pipeline cache keys include source hash, prelude version, and pixel format.

### Network contract tests

- Use fixture JSON and an injected `URLProtocol`; never call the live API in the
  test suite.
- Verify Authorization is attached by the client but omitted from logs and
  error descriptions.
- Verify retryable and non-retryable responses preserve the current preview.
- Verify one-repair maximum.

### Device acceptance

- Enter, replace, relaunch with, and delete the Keychain credential.
- Generate, compile, and animate a fixture and a live API candidate.
- Confirm 60 FPS or documented adaptive-resolution behavior.
- Exercise Feedback, back, Keep, Skip auto-next, collection reload, and delete.
- Export and open PNG, looping MP4, formula JSON, and production handoff.
- Relaunch offline and animate saved candidates without API access.
- Verify background pause, Reduce Motion, Low Power Mode, memory warning, and
  failed-compile recovery.

## Delivery decomposition

The Formula Lab is one subsystem but should be implemented in independently
testable vertical slices:

1. Formula model, source contract, validator, fixture compiler, and 60 FPS Metal
   preview with no API.
2. Candidate state machine, Keep/Skip local persistence, and collection.
3. Keychain credential UI and Responses API clients with fixture-driven tests.
4. Algorithmic Art Director and generated formula/repair loop.
5. Feedback ancestry, rejection diversity memory, and parameter inspector.
6. Offscreen PNG/video export and portable formula document.
7. Production handoff, full device acceptance, and performance tuning.

The independent Seed Atlas for the existing Rich Canvas families follows after
this subsystem; it can later reuse Formula Lab's gallery and quality-measurement
patterns without sharing generated-code runtime state.
