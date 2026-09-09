# Shader Roulette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and privately publish a polished one-page generative-art engine that creates reproducible animated 2D, 3D, and hybrid shader compositions from a seed.

**Architecture:** A static React/Vite Site keeps product UI separate from a deterministic visual-genome generator and a canvas rendering adapter. WebGL2 renders one parameterized fragment shader with geometry/material selectors, while a deterministic Canvas 2D renderer supplies graceful fallback and automated snapshot invariants.

**Tech Stack:** OpenAI Sites Vinext starter, React, TypeScript, WebGL2/GLSL ES 3.00, Canvas 2D, CSS, Node test runner.

**Spec:** `docs/superpowers/specs/2026-09-09-shader-roulette-design.md`

## Global Constraints

- Site root is `web/shader-roulette/`; do not modify the existing iOS application or other web prototypes.
- The app is one route, static-only, with no accounts, database, analytics, uploads, or persistence beyond the URL seed.
- The same unsigned 32-bit seed must always produce the same frozen visual genome.
- Structural values never reroll during animation; only the time uniform changes.
- Include six reachable geometry families: organism, relic, ribbon, glyph, field, and constellation.
- Include seven compatible material families: matte, glass, film, plasma, metal, ink, and contour.
- Support mouse, touch, Space-key reroll, pause/play, seed copy, seed URL restoration, and PNG download.
- Respect `prefers-reduced-motion`; preserve the artwork identity as a still image.
- Provide Canvas 2D fallback when WebGL2 is unavailable or cannot initialize.
- Keep controls at least 44 CSS pixels in both dimensions and maintain readable contrast on every generated background.
- Render a new candidate in bounded time; after six rejected candidates, return a safe fallback genome.
- Cap preview device pixel ratio at 2 and keep export resolution independent from preview resolution.

---

### Task 1: Scaffold the isolated Site and deterministic genome core

**Files:**
- Create: `web/shader-roulette/` through the Sites starter
- Modify: `web/shader-roulette/package.json`
- Create: `web/shader-roulette/app/lib/generative/types.ts`
- Create: `web/shader-roulette/app/lib/generative/random.ts`
- Create: `web/shader-roulette/app/lib/generative/genome.ts`
- Create: `web/shader-roulette/app/lib/generative/genome.test.ts`
- Create: `web/shader-roulette/.openai/hosting.json`

**Interfaces:**
- Produces: `GeometryFamily`, `MaterialFamily`, `DimensionMode`, `PaletteRoles`, `VisualGenome` types.
- Produces: `normalizeSeed(value: string | number): number`, `mulberry32(seed: number): () => number`, and `generateGenome(seed: number): VisualGenome`.
- Produces: `isGenomeValid(genome: VisualGenome): boolean` for tests and candidate rejection.

- [ ] **Step 1: Scaffold the project and install its dependencies**

Run from an empty `web/shader-roulette/` directory:

```bash
npm create --yes @openai/sites@0.3.0 . -- --yes --add-ons shadcn --install
```

Keep the generated package manager, lockfile, application structure, and development scripts. Configure the generated Site as static-only and ensure `.openai/hosting.json` points `static.directory` at the starter's public build output.

- [ ] **Step 2: Add the deterministic generator test script and write failing tests**

Add this script to `package.json` without removing starter scripts:

```json
{
  "scripts": {
    "test": "node --experimental-strip-types --test app/lib/**/*.test.ts"
  }
}
```

Create `genome.test.ts` with these assertions:

```ts
import assert from "node:assert/strict";
import test from "node:test";
import { generateGenome, isGenomeValid } from "./genome.ts";

test("the same seed produces the same genome", () => {
  assert.deepEqual(generateGenome(0x8f31), generateGenome(0x8f31));
});

test("a broad seed corpus stays within structural constraints", () => {
  for (let seed = 0; seed < 2048; seed += 1) {
    assert.equal(isGenomeValid(generateGenome(seed)), true, `seed ${seed}`);
  }
});

test("the seed corpus reaches every family and dimensional mode", () => {
  const genomes = Array.from({ length: 4096 }, (_, seed) => generateGenome(seed));
  assert.deepEqual(new Set(genomes.map((value) => value.geometry)),
    new Set(["organism", "relic", "ribbon", "glyph", "field", "constellation"]));
  assert.deepEqual(new Set(genomes.map((value) => value.dimension)),
    new Set(["graphic", "volumetric", "hybrid"]));
});

test("rare mutations never stack", () => {
  for (let seed = 0; seed < 4096; seed += 1) {
    assert.ok(generateGenome(seed).rareMutation.length <= 1);
  }
});
```

- [ ] **Step 3: Run the tests and confirm the generator is absent**

Run: `npm test`

Expected: FAIL because `./genome.ts` and its exports do not exist.

- [ ] **Step 4: Define the stable genome contract**

Create `types.ts` with string unions for the exact family names above and this shape:

```ts
export type VisualGenome = {
  seed: number;
  dimension: "graphic" | "volumetric" | "hybrid";
  geometry: "organism" | "relic" | "ribbon" | "glyph" | "field" | "constellation";
  material: "matte" | "glass" | "film" | "plasma" | "metal" | "ink" | "contour";
  palette: { background: string; dark: string; light: string; accent: string; emission: string };
  params: {
    scale: number; rotation: number; lobes: number; warp: number; hollow: number;
    thickness: number; roughness: number; metallic: number; transmission: number;
    bloom: number; grain: number; cameraZ: number; satelliteCount: number;
  };
  motion: { tempo: number; breathe: number; orbit: number; phase: number };
  rareMutation: [] | ["slice" | "hollow-core" | "chromatic-edge" | "satellite" | "flatland"];
  title: string;
};
```

- [ ] **Step 5: Implement seeded generation, compatibility, and bounded rejection**

Implement `mulberry32` using integer operations and `normalizeSeed` using unsigned coercion. In `generateGenome`, derive all choices from a new RNG created from the normalized seed. Use weighted family arrays, family-to-dimension mapping, and a material compatibility table. Validate these exact ranges:

```ts
const LIMITS = {
  scale: [0.62, 1.18], warp: [0.04, 0.72], hollow: [0, 0.68],
  thickness: [0.04, 0.34], roughness: [0.08, 0.92], bloom: [0, 0.55],
  cameraZ: [2.4, 4.8], satelliteCount: [0, 4], tempo: [0.045, 0.22],
} as const;
```

Score occupied area, complexity, contrast, element count, and total-effects budget from genome values. Accept scores between 0.28 and 0.82. Attempt at most six correlated candidates using seeds mixed with `0x9e3779b9`; if none pass, return a matte organism with zero rare mutations and the original seed.

- [ ] **Step 6: Run generator tests**

Run: `npm test`

Expected: PASS for determinism, bounds, family reachability, and mutation limits.

- [ ] **Step 7: Commit the generator slice**

```bash
git add web/shader-roulette
git commit -m "feat: add shader roulette visual genome"
```

---

### Task 2: Build coordinated palettes and the parameterized GLSL scene

**Files:**
- Create: `web/shader-roulette/app/lib/generative/color.ts`
- Create: `web/shader-roulette/app/lib/generative/color.test.ts`
- Create: `web/shader-roulette/app/lib/render/shaders.ts`
- Create: `web/shader-roulette/app/lib/render/shaders.test.ts`
- Modify: `web/shader-roulette/app/lib/generative/genome.ts`

**Interfaces:**
- Consumes: `VisualGenome` and seeded RNG from Task 1.
- Produces: `makePalette(random: () => number, material: MaterialFamily): PaletteRoles`.
- Produces: `VERTEX_SHADER_SOURCE` and `FRAGMENT_SHADER_SOURCE` strings.
- Produces: stable numeric `GEOMETRY_IDS`, `MATERIAL_IDS`, and `DIMENSION_IDS` records shared by the renderer.

- [ ] **Step 1: Write failing palette and shader-contract tests**

```ts
test("generated palettes use parseable opaque hex roles", () => {
  const palette = makePalette(mulberry32(42), "film");
  for (const color of Object.values(palette)) assert.match(color, /^#[0-9a-f]{6}$/i);
});

test("background and light retain readable luminance separation", () => {
  for (let seed = 0; seed < 512; seed += 1) {
    const palette = makePalette(mulberry32(seed), "matte");
    assert.ok(Math.abs(relativeLuminance(palette.light) - relativeLuminance(palette.background)) >= 0.36);
  }
});

test("the fragment shader declares every renderer uniform", () => {
  for (const name of ["u_resolution", "u_time", "u_geometry", "u_material", "u_dimension",
    "u_palette0", "u_palette1", "u_palette2", "u_palette3", "u_params0", "u_params1"])
    assert.match(FRAGMENT_SHADER_SOURCE, new RegExp(`uniform\\\\s+[^;]+\\\\s+${name}\\\\s*;`));
});
```

- [ ] **Step 2: Run the focused tests and confirm failure**

Run: `npm test -- app/lib/generative/color.test.ts app/lib/render/shaders.test.ts`

Expected: FAIL because palette and shader modules do not exist.

- [ ] **Step 3: Implement perceptual palette roles**

Implement OKLCH-to-sRGB conversion locally with channel clamping. Choose one harmony per seed from analogous, split-complementary, warm/cool, and restrained monochrome. Keep background lightness in `0.035...0.15`, body light in `0.68...0.92`, and accent chroma in `0.08...0.24`. Material-specific adjustments make metal less saturated, plasma emissive, glass lighter, and ink use two quiet roles plus one accent.

- [ ] **Step 4: Implement the full-screen vertex shader and shared fragment pipeline**

The vertex shader passes clip-space positions to the fragment shader. The fragment shader must include:

- hash and value-noise helpers driven by fixed uniforms rather than frame-varying random input;
- smooth union, subtraction, and intersection operators;
- sphere, rounded box, torus, capsule, superellipse, arc, and segment distance functions;
- one `mapScene(vec3)` switch implementing organism, relic, ribbon, and constellation 3D geometry;
- one `mapGraphic(vec2)` switch implementing glyph and field geometry plus hybrid overlays;
- a ray marcher capped at 76 steps, maximum distance 8.0, and epsilon increasing with travel distance;
- tetrahedral normal estimation, soft shadow, ambient occlusion, key/rim lighting, Fresnel, and material switch;
- ACES-style tone mapping, subtle vignette, seeded grain, and bloom approximation restricted by `u_params1`;
- alpha fixed to `1.0` for the visible canvas.

Use `u_time` only for low-amplitude deformation, phase, and camera drift. Family identity, palette, element count, and topology are uniform-derived and time-invariant.

- [ ] **Step 5: Run palette and shader-contract tests**

Run: `npm test`

Expected: PASS.

- [ ] **Step 6: Commit the visual vocabulary**

```bash
git add web/shader-roulette/app/lib/generative web/shader-roulette/app/lib/render
git commit -m "feat: add procedural shader vocabulary"
```

---

### Task 3: Implement WebGL2 rendering, context recovery, and Canvas fallback

**Files:**
- Create: `web/shader-roulette/app/lib/render/webgl-renderer.ts`
- Create: `web/shader-roulette/app/lib/render/canvas-fallback.ts`
- Create: `web/shader-roulette/app/lib/render/renderer.ts`
- Create: `web/shader-roulette/app/lib/render/renderer.test.ts`

**Interfaces:**
- Consumes: `VisualGenome`, shader sources, and numeric family IDs.
- Produces: `createRenderer(canvas: HTMLCanvasElement, onError: (message: string) => void): SceneRenderer`.
- Produces: `SceneRenderer` with `setGenome`, `setPaused`, `resize`, `renderFrame`, `exportPng`, and `dispose` methods.
- Produces: `drawFallback(ctx: CanvasRenderingContext2D, genome: VisualGenome, width: number, height: number, time: number): void`.

- [ ] **Step 1: Write failing renderer-selection tests with a minimal fake canvas**

```ts
test("renderer uses deterministic fallback when WebGL2 is absent", () => {
  const canvas = fakeCanvas({ webgl2: null, context2d: fake2dContext() });
  const renderer = createRenderer(canvas as unknown as HTMLCanvasElement, () => {});
  assert.equal(renderer.kind, "canvas2d");
});

test("preview dimensions cap device pixel ratio at two", () => {
  assert.deepEqual(pixelSize(375, 667, 3), { width: 750, height: 1334 });
});
```

- [ ] **Step 2: Run renderer tests and confirm failure**

Run: `npm test -- app/lib/render/renderer.test.ts`

Expected: FAIL because renderer selection and pixel sizing do not exist.

- [ ] **Step 3: Implement the WebGL2 adapter**

Compile and link the shared shaders once. Cache uniform locations and a single fullscreen-triangle vertex array. `setGenome` converts hex colors to linear RGB, packs genome values into two `vec4` parameter uniforms, and uploads integer family IDs. `renderFrame` updates resolution and time, draws three vertices, and performs no allocation in the animation loop.

Handle `webglcontextlost` with `preventDefault()` and pause drawing. On `webglcontextrestored`, rebuild GPU resources and re-upload the current genome. Shader errors call `onError` with a user-readable message and trigger fallback selection.

- [ ] **Step 4: Implement the Canvas 2D fallback**

Use the same seed and palette to draw a family-specific analytic silhouette from 96 radial samples, or a rounded path/ribbon for graphic families. Apply two radial gradients, one negative-space cutout when `hollow > 0.2`, limited blur, and seeded texture strokes. Wrap drawing in `save()`/`restore()`, clear transforms each frame, and never use `Math.random()`.

- [ ] **Step 5: Implement sizing, animation control, and export**

`pixelSize(cssWidth, cssHeight, devicePixelRatio)` clamps the ratio to `[1, 2]`. Preview resize uses `ResizeObserver`. PNG export creates an offscreen 2048×2048 canvas, renders the frozen genome at the current resting phase, and resolves with `canvas.toBlob("image/png")`; reject with a concise error if the blob is null.

- [ ] **Step 6: Run renderer and complete tests**

Run: `npm test`

Expected: PASS.

- [ ] **Step 7: Commit the rendering layer**

```bash
git add web/shader-roulette/app/lib/render
git commit -m "feat: render seeded WebGL scenes with fallback"
```

---

### Task 4: Build the gallery-like interaction and first meaningful preview

**Files:**
- Replace: `web/shader-roulette/app/page.tsx`
- Modify: `web/shader-roulette/app/layout.tsx`
- Replace: `web/shader-roulette/app/globals.css`
- Create: `web/shader-roulette/app/components/shader-stage.tsx`
- Create: `web/shader-roulette/app/components/control-dock.tsx`
- Create: `web/shader-roulette/app/lib/seed-url.ts`
- Create: `web/shader-roulette/app/lib/seed-url.test.ts`

**Interfaces:**
- Consumes: `generateGenome` and `createRenderer`.
- Produces: `readSeed(search: string): number | null`, `seedHref(seed: number, base: URL): string`, and `newRandomSeed(): number` using `crypto.getRandomValues`.
- Produces: `ShaderStage` callbacks `onReroll`, `onError`, and `onReady`.
- Produces: `ControlDock` callbacks `onReroll`, `onTogglePaused`, `onCopy`, and `onDownload`.

- [ ] **Step 1: Write failing seed URL tests**

```ts
test("reads decimal and hexadecimal seeds", () => {
  assert.equal(readSeed("?seed=36657"), 36657);
  assert.equal(readSeed("?seed=0x8f31"), 36657);
});

test("rejects missing, negative, and overflowing seeds", () => {
  assert.equal(readSeed(""), null);
  assert.equal(readSeed("?seed=-1"), null);
  assert.equal(readSeed("?seed=4294967296"), null);
});
```

- [ ] **Step 2: Run seed tests and confirm failure**

Run: `npm test -- app/lib/seed-url.test.ts`

Expected: FAIL because seed URL helpers do not exist.

- [ ] **Step 3: Implement URL seed restoration and mutation**

Parse only unsigned 32-bit decimal or `0x` hexadecimal values. On reroll, use `crypto.getRandomValues(new Uint32Array(1))[0]`, replace the URL query with `history.replaceState`, and update the title suffix. Copy the full seed URL with the Clipboard API and use a temporary textarea fallback only when Clipboard is unavailable.

- [ ] **Step 4: Implement the first coherent product surface**

Make `page.tsx` a client page with a full-viewport `ShaderStage`, top-left wordmark/title, and bottom `ControlDock`. The canvas itself rerolls on pointer activation. Space rerolls unless focus is inside a button or link. Escape never changes state. The generated canvas description reads: `"${title}: ${dimension} ${geometry}, ${material} material"`.

Use the starter's installed tooltip primitive for icon-only pause, copy, and download actions. Keep the visible primary action as the text button `ЕЩЁ`.

- [ ] **Step 5: Apply the visual system in shared theme tokens**

Define near-black background `#08090b`, warm paper text `#f3efe7`, quiet border `rgba(255,255,255,.14)`, and translucent dock surface `rgba(11,12,15,.58)`. Use a restrained grotesk/system font stack, large fluid generated title, 999px pill controls, 44px minimum targets, visible `:focus-visible` rings, subtle CSS grain, and no card grid. Desktop controls float with generous negative space; below 640px they form a bottom-centered dock inside safe-area insets.

- [ ] **Step 6: Add reduced motion and prepared-scene crossfade**

Read `matchMedia("(prefers-reduced-motion: reduce)")`. In reduced motion, set renderer paused and swap genomes immediately. Otherwise, render current and next scenes in two stacked canvases; once the next renderer has drawn its first frame, crossfade opacity for 420ms, dispose the old renderer, and ignore intermediate rerolls except the newest seed.

- [ ] **Step 7: Set product metadata and remove starter content**

Set title to `Shader Roulette`, description to `A tiny engine for impossible, repeatable forms.`, language to Russian-compatible UTF-8 markup, and remove unused starter-only logos/content. Do not create social-preview imagery or metadata.

- [ ] **Step 8: Start the development preview and perform the first handoff**

Run the generated development script in a retained session. Request the exact printed local URL once and require a successful response. Open that URL in the Codex panel only after the shader stage, real title, `ЕЩЁ` control, and theme compile without a blocking error.

- [ ] **Step 9: Commit the interaction slice**

```bash
git add web/shader-roulette/app
git commit -m "feat: add shader roulette gallery experience"
```

---

### Task 5: Complete actions, accessibility, tests, and private publishing

**Files:**
- Modify: `web/shader-roulette/app/page.tsx`
- Modify: `web/shader-roulette/app/components/control-dock.tsx`
- Modify: `web/shader-roulette/app/components/shader-stage.tsx`
- Modify: `web/shader-roulette/app/globals.css`
- Create: `web/shader-roulette/app/lib/title.ts`
- Create: `web/shader-roulette/app/lib/title.test.ts`
- Modify: `web/shader-roulette/README.md`

**Interfaces:**
- Consumes: renderer export, seed URL helpers, and `VisualGenome`.
- Produces: `titleForGenome(genome: VisualGenome): string` from deterministic adjective/noun dictionaries.
- Completes all visible actions and status announcements.

- [ ] **Step 1: Write deterministic title tests**

```ts
test("titles are deterministic and include a compact seed suffix", () => {
  const genome = generateGenome(0x8f31);
  assert.equal(titleForGenome(genome), titleForGenome(genome));
  assert.match(titleForGenome(genome), / #[0-9A-F]{4}$/);
});

test("different visual families do not all use the same noun", () => {
  const titles = Array.from({ length: 128 }, (_, seed) => titleForGenome(generateGenome(seed)));
  assert.ok(new Set(titles.map((value) => value.split(" ")[1])).size >= 12);
});
```

- [ ] **Step 2: Run title tests and confirm failure**

Run: `npm test -- app/lib/title.test.ts`

Expected: FAIL because title generation does not exist.

- [ ] **Step 3: Implement authored deterministic naming**

Create family-specific noun lists and material/motion-sensitive adjectives. Select them from seed-mixed indices without consuming or mutating the genome RNG. Format the low 16 seed bits as four uppercase hexadecimal digits.

- [ ] **Step 4: Finish copy, pause, download, and error states**

Copy announces `Ссылка скопирована` in an `aria-live="polite"` status. Pause changes its accessible label and icon to Play and freezes time at the current value. Download names files `shader-roulette-<8-digit-hex-seed>.png`, disables only while encoding, and reports export failures inline without dismissing the scene. A WebGL failure shows a quiet `Canvas mode` badge and retains all controls.

- [ ] **Step 5: Check the representative seed corpus programmatically**

Run: `npm test`

Expected: all deterministic, bounds, family reachability, palette, shader-contract, fallback, URL, and title tests PASS.

- [ ] **Step 6: Build the production Site**

Run: `npm run build`

Expected: exit code 0, no TypeScript or shader-source import errors, and the configured static output directory exists.

- [ ] **Step 7: Verify the build response without browser QA**

Keep the retained development server alive. Request its exact local URL and require a success response. Do not take screenshots, inspect the DOM, click controls, or resize the browser because visual browser QA was not requested.

- [ ] **Step 8: Commit the completed Site**

```bash
git add web/shader-roulette
git commit -m "feat: complete shader roulette site"
```

- [ ] **Step 9: Save, deploy, and verify a private Sites version**

Use the existing `project_id` from `.openai/hosting.json`, or register the Site once if it is absent. Invoke the sites-hosting workflow, save one version from the successful static build, deploy it privately, and verify terminal deployment success before returning its URL. Stop the retained development session after publishing completes.

