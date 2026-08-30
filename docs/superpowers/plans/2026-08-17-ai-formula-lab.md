# AI Formula Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a private on-device Formula Lab that turns typed artistic direction into constrained animated Metal formulas, supports Feedback, Keep, and Skip, and exports media plus a production handoff.

**Architecture:** Formula Lab is an isolated DEBUG-only subsystem under `StepsTrader/Experiments/FormulaLab`. Swift owns state, persistence, networking, validation, and export; generated code is limited to two function bodies inserted into an app-owned Metal template and rendered by `MTKView` at a preferred 60 FPS. The implementation is delivered in vertical slices so fixture formulas, persistence, API generation, refinement, and export can each be reviewed and tested independently.

**Tech Stack:** Swift 5, SwiftUI, Observation/Combine-compatible `ObservableObject`, Metal/MetalKit, Security Keychain APIs, OpenAI Responses API, Foundation networking, Core Image, AVFoundation, XCTest, Xcode project targets `Steps4` and `Steps4Tests`.

**Spec:** `docs/superpowers/specs/2026-08-17-ai-formula-lab-design.md`

## Global Constraints

- The app target remains iOS 17; device acceptance runs on a physical iPhone.
- Formula Lab is reachable only in DEBUG builds and production targets do not expose runtime-generated pipelines.
- Voice input is excluded; feedback is typed.
- Generated code consists only of `formulaDistance` and `formulaColor` bodies; entry points, buffers, textures, and the Metal prelude remain app-owned.
- Generated bodies are at most 12,000 UTF-8 bytes each, loops are statically bounded to 64 iterations, parameters are limited to eight floats, and palettes are limited to four colors.
- Preview prefers 60 FPS, begins at no more than 1.25 pixels per point, pauses offscreen, and renders phase zero under Reduce Motion.
- OpenAI credentials live only in a dedicated ThisDeviceOnly Keychain item and never enter logs, analytics, candidate documents, or exports.
- A normal generation receives at most one automatic repair request.
- Kept candidates are reproducible from source, prelude version, parameters, palette, seed, and feedback ancestry.
- PNG uses an offscreen 2048×2048 render; loop video uses 4 seconds, 30 FPS, 1080×1080 H.264.
- Existing dirty-worktree changes are preserved. Git staging and commits are performed only with explicit user authorization.

## File Map

- `StepsTrader/Experiments/FormulaLab/FormulaModels.swift`: Codable domain types, limits, candidate ancestry, and render uniforms.
- `StepsTrader/Experiments/FormulaLab/FormulaMetalPrelude.swift`: versioned app-owned MSL template and helper library.
- `StepsTrader/Experiments/FormulaLab/FormulaSourceValidator.swift`: lexical source restrictions and bounded-loop checks.
- `StepsTrader/Experiments/FormulaLab/FormulaMetalCompiler.swift`: runtime library/pipeline compilation, normalized diagnostics, and LRU cache.
- `StepsTrader/Experiments/FormulaLab/FormulaMetalRenderer.swift`: `MTKViewDelegate`, animation clock, adaptive scale, and offscreen rendering.
- `StepsTrader/Experiments/FormulaLab/FormulaMetalView.swift`: SwiftUI wrapper for the Metal preview.
- `StepsTrader/Experiments/FormulaLab/FormulaCandidateStore.swift`: atomic candidate persistence and index rebuilding.
- `StepsTrader/Experiments/FormulaLab/FormulaLabStore.swift`: `@MainActor` state machine and latest-request cancellation.
- `StepsTrader/Experiments/FormulaLab/FormulaAPIKeyStore.swift`: dedicated Keychain credential storage.
- `StepsTrader/Experiments/FormulaLab/OpenAIFormulaClient.swift`: Responses API requests, structured-output schemas, redacted failures, and repair limits.
- `StepsTrader/Experiments/FormulaLab/FormulaPrompts.swift`: art-director, formula, Feedback, Skip, and repair prompt construction.
- `StepsTrader/Experiments/FormulaLab/FormulaProbeRunner.swift`: deterministic multi-phase offscreen quality and timing probes.
- `StepsTrader/Experiments/FormulaLab/FormulaExporter.swift`: PNG, MP4, portable JSON, and production handoff artifacts.
- `StepsTrader/Experiments/FormulaLab/FormulaLabView.swift`: generation UI, preview controls, feedback, and state presentation.
- `StepsTrader/Experiments/FormulaLab/FormulaCollectionView.swift`: kept-candidate grid, detail, duplicate, export, and deletion.
- `StepsTrader/Experiments/RichCanvas/RichCanvasLabView.swift`: DEBUG navigation entry into Formula Lab.
- `Steps4.xcodeproj/project.pbxproj`: app/test file references, groups, and source build phases.
- `Steps4Tests/FormulaModelsTests.swift`: model limits, coding, and deterministic identity.
- `Steps4Tests/TestHelpers/FormulaFixtures.swift`: shared valid directions, drafts, candidates, and synthetic probe frames.
- `Steps4Tests/FormulaSourceValidatorTests.swift`: accepted/forbidden MSL body characterization.
- `Steps4Tests/FormulaMetalCompilerTests.swift`: template assembly, compile diagnostics, and cache keys.
- `Steps4Tests/FormulaCandidateStoreTests.swift`: atomic save/load/index recovery.
- `Steps4Tests/FormulaLabStoreTests.swift`: transitions, cancellation, Keep, Feedback, and Skip.
- `Steps4Tests/FormulaAPIKeyStoreTests.swift`: injected credential-store behavior without real Keychain access.
- `Steps4Tests/OpenAIFormulaClientTests.swift`: request/schema/response/error contracts with `URLProtocol` fixtures.
- `Steps4Tests/FormulaProbeRunnerTests.swift`: empty, full, static, motion, and loop quality metrics.
- `Steps4Tests/FormulaExporterTests.swift`: manifest redaction, naming, and cancellation cleanup.

---

### Task 1: Domain model, constrained source contract, and validator

**Files:**
- Create: `StepsTrader/Experiments/FormulaLab/FormulaModels.swift`
- Create: `StepsTrader/Experiments/FormulaLab/FormulaMetalPrelude.swift`
- Create: `StepsTrader/Experiments/FormulaLab/FormulaSourceValidator.swift`
- Create: `Steps4Tests/FormulaModelsTests.swift`
- Create: `Steps4Tests/FormulaSourceValidatorTests.swift`
- Create: `Steps4Tests/TestHelpers/FormulaFixtures.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Foundation `Codable`, `UUID`, `Date`, and SIMD value types.
- Produces: `AlgorithmicArtDirection`, `FormulaDraft`, `FormulaCandidate`, `FormulaParameterDescriptor`, `FormulaRGBA`, `FormulaProbeSummary`, `FormulaMetalPrelude.assemble(draft:)`, and `FormulaSourceValidator.validate(body:kind:)`.

- [ ] **Step 1: Add failing model tests**

```swift
func testCandidateRoundTripPreservesReproductionInputs() throws {
    let candidate = FormulaFixtures.candidate(seed: 42)
    let data = try JSONEncoder().encode(candidate)
    let decoded = try JSONDecoder().decode(FormulaCandidate.self, from: data)
    XCTAssertEqual(decoded, candidate)
}

func testDraftRejectsMoreThanEightParameters() {
    let draft = FormulaFixtures.draft(parameterCount: 9)
    XCTAssertThrowsError(try draft.validated())
}
```

- [ ] **Step 2: Add failing validator tests**

```swift
func testAcceptsBoundedExpressionBody() throws {
    let body = "float d = sdCircle(p, params.values[0]); return d;"
    XCTAssertNoThrow(try FormulaSourceValidator().validate(body: body, kind: .distance))
}

func testRejectsEntryPointsPointersAndUnboundedLoops() {
    let bodies = [
        "fragment float4 stolen() { return 0; }",
        "device float *value; return *value;",
        "while (true) { } return 0;",
        "for (int i = 0; i < 65; ++i) { } return 0;"
    ]
    for body in bodies {
        XCTAssertThrowsError(try FormulaSourceValidator().validate(body: body, kind: .distance))
    }
}
```

- [ ] **Step 3: Register the five source/test files in the correct PBX groups and source phases**

Add unique PBX file-reference and build-file identifiers, place production files in a new `FormulaLab` group under `Experiments`, place tests in `Steps4Tests`, and add each build file to exactly one matching Sources phase.

- [ ] **Step 4: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/FormulaModelsTests \
  -only-testing:Steps4Tests/FormulaSourceValidatorTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: build failures for missing Formula Lab types.

- [ ] **Step 5: Implement immutable model limits and explicit validation errors**

```swift
enum FormulaLimits {
    static let maximumParameters = 8
    static let maximumPaletteColors = 4
    static let maximumBodyBytes = 12_000
    static let maximumLoopIterations = 64
}

struct FormulaDraft: Codable, Equatable, Sendable {
    let title: String
    let rationale: String
    let distanceFunctionBody: String
    let colorFunctionBody: String
    let parameters: [FormulaParameterDescriptor]
    let seed: UInt64
    let palette: [FormulaRGBA]
    let expectedMotion: String

    func validated() throws -> Self
}
```

Define `FormulaCandidate` with UUID, parent UUID, dates, direction, prompt/feedback history, rejection traits, generated bodies, assembled-source hash, prelude/schema versions, parameter values, seed, palette, model ID, optional `FormulaProbeSummary`, and preview filenames. Define the summary value type here so persistence has a stable schema before Task 7 supplies its measurements. Do not define credential or Authorization fields.

- [ ] **Step 6: Implement the app-owned Metal template**

Expose exact contracts:

```metal
float formulaDistance(float2 p, float phase, uint seed, constant FormulaParameters& params);
float3 formulaColor(float2 p, float distance, float phase, uint seed, constant FormulaParameters& params);
```

The fixed template owns fullscreen vertex/fragment entry points, safe division/clamp helpers, basic SDF primitives, seeded hash, periodic noise, palette access, and `FormulaParameters { float values[8]; float4 colors[4]; }`.

- [ ] **Step 7: Implement lexical validation**

Normalize Unicode, reject control/null bytes, enforce UTF-8 size, scan forbidden tokens as token boundaries, reject function declarations and pointer syntax, verify `params.values[index]` is in `0...7`, and accept `for` only when the comparator has an integer literal no greater than 64. Return `[FormulaValidationIssue]` with stable codes and source ranges.

- [ ] **Step 8: Run focused tests and verify GREEN**

Run the Step 4 command. Expected: both suites pass.

- [ ] **Step 9: Review checkpoint**

Inspect `git diff --check` and the focused diff. If the user authorizes a commit, use `feat: add constrained Formula Lab source contract`.

---

### Task 2: Runtime compiler and animated fixture preview

**Files:**
- Create: `StepsTrader/Experiments/FormulaLab/FormulaMetalCompiler.swift`
- Create: `StepsTrader/Experiments/FormulaLab/FormulaMetalRenderer.swift`
- Create: `StepsTrader/Experiments/FormulaLab/FormulaMetalView.swift`
- Create: `Steps4Tests/FormulaMetalCompilerTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `FormulaMetalPrelude.assemble(draft:)`, `FormulaDraft`, Metal/MetalKit.
- Produces: `FormulaCompiledPipeline`, `FormulaCompilerDiagnostic`, `FormulaMetalCompiler.compile(draft:pixelFormat:) async`, `FormulaMetalRenderer.install(pipeline:candidate:)`, and `FormulaMetalView`.

- [ ] **Step 1: Write failing compiler/cache tests**

```swift
func testFixtureDraftCompilesWithFixedEntryPoints() async throws {
    let compiler = try XCTUnwrap(FormulaMetalCompiler.makeDefault())
    let result = try await compiler.compile(
        draft: FormulaFixtures.animatedCircle,
        pixelFormat: .bgra8Unorm
    )
    XCTAssertEqual(result.sourceHash.count, 64)
}

func testCacheKeyChangesWithPreludeAndPixelFormat() {
    XCTAssertNotEqual(
        FormulaPipelineKey(sourceHash: "a", preludeVersion: 1, pixelFormat: .bgra8Unorm),
        FormulaPipelineKey(sourceHash: "a", preludeVersion: 2, pixelFormat: .bgra8Unorm)
    )
}
```

- [ ] **Step 2: Register files and run focused tests to verify RED**

Use the Task 1 registration pattern, then run `-only-testing:Steps4Tests/FormulaMetalCompilerTests`. Expected: missing compiler and renderer symbols.

- [ ] **Step 3: Implement asynchronous compilation and normalized diagnostics**

Create libraries with `device.makeLibrary(source:options:)` from a non-main task, resolve only `formulaLabVertex` and `formulaLabFragment`, build a `.bgra8Unorm` pipeline, and normalize Metal errors into line, column, severity, and message. Cache at most eight pipelines by SHA-256 source hash, prelude version, and pixel format.

- [ ] **Step 4: Implement 60 FPS `MTKViewDelegate` rendering**

```swift
struct FormulaRenderUniforms {
    var resolution: SIMD2<Float>
    var phase: Float
    var seed: UInt32
    var values0: SIMD4<Float>
    var values1: SIMD4<Float>
    var color0: SIMD4<Float>
    var color1: SIMD4<Float>
    var color2: SIMD4<Float>
    var color3: SIMD4<Float>
}
```

Use a monotonic clock, wrap phase into `[0, 1)`, set `preferredFramesPerSecond = 60`, cap `contentScaleFactor` to 1.25, keep the last valid pipeline during replacement, and pause when inactive. Track a rolling p95 frame duration; after three seconds above 16.7 ms, lower render scale one step and publish a visible warning. Low Power Mode may reduce scale or preview FPS. Parameter and seed updates change uniforms without recompilation.

- [ ] **Step 5: Add SwiftUI wrapper and fixture initializer**

`FormulaMetalView` creates an `MTKView`, assigns the renderer, mirrors scene activity and Reduce Motion, and shows the deterministic phase-zero frame when motion is reduced. A DEBUG fixture factory exposes an animated circle so the slice can run without network access.

- [ ] **Step 6: Run compiler tests and app build**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/FormulaMetalCompilerTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: tests and build pass. Metal compilation test may skip only when no Metal device is exposed by the host.

- [ ] **Step 7: Review checkpoint**

Inspect `git diff --check`. If authorized, commit as `feat: render animated Formula Lab fixtures with Metal`.

---

### Task 3: Candidate state machine, Keep/Skip, persistence, and collection

**Files:**
- Create: `StepsTrader/Experiments/FormulaLab/FormulaCandidateStore.swift`
- Create: `StepsTrader/Experiments/FormulaLab/FormulaLabStore.swift`
- Create: `StepsTrader/Experiments/FormulaLab/FormulaLabView.swift`
- Create: `StepsTrader/Experiments/FormulaLab/FormulaCollectionView.swift`
- Create: `Steps4Tests/FormulaCandidateStoreTests.swift`
- Create: `Steps4Tests/FormulaLabStoreTests.swift`
- Modify: `StepsTrader/Experiments/RichCanvas/RichCanvasLabView.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: fixture compiler/renderer, `FormulaCandidate`, `FileManager`, Rich Canvas theme/header components.
- Produces: `FormulaCandidatePersisting`, `FormulaCandidateStore`, `FormulaLabState`, `FormulaLabStore`, root Lab UI, and saved collection UI.

- [ ] **Step 1: Write failing persistence tests**

```swift
func testSaveLoadAndIndexRebuild() throws {
    let root = temporaryDirectory()
    let store = FormulaCandidateStore(rootURL: root)
    let candidate = FormulaFixtures.candidate(seed: 7)
    try store.save(candidate, previewPNG: Data([1, 2, 3]))
    try FileManager.default.removeItem(at: root.appendingPathComponent("index.json"))
    XCTAssertEqual(try store.loadAll().map(\.id), [candidate.id])
}

func testCorruptCandidateDoesNotHideHealthyCandidate() throws {
    let loaded = try makeStoreWithOneHealthyAndOneCorruptCandidate().loadAll()
    XCTAssertEqual(loaded.count, 1)
}
```

- [ ] **Step 2: Write failing state-machine tests**

```swift
@MainActor
func testStaleGenerationCannotReplaceLatestPreview() async {
    let generator = ControllableFormulaGenerator()
    let store = FormulaLabStore(generator: generator, candidateStore: InMemoryCandidateStore())
    let first = store.generate(direction: "coral")
    let second = store.generate(direction: "mist")
    generator.complete(first, with: FormulaFixtures.candidate(seed: 1))
    generator.complete(second, with: FormulaFixtures.candidate(seed: 2))
    await store.waitForIdle()
    XCTAssertEqual(store.currentCandidate?.seed, 2)
}

@MainActor
func testSkipRecordsTraitsAndRequestsDifferentSuccessor() async {
    let store = makeFixtureLabStore()
    await store.skip()
    XCTAssertEqual(store.rejectionMemory.count, 1)
    XCTAssertEqual(store.generationRequests.last?.mode, .skip)
}
```

- [ ] **Step 3: Register files and run both suites to verify RED**

Run only `FormulaCandidateStoreTests` and `FormulaLabStoreTests`. Expected: missing persistence/state symbols.

- [ ] **Step 4: Implement atomic candidate persistence**

Define `FormulaCandidatePersisting` with `loadAll`, `load(id:)`, `save(_:previewPNG:)`, and `delete(id:)`. Write candidate contents to a sibling temporary directory, move atomically into `Application Support/formula_lab/candidates/<uuid>`, rebuild `index.json` from readable candidate folders, and expose corrupt-entry diagnostics separately.

- [ ] **Step 5: Implement the `@MainActor` state machine**

Use explicit states `needsKey`, `ready`, `directing`, `generating`, `compiling`, `probing`, `previewing`, `saving`, `exporting`, `requestFailed`, `compileFailed`, and `probeFailed`. Every generation receives a UUID token; only the active token may install a pipeline or candidate. Keep captures and persists a deterministic 1024×1024 phase-zero preview; Skip adds one compact record to a 20-item memory and requests a successor; Back restores one of at most ten session candidates. Scene backgrounding cancels active network/export tasks where safe and pauses rendering.

- [ ] **Step 6: Build the fixture-driven Lab and collection UI**

Create the full-bleed preview, multiline prompt, Generate/Feedback/Keep/Skip controls, source/diagnostics sheet, parameter sliders, seed regeneration, collection grid, detail view, confirmed deletion, and progress labels. All API-dependent controls use the fixture generator until Task 5.

- [ ] **Step 7: Add DEBUG-only navigation from Rich Canvas Lab**

Add a toolbar/header action guarded with `#if DEBUG` that presents or navigates to `FormulaLabView`. Do not reference Formula Lab types in a RELEASE compilation branch.

- [ ] **Step 8: Run focused tests and build**

Run both Task 3 test classes, then the Debug simulator build. Expected: pass.

- [ ] **Step 9: Review checkpoint**

Inspect the saved file layout in tests and `git diff --check`. If authorized, commit as `feat: add Formula Lab candidate workflow`.

---

### Task 4: Keychain credential and OpenAI structured-output clients

**Files:**
- Create: `StepsTrader/Experiments/FormulaLab/FormulaAPIKeyStore.swift`
- Create: `StepsTrader/Experiments/FormulaLab/FormulaPrompts.swift`
- Create: `StepsTrader/Experiments/FormulaLab/OpenAIFormulaClient.swift`
- Create: `Steps4Tests/FormulaAPIKeyStoreTests.swift`
- Create: `Steps4Tests/OpenAIFormulaClientTests.swift`
- Create: `Steps4Tests/Fixtures/formula-art-direction-response.json`
- Create: `Steps4Tests/Fixtures/formula-draft-response.json`
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaLabView.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: existing `NetworkClient`, domain models, secure SwiftUI text field.
- Produces: `FormulaCredentialStoring`, `FormulaAPIKeyStore`, `FormulaGenerating`, `OpenAIFormulaClient`, `FormulaPromptBuilder`, and typed `FormulaClientError`.

- [ ] **Step 1: Write failing credential tests against an injected store**

```swift
func testCredentialLifecycleNeverExposesStoredValueInDescription() throws {
    let store = InMemoryFormulaCredentialStore()
    try store.save("sk-test-secret")
    XCTAssertTrue(store.hasCredential)
    XCTAssertFalse(String(describing: store).contains("sk-test-secret"))
    try store.delete()
    XCTAssertFalse(store.hasCredential)
}
```

- [ ] **Step 2: Write failing request/response contract tests**

```swift
func testFormulaRequestUsesResponsesEndpointAndStrictSchema() async throws {
    let capture = URLRequestCapture(responseFixture: "formula-draft-response.json")
    let client = OpenAIFormulaClient(transport: capture, credentialStore: InMemoryFormulaCredentialStore("sk-test"))
    _ = try await client.generateFormula(request: FormulaFixtures.generationRequest)
    XCTAssertEqual(capture.request?.url?.absoluteString, "https://api.openai.com/v1/responses")
    XCTAssertEqual(capture.request?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    XCTAssertTrue(try capture.requestJSON.containsStrictJSONSchema(named: "formula_draft"))
}

func testServerFailureDoesNotIncludeCredentialOrPayload() async {
    let error = await failingClientError(key: "sk-test-secret", payload: "private prompt")
    XCTAssertFalse(String(describing: error).contains("sk-test-secret"))
    XCTAssertFalse(String(describing: error).contains("private prompt"))
}
```

- [ ] **Step 3: Register files/fixtures and verify RED**

Run `FormulaAPIKeyStoreTests` and `OpenAIFormulaClientTests`. Expected: missing types.

- [ ] **Step 4: Implement dedicated Keychain storage**

Use service `com.stepstrader.formula-lab.openai`, account `api_key_v1`, generic-password class, and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Expose only `hasCredential`, a closure-scoped `withCredential`, `save`, and `delete`; do not add a public property containing the key.

- [ ] **Step 5: Implement exact structured-output prompts**

Art direction is limited to name, philosophy, conceptual seed, geometry, motion, composition, color, up to eight parameter axes, and up to six avoid traits. Formula output is limited to title, rationale, two body strings, up to eight parameter descriptors, UInt64 seed, up to four RGBA colors, and expected motion. Prompt rules prohibit artist imitation, full Metal files, resources, pointers, unbounded loops, and unknown helpers.

- [ ] **Step 6: Implement Responses API transport**

POST to `/v1/responses` with default model `gpt-5.6-terra`, bearer credential, `store: false`, and strict JSON schema. Persist the configurable model identifier as a non-secret Formula Lab preference. Parse the structured JSON content without scraping prose. Map 401/403 to authentication, 408/429/5xx to retryable service errors, decode failures to invalid structured output, and other statuses to redacted server errors. Use the existing `NetworkClient` retry policy and propagate cancellation.

- [ ] **Step 7: Add secure key-entry UI**

Show the disclosure of transmitted data before first use, collect the key in `SecureField`, clear the local string immediately after Keychain save, and provide Replace/Delete actions. Never prefill the stored value.

- [ ] **Step 8: Run focused tests and build**

Run both Task 4 suites and the Debug build. Expected: pass with fixture-only networking.

- [ ] **Step 9: Review checkpoint**

Search the diff for `sk-`, `Authorization`, and key property names; only test fixtures and request-header construction may match. If authorized, commit as `feat: connect Formula Lab to structured OpenAI generation`.

---

### Task 5: Algorithmic Art Director, generated formula flow, and one-shot repair

**Files:**
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaPrompts.swift`
- Modify: `StepsTrader/Experiments/FormulaLab/OpenAIFormulaClient.swift`
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaLabStore.swift`
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaLabView.swift`
- Modify: `Steps4Tests/OpenAIFormulaClientTests.swift`
- Modify: `Steps4Tests/FormulaLabStoreTests.swift`
- Modify: `THIRD_PARTY_NOTICES.md`

**Interfaces:**
- Consumes: `FormulaGenerating`, validator, compiler, candidate state machine.
- Produces: two-pass `directArt` then `generateFormula`, one normalized repair attempt, and algorithmic-art attribution.

- [ ] **Step 1: Write failing two-pass and repair-budget tests**

```swift
@MainActor
func testNewSessionDirectsArtOnceAndReusesDirectionForFeedback() async {
    let generator = RecordingFormulaGenerator()
    let store = makeLabStore(generator: generator)
    await store.generate(direction: "fragile coral")
    await store.feedback("more asymmetric")
    XCTAssertEqual(generator.artDirectionRequests.count, 1)
    XCTAssertEqual(generator.formulaRequests.count, 2)
}

@MainActor
func testCompileFailurePermitsExactlyOneAutomaticRepair() async {
    let generator = RecordingFormulaGenerator(alwaysInvalid: true)
    let store = makeLabStore(generator: generator)
    await store.generate(direction: "soft orbit")
    XCTAssertEqual(generator.repairRequests.count, 1)
    XCTAssertEqual(store.state.kind, .compileFailed)
}
```

- [ ] **Step 2: Run focused tests to verify RED**

Run the two modified test classes. Expected: incorrect pass counts and missing repair behavior.

- [ ] **Step 3: Wire the two-pass generation pipeline**

For a new direction call `directArt`, then call `generateFormula` with the returned direction. For Feedback and Skip, reuse the direction. Validate, compile, and install the draft in order. Preserve the current valid preview during every network/compile/probe state.

- [ ] **Step 4: Implement normalized one-shot repair**

Send only issue codes, line/column, normalized diagnostic messages, original function bodies, helper contract, and direction. Track `repairCount` on the generation token and refuse a second automatic attempt. Manual Feedback and Skip begin new generation tokens.

- [ ] **Step 5: Add algorithmic-art attribution**

Add an Apache-2.0 notice identifying the adapted instruction source at `https://github.com/anthropics/skills/tree/main/skills/algorithmic-art`. State that the p5.js viewer, branding, and templates are not included.

- [ ] **Step 6: Run focused tests and build**

Expected: two-pass, repair cap, validator, compiler, and app build pass.

- [ ] **Step 7: Review checkpoint**

Confirm no live request occurs in tests. If authorized, commit as `feat: add directed and repairable formula generation`.

---

### Task 6: Feedback ancestry, Skip diversity, and parameter exploration

**Files:**
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaModels.swift`
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaPrompts.swift`
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaLabStore.swift`
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaLabView.swift`
- Modify: `Steps4Tests/FormulaLabStoreTests.swift`
- Modify: `Steps4Tests/OpenAIFormulaClientTests.swift`

**Interfaces:**
- Consumes: current candidate, session trail, uniforms, formula client.
- Produces: immutable child candidates, capped structural rejection memory, seed regeneration, and local slider updates.

- [ ] **Step 1: Write failing ancestry/diversity/uniform tests**

```swift
@MainActor
func testFeedbackCreatesChildWithoutMutatingKeptParent() async {
    let store = makeFixtureLabStore()
    let parent = try await store.keepCurrent()
    await store.feedback("slower breathing")
    XCTAssertEqual(store.currentCandidate?.parentID, parent.id)
    XCTAssertEqual(try store.candidateStore.load(id: parent.id), parent)
}

@MainActor
func testParameterAndSeedChangesDoNotCompileOrCallAPI() {
    let store = makeFixtureLabStore()
    store.setParameter(id: "radius", value: 0.62)
    store.regenerateSeed()
    XCTAssertEqual(store.metrics.compileRequestCount, 0)
    XCTAssertEqual(store.metrics.apiRequestCount, 0)
}
```

- [ ] **Step 2: Run focused tests to verify RED**

Expected: missing parent preservation and local update behavior.

- [ ] **Step 3: Implement immutable Feedback ancestry**

Each refinement creates a new UUID and parent UUID, appends only the latest feedback to the inherited history, sends the parent bodies/parameters and optional 512×512 preview, and never overwrites a kept parent package.

- [ ] **Step 4: Implement structural Skip memory**

Derive compact traits from rationale, SDF/helper usage, motion intent, and topology labels; keep at most 20 records. The Skip prompt requires different topology or motion logic and explicitly says numeric-only variation is insufficient. Once the successor is active, evict the rejected pipeline unless a kept or session-history candidate still references it.

- [ ] **Step 5: Implement uniform-only exploration**

Clamp sliders to descriptor bounds, update renderer uniforms, persist the current values only on Keep, and regenerate `UInt64` seed locally. `Refine with AI` includes current parameter values and seed in the request.

- [ ] **Step 6: Run focused tests and build**

Expected: ancestry, diversity memory, no-recompile metrics, and app build pass.

- [ ] **Step 7: Review checkpoint**

If authorized, commit as `feat: refine and explore generated formulas`.

---

### Task 7: Probe runner and deterministic quality gates

**Files:**
- Create: `StepsTrader/Experiments/FormulaLab/FormulaProbeRunner.swift`
- Create: `Steps4Tests/FormulaProbeRunnerTests.swift`
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaMetalRenderer.swift`
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaLabStore.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: compiled pipeline and offscreen renderer.
- Produces: measurements stored in the existing `FormulaProbeSummary`, plus `FormulaProbeWarning`, `FormulaProbeFailure`, and `FormulaProbeRunner.run(pipeline:candidate:) async`.

- [ ] **Step 1: Write failing metric tests with synthetic frames**

```swift
func testCoverageRejectsAlwaysEmptyAndAlwaysFullFrames() {
    XCTAssertThrowsError(try FormulaProbeMetrics.evaluate(frames: .emptyFiveFrames))
    XCTAssertThrowsError(try FormulaProbeMetrics.evaluate(frames: .fullFiveFrames))
}

func testMotionAndLoopMetricsSeparateStaticFromClosedAnimation() throws {
    let result = try FormulaProbeMetrics.evaluate(frames: .movingClosedLoop)
    XCTAssertGreaterThan(result.motionScore, 0)
    XCTAssertLessThan(result.loopDelta, 0.03)
}
```

- [ ] **Step 2: Register files and verify RED**

Run `FormulaProbeRunnerTests`. Expected: missing probe symbols.

- [ ] **Step 3: Add reusable offscreen render API**

Render a supplied phase into a private `.bgra8Unorm` texture at an exact size, wait for command-buffer completion off the main actor, and return RGBA bytes plus GPU timing when available. The preview and exporter share this render path.

- [ ] **Step 4: Implement deterministic probes**

Render 128×128 at phases 0, 0.25, 0.5, 0.75, and 1. Compute foreground coverage from alpha/luminance distance to background, adjacent-frame normalized difference, phase-zero/phase-one difference, invalid pixel count, and maximum GPU duration. Reject command failures, invalid pixels, universal coverage outside 1% through 90%, requested-but-static motion, excessive loop delta, or any frame above 16.7 ms; emit warnings for borderline motion/loop values.

- [ ] **Step 5: Insert probing between compile and preview**

Only install a new candidate after a passing probe. On failure keep the prior valid pipeline visible and expose Repair or Skip. Save the summary into the candidate manifest.

- [ ] **Step 6: Run probe/store tests and build**

Expected: synthetic metric tests pass; Metal-only tests skip solely when the host exposes no device.

- [ ] **Step 7: Review checkpoint**

If authorized, commit as `feat: validate generated formula quality on device`.

---

### Task 8: PNG, MP4, portable document, and production handoff

**Files:**
- Create: `StepsTrader/Experiments/FormulaLab/FormulaExporter.swift`
- Create: `Steps4Tests/FormulaExporterTests.swift`
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaCandidateStore.swift`
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaCollectionView.swift`
- Modify: `StepsTrader/Experiments/FormulaLab/FormulaLabStore.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: candidate, assembled source, offscreen renderer, probe summary.
- Produces: `FormulaExporting`, `FormulaExporter.exportPNG`, `exportLoopMP4`, `exportPortableDocument`, and `exportProductionHandoff`.

- [ ] **Step 1: Write failing export contract tests**

```swift
func testPortableManifestRoundTripsWithoutSecrets() throws {
    let data = try FormulaExporter.fixture().portableDocument(for: FormulaFixtures.candidate(seed: 9))
    let text = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertFalse(text.localizedCaseInsensitiveContains("authorization"))
    XCTAssertFalse(text.localizedCaseInsensitiveContains("api_key"))
    XCTAssertEqual(try JSONDecoder().decode(FormulaCandidate.self, from: data).seed, 9)
}

func testCancelledExportLeavesNoFinalOrTemporaryFile() async {
    let destination = temporaryDirectory().appendingPathComponent("loop.mp4")
    await XCTAssertThrowsCancellationError {
        try await FormulaExporter.slowFixture().exportLoopMP4(candidate: FormulaFixtures.candidate(), to: destination)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path + ".partial"))
}
```

- [ ] **Step 2: Register files and verify RED**

Run `FormulaExporterTests`. Expected: missing exporter symbols.

- [ ] **Step 3: Implement deterministic PNG export**

Render offscreen at 2048×2048 with user-selected phase or zero, encode sRGB PNG through Core Image/ImageIO, support opaque/transparent background, and add UUID, seed, schema version, and philosophy-name metadata. Prompt text is excluded unless the user opts in.

- [ ] **Step 4: Implement looped MP4 export**

Use `AVAssetWriter`, H.264, 1080×1080, 30 FPS, and 120 frames covering phase `frameIndex / 120`. Render into pixel buffers through the shared offscreen path, check cancellation per frame, write to a `.partial` sibling, and atomically move only after successful writer completion.

- [ ] **Step 5: Implement portable JSON and production handoff**

Portable JSON is sorted, human-readable `FormulaCandidate` data without media or credentials. Production handoff creates a directory containing `<slug>.metal`, `<slug>.formula.json`, PNG, optional MP4, and `ATTRIBUTION.txt`; verify the assembled source hash before writing.

- [ ] **Step 6: Connect export UI and lazy video cache**

Expose phase/background/media options, progress, cancellation, share sheet, and errors. Cache `preview.mov` inside a kept candidate only after a successful first video export. External shared files remain untouched when the candidate is deleted.

- [ ] **Step 7: Run exporter tests and full automated verification**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all unit tests and Debug build pass.

- [ ] **Step 8: Run physical-device acceptance**

Install Debug on the development iPhone; test Keychain enter/replace/relaunch/delete, live generation, 60 FPS or visible adaptive scale, Feedback/Back/Keep/Skip, collection reload/delete, offline saved animation, PNG/MP4/JSON/handoff opening, background pause, Reduce Motion, Low Power Mode, and failed-compile recovery. Record device model, OS, p95 frame duration, and any probe warning in the task handoff.

- [ ] **Step 9: Final review checkpoint**

Run `git diff --check`, inspect new files for credential logging and RELEASE reachability, and compare every acceptance item to the design spec. If authorized, commit as `feat: export Formula Lab candidates and handoffs`.
