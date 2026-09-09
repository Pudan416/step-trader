# Shader Roulette — design specification

## Product intent

Shader Roulette is a single-page generative-art toy whose only essential action is asking for another image. Every result should feel surprising and individually authored even though it is produced from a seed. The target is not unrestricted randomness: the engine combines a deliberately bounded visual vocabulary, correlated parameters, and quality checks so the output remains strange but attractive.

The page is for a person who wants immediate visual discovery, not a shader editor. It exposes no technical controls by default.

## Experience

The artwork fills almost the entire viewport on a dark, softly textured stage. Interface chrome is sparse and floats above the stage:

- a small `SHADER ROULETTE` wordmark;
- one dominant `ЕЩЁ` button;
- a compact seed label, copy action, pause/play action, and PNG download;
- a short generated title such as `Soft Rupture #8F31` that changes with the artwork.

Clicking `ЕЩЁ`, pressing Space, or clicking the artwork creates a new seed and crossfades into a new scene. The scene moves continuously but slowly enough to read as an object rather than a screensaver. The experience respects reduced-motion preferences by rendering the same identity as a still composition and replacing the crossfade with an immediate swap.

On phones the artwork remains full-bleed; controls collapse into a compact bottom dock with touch-sized targets. The generator must remain usable by keyboard and screen readers.

## Visual thesis

The direction is a dark contemporary gallery rather than a developer demo. Backgrounds use near-black ink, deep mineral hues, subtle grain, and a restrained bloom. Generated objects may be vivid, pearlescent, smoky, metallic, translucent, matte, or nearly monochrome. Typography and controls remain neutral so the artwork owns the page.

The engine avoids obvious stock-shader imagery: uniform neon blobs, generic glowing spheres, endless tunnel effects, visible debug grids, and arbitrary rainbow noise. Each scene gets one dominant gesture, one material logic, and a small coordinated palette.

## Generative engine

### Stable visual genome

A deterministic seed produces a frozen `VisualGenome`. The genome stores causes rather than pixels:

- dimensional mode: graphic 2D, volumetric 3D, or hybrid;
- geometry family and its topology parameters;
- composition gesture, camera, scale, rotation, and negative space;
- material family, palette roles, lighting, edge treatment, and atmosphere;
- motion amplitudes, phases, and tempo;
- rarity flags for unusual but safe mutations.

The same seed always recreates the same visual identity. Time changes only continuous motion and never rerolls structural parameters.

### Geometry vocabulary

The first release contains six coherent geometry families rather than a bag of independent primitives:

1. **Organism** — smooth asymmetric radial bodies with lobes, cavities, and controlled surface displacement.
2. **Relic** — rounded solids formed by unions and subtractions of superellipsoids, capsules, tori, and cut planes.
3. **Ribbon** — folded strips, knots, arcs, and membrane-like surfaces with readable silhouette and negative space.
4. **Glyph** — flat or shallow extruded symbols built from smooth 2D distance fields, counterforms, and offset outlines.
5. **Field** — mist, caustic membranes, interference bands, and luminous voids whose boundary still reads as one composition.
6. **Constellation** — a designed relationship between one anchor object and a few satellites; never an undifferentiated particle cloud.

3D families render through bounded ray marching of signed-distance fields. Graphic families render through analytic 2D distance fields. Hybrid scenes may place a sharp glyph or line gesture against one volumetric body, with strict limits on element count.

### Materials and lighting

Geometry and material are selected separately but connected by a compatibility table. Material families are:

- ceramic/matte;
- translucent glass;
- iridescent film;
- emissive plasma;
- brushed metal;
- soft gradient ink;
- contour/negative-space treatment.

Each material consumes a semantic palette: background, body dark, body light, accent, and optional emission. Palettes are generated in perceptual color space around one harmony strategy, then checked for contrast and excessive chroma. Lighting uses one key light, optional rim light, ambient occlusion, soft shadowing, and restrained bloom. Not every scene receives every effect.

### Curated randomness and rejection

The generator uses weighted choices, correlated ranges, and compatibility rules. For example, a complex silhouette receives a simpler material; a transparent material receives fewer overlapping forms; a highly saturated accent is balanced by a quiet background.

Before display, a candidate receives inexpensive structural scores derived from its genome: silhouette complexity, occupied area, negative-space balance, palette contrast, element count, and effect budget. Candidates outside the approved ranges are regenerated, up to a small fixed limit. The final attempt always falls back to a known-safe genome construction so the interface never stalls.

Rare mutations appear often enough to surprise but remain controlled: a single hard slice, a hollow core, chromatic edge splitting, a floating satellite, or an unusually flat composition. Multiple rare mutations do not stack freely.

## Rendering architecture

The site lives in `web/shader-roulette/` as a standalone static React/Vite application suitable for private Sites hosting.

The product is divided into small modules:

- `genome` turns a seed into a validated `VisualGenome`;
- `palette` generates coordinated color roles;
- `renderer` owns WebGL2 setup, shader compilation, uniforms, animation, resize, and context restoration;
- GLSL modules implement shared SDF geometry, ray marching, materials, lighting, and post-processing;
- `export` renders the current seed to an offscreen high-resolution target and downloads a PNG;
- the React page owns controls, accessibility, title/seed presentation, and transitions, but does not contain rendering math.

One general renderer consumes uniforms and small integer family selectors. It does not generate arbitrary GLSL strings for each click. This keeps rerolls fast, avoids shader-compilation pauses, and makes every seed reproducible.

## Data flow

1. Initial load reads an optional seed from the URL or creates a random 32-bit seed.
2. The generator derives and validates a genome.
3. The renderer receives the frozen genome and uploads its parameters as uniforms.
4. Animation advances only the time uniform.
5. `ЕЩЁ`, artwork click, or Space creates a new seed; the next scene is prepared before the crossfade begins.
6. The URL updates with the seed without navigation, allowing a result to be copied and revisited.
7. PNG export renders the current genome at a larger fixed resolution without changing the visible scene.

No account, server database, analytics, upload, or persistent collection is included.

## Failure handling

- If WebGL2 is unavailable or shader initialization fails, the page shows a composed Canvas 2D fallback using the same seed, palette, and graphic families.
- If the WebGL context is lost, animation pauses, the interface remains responsive, and the renderer restores the current genome when the context returns.
- PNG export reports a concise inline error if the browser blocks or runs out of memory, while preserving the current artwork.
- Rapid repeated clicks are coalesced so only the newest requested seed becomes visible.

## Performance and accessibility

The renderer caps device pixel ratio on dense screens and adapts ray-march steps to viewport size. It targets a stable 60 fps on a modern laptop and 30–60 fps on a recent phone. Export quality is independent from preview quality.

Controls have visible focus states, accessible names, and at least 44-pixel touch targets. Text and controls retain readable contrast over every generated background. Reduced motion freezes the scene at its designed resting phase. The canvas has a concise textual description containing the generated title, dimensional mode, geometry family, and material.

## Verification

Automated checks cover deterministic genome generation, parameter bounds, compatibility rules, fallback construction, URL seed parsing, and reduced-motion behavior. A production build must succeed.

The finished implementation will also be checked across a representative seed corpus to ensure:

- all six geometry families can be reached;
- 2D, 3D, and hybrid scenes appear;
- no candidate produces NaN/Infinity uniforms;
- identical seeds recreate identical genomes;
- layout and controls work at desktop and narrow mobile widths;
- keyboard generation, pause/play, copy, and PNG export behave correctly.

## Completion criteria

The project is complete when the private deployed page opens directly into a polished animated artwork; produces a visibly different, aesthetically coherent scene on every reroll; recreates scenes from their seed URLs; supports keyboard/touch controls and reduced motion; downloads a PNG; degrades gracefully without WebGL2; and passes its production build and deterministic generator tests.
