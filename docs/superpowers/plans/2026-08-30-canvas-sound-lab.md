# Canvas Sound Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish a phone-first browser instrument whose ambient composition responds to Steps, Sleep, Glitch, up to ten happening seeds, Remix, and an XY touch lead.

**Architecture:** Create a standalone Sites project in `canvas-sound-lab/`. Keep seeded music generation pure and testable, isolate Web Audio graph ownership in one engine, and let the React page coordinate controls, a Canvas 2D visual field, and Pointer Events without any production-app dependency.

**Tech Stack:** React, TypeScript, Vite/Vinext Sites scaffold, Web Audio API, Canvas 2D, Vitest, CSS.

**Spec:** `docs/superpowers/specs/2026-08-30-canvas-sound-lab-design.md`

## Global Constraints

- The demo is a standalone site and must not modify or import the Nowhere iOS application.
- Audio starts only after an explicit Sound interaction and suspends when the document is hidden.
- Happening count is limited to exactly ten; Undo and Reset can restore capacity.
- Remix preserves Steps, Sleep, Glitch, and happening count.
- Glitch is bounded to 0...100 and output gain remains conservative at every value.
- No authentication, analytics, external audio files, HealthKit access, or server persistence.
- The primary target is iPhone Safari with 44-point minimum touch targets and safe-area support.

---

### Task 1: Scaffold the standalone Site and define pure seeded music state

**Files:**
- Create: `canvas-sound-lab/` from the pinned Sites scaffold
- Create: `canvas-sound-lab/lib/music.ts`
- Create: `canvas-sound-lab/lib/music.test.ts`
- Modify: `canvas-sound-lab/package.json`

**Interfaces:**
- Produces: `createMusicWorld(seed: number): MusicWorld`
- Produces: `createHappeningSeed(worldSeed: number, index: number, entropy: number): HappeningSeed`
- Produces: `remixState(state: LabState, entropy: number): LabState`
- Produces: `canAddHappening(seeds: HappeningSeed[]): boolean`

- [ ] **Step 1: Initialize the site inside `canvas-sound-lab/` and install its generated dependencies**

Use the pinned Sites scaffold without database, upload, authentication, or connector add-ons.

- [ ] **Step 2: Write failing unit tests for deterministic worlds, the ten-seed limit, Undo, and Remix preservation**

```ts
expect(createMusicWorld(42)).toEqual(createMusicWorld(42))
expect(canAddHappening(Array.from({ length: 10 }, makeSeed))).toBe(false)
expect(remixState(state, 99)).toMatchObject({ steps: state.steps, sleep: state.sleep, glitch: state.glitch })
expect(remixState(state, 99).happenings).toHaveLength(state.happenings.length)
```

- [ ] **Step 3: Run the focused test and verify the missing-module failure**

Run the generated test script against `lib/music.test.ts`; expect failure because `lib/music.ts` does not exist.

- [ ] **Step 4: Implement seeded random generation, scale selection, parameter mappings, and immutable state helpers**

Use a small integer PRNG whose output is stable across reloads. Clamp Steps to `0...20_000`, Sleep to `0...10`, Glitch to `0...100`, and seed count to `0...10`.

- [ ] **Step 5: Run the focused test and commit the passing state model**

Expected: all music-state assertions pass.

### Task 2: Build the bounded Web Audio engine

**Files:**
- Create: `canvas-sound-lab/lib/audio-engine.ts`
- Create: `canvas-sound-lab/lib/audio-params.test.ts`

**Interfaces:**
- Consumes: `MusicWorld`, `HappeningSeed`, and normalized mappings from `lib/music.ts`
- Produces: `CanvasAudioEngine.start(state): Promise<void>`
- Produces: `CanvasAudioEngine.update(state): void`
- Produces: `CanvasAudioEngine.audition(seed): void`
- Produces: `CanvasAudioEngine.beginLead(x, y): void`, `moveLead(x, y, speed): void`, `endLead(): void`
- Produces: `CanvasAudioEngine.stop(): Promise<void>` and `destroy(): void`

- [ ] **Step 1: Write failing tests for parameter clamps and monotonic Steps, Sleep, and Glitch mappings**

```ts
expect(audioParams({ steps: -1, sleep: 20, glitch: 140 })).toMatchObject({ glitch: 1 })
expect(audioParams(highSteps).bpm).toBeGreaterThan(audioParams(lowSteps).bpm)
expect(audioParams(highGlitch).detuneCents).toBeGreaterThan(audioParams(lowGlitch).detuneCents)
```

- [ ] **Step 2: Run the focused test and verify failure before implementation**

- [ ] **Step 3: Implement the graph and scheduler**

Create a master filter, delay feedback path, algorithmic reverb delay network, compressor, and `0.38` maximum master gain. Use a bounded look-ahead scheduler for the background and happening roles. Ramp live parameter changes, clear scheduling timers when stopped, and never create more than the fixed background voices, ten bounded happening events, and one lead voice.

- [ ] **Step 4: Implement Sound lifecycle and visibility handling hooks**

Resume only from the Sound interaction. On `visibilitychange` to hidden, stop scheduling and suspend the context. Expose an engine state callback so the interface can accurately show Off, Starting, On, or Needs Tap.

- [ ] **Step 5: Run tests and commit the audio engine**

Expected: parameter tests pass without requiring an actual browser audio device.

### Task 3: Create the first meaningful mobile interface slice

**Files:**
- Modify: `canvas-sound-lab/app/page.tsx`
- Modify: `canvas-sound-lab/app/globals.css`
- Modify: `canvas-sound-lab/app/layout.tsx`

**Interfaces:**
- Consumes: pure state helpers from `lib/music.ts`
- Produces: one recognizable mobile viewport with the performance surface, Sound, three values, Happening, and Remix visible

- [ ] **Step 1: Replace all starter content with the Canvas Sound Lab shell**

Render the title, seed readout, abstract performance surface, Sound control, Steps/Sleep/Glitch values, Happening count, and bottom actions with realistic default state.

- [ ] **Step 2: Implement the visual direction and mobile layout**

Use CSS fields, grain, strong condensed typography, safe-area padding, portrait-first layout, and responsive landscape/desktop constraints. Do not add images or inline SVG illustration.

- [ ] **Step 3: Start the retained development preview and force one successful route response**

Require a non-error response from the exact local URL before presenting the first preview.

- [ ] **Step 4: Open the first meaningful preview in the app**

Keep the resulting browser tab as the single preview and later deployment handoff.

### Task 4: Connect controls, canvas visuals, and the XY lead

**Files:**
- Create: `canvas-sound-lab/components/PerformanceCanvas.tsx`
- Create: `canvas-sound-lab/components/ControlRack.tsx`
- Modify: `canvas-sound-lab/app/page.tsx`
- Modify: `canvas-sound-lab/app/globals.css`

**Interfaces:**
- Consumes: `CanvasAudioEngine` and `LabState`
- Produces: `PerformanceCanvas` pointer callbacks in normalized `0...1` coordinates
- Produces: accessible control callbacks for Sound, Add, Undo, Remix, and Reset

- [ ] **Step 1: Implement the animated background and touch trace**

Drive gradient motion from Steps, visual clarity from Sleep, and bounded scan-line/color displacement from Glitch. Honor `prefers-reduced-motion`.

- [ ] **Step 2: Implement Pointer Events for the lead**

Capture the active pointer, prevent page scrolling only on the instrument surface, normalize coordinates, estimate movement speed from successive events, and always release the lead on pointer up, cancel, or lost capture.

- [ ] **Step 3: Wire every control to state and audio**

Happening auditions and appends one seed only below ten. Undo removes the last. Remix changes the world seed but preserves inputs and count. Reset returns defaults and clears seeds. Sliders update both audio and visuals while dragging.

- [ ] **Step 4: Add accessible status and unsupported-audio behavior**

Provide `aria-live` announcements for sound state, remix, and `10/10`. Disable unavailable actions instead of allowing silent failure.

- [ ] **Step 5: Run tests and commit the completed interaction**

Expected: state tests pass and the page compiles without browser runtime errors.

### Task 5: Validate, build, and publish

**Files:**
- Modify: `canvas-sound-lab/app/layout.tsx`
- Modify: `canvas-sound-lab/.openai/hosting.json`

**Interfaces:**
- Consumes: the complete client-only site
- Produces: a deployed owner-accessible Sites URL

- [ ] **Step 1: Replace starter metadata with Canvas Sound Lab title and description**

Use `Canvas Sound Lab` and a concise description of the Steps, Sleep, Glitch, happenings, Remix, and touch instrument.

- [ ] **Step 2: Run all unit tests and the production build**

Expected: every test passes and the deployment build succeeds.

- [ ] **Step 3: Verify required interaction invariants from the compiled source**

Confirm explicit audio start, ten-seed clamp, preserved Remix inputs, pointer cancellation, hidden-page suspension, conservative master gain, and no production-app imports.

- [ ] **Step 4: Publish the validated site privately**

Create or reuse the Site record, save the exact built version, deploy it with verified owner-only access, and wait for a successful status.

- [ ] **Step 5: Open the deployed URL in the existing preview tab and deliver the link**

The final handoff names the phone interactions to try and any iPhone audio caveat that still requires an explicit tap.
