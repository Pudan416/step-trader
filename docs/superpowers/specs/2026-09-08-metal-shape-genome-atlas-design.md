# Metal Shape Genome Atlas — Design

Date: 2026-09-08

## Summary

Add a new, Metal-only generative-shape study above the existing “Формы × заполнения” matrix on the Nowhere Composition Atlas. The current matrix, controls, assets, and behavior remain unchanged.

The new study introduces one coherent family of closed procedural contours rather than more hand-enumerated circles, rounded polygons, and stars. A deterministic shape genome produces twelve curated presets across four morphological groups. A shared Metal rendering pipeline applies only compatible materials to each preset. A compact scene laboratory demonstrates which objects can act as centers, supporting forms, or accents.

The first version is an isolated laboratory and website study. It does not change the production daily-canvas generator or user-visible behavior in the shipping app.

## Product Intent

The shapes should look like computational objects belonging to the same world as the existing Nowhere snowflakes. They must be:

- closed silhouettes;
- deterministic from a seed;
- recognizably related without becoming near-duplicates;
- expressive through geometry and material behavior rather than icon-like subject matter;
- suitable for a quiet generative diary rather than a catalogue of decorative symbols;
- renderable through the existing Apple Metal stack.

The system should make hierarchy visible through generated scenes, not through a long explanatory taxonomy in the interface.

## Scope

### Included

- A deterministic closed-contour genome implemented for Metal rendering.
- Twelve curated shape presets divided across four morphological groups.
- Ten approved Metal material treatments.
- Per-shape material compatibility and role metadata.
- A small scene laboratory using compatible primary, supporting, and accent objects.
- A new Metal-only comparison table above the existing matrix.
- Exported Metal renders used by the website.
- Build, automated validation, and browser visual QA for the new section.
- Publication as a new version of the existing Sites project.

### Excluded

- Removing, hiding, rewriting, or reordering the current matrix.
- Replacing existing site assets.
- Enabling the new shapes in the production daily-canvas generator.
- User-facing settings for editing raw mathematical parameters.
- A general-purpose vector editor.
- Real-time differential-growth simulation in the first version.

## Alternatives Considered

### 1. Unified contour genome — selected

A superformula-derived polar contour is combined with bounded harmonic deformation, anisotropy, and off-center bias. This creates a broad but coherent family, maps well to deterministic seeds, and can be evaluated efficiently in Metal.

### 2. Several unrelated generators

Superformula, differential growth, metaballs, and particle hulls would produce greater immediate variety, but make visual coherence, compatibility, and performance harder to control. Differential growth remains a possible later accent family after the first grammar is curated.

### 3. Extend the current polygon/star parameter sweep

This would reuse more existing code but preserve the current false-diversity problem. It is not sufficient for the requested direction.

## Shape Genome

### Model

Each `MetalShapeGenome` contains stable, bounded parameters:

- symmetry order;
- radial exponent and roundness;
- lobe depth;
- valley sharpness;
- anisotropy;
- rotation;
- center offset;
- two low-frequency harmonic amplitudes and phases;
- edge softness budget;
- deterministic seed.

The radial contour is sampled from the superformula-derived base and perturbed by low-frequency harmonics. Parameters are constrained so the contour remains closed, non-self-intersecting, and thick enough to survive small rendering sizes.

### Curated groups

The public table shows named groups, not raw equations:

1. **Soft radial** — near-round bodies with controlled asymmetry and gentle local tension.
2. **Lobed** — three-, four-, and five-part forms whose lobes feel grown rather than cut from polygons.
3. **Folded rosettes** — closed forms with deeper valleys and alternating tension, without self-intersection.
4. **Crystalline** — irregular snowflake relatives with sharper peaks and restrained symmetry-breaking.

Each group contributes three curated presets, for twelve rows total. Presets must be separated by silhouette metrics and human visual review; a parameter change alone does not earn a row.

### Rejection rules

A generated genome is rejected or repaired when it has:

- a self-intersection;
- a minimum local thickness below the small-preview threshold;
- a silhouette distance too close to an already selected preset;
- extreme concavity that creates unstable blur or glow footprints;
- an optical center too far from its layout center;
- more fine-scale detail than the selected render tier supports.

## Metal Rendering Architecture

### Shared geometry representation

The CPU creates a deterministic contour sample buffer for each selected genome. Metal consumes the normalized contour and derives an object-local signed-distance-like field for masking, boundary distance, normals, and material coordinates.

Geometry and material remain separate:

`seed → genome → contour samples → local field → compatible material → composited actor`

The shared field allows every material to use the same authoritative silhouette. Material changes must not subtly alter the object boundary except for explicitly external effects such as directional blur and eclipse glow.

### Render tiers

- **Preview:** reduced samples and effect taps for the table and small scene actors.
- **Hero:** full contour and effect budgets for enlarged assets and the central laboratory object.
- **Export:** deterministic fixed-resolution render used for site assets and regression references.

## Approved Materials

The new study keeps these as distinct authored treatments:

1. **Solid color** — dense, simple mass.
2. **Side light** — directional transition across the interior.
3. **Contour** — thin, non-emissive boundary with an empty center.
4. **Directional blur** — a sharp source edge with a continuous code-art wake.
5. **Radial, two colors** — restrained volumetric light and shadow.
6. **Radial, three colors** — richer volumetric transition with a third chromatic region.
7. **Procedural light** — one or more seed-driven light lobes inside the silhouette.
8. **Procedural flow** — curved color bands following a local vector field.
9. **Procedural contour** — a continuous, generatively modulated line treatment used only where the silhouette stays legible.
10. **Eclipse glow** — a dark or restrained core with a strong external halo appearing to originate behind the figure.

### Thin-material construction

Procedural fills should avoid turning every object into a fully painted gradient mass. The first implementation supports:

- nested distance bands;
- warped contour strips;
- several broad flow ribbons with negative space between them;
- translucent overlapping shells;
- continuous lines with seed-driven width and displacement.

Fine repeated stripes are bounded by preview resolution and accessibility contrast. The result should read as deliberate bands, not moiré or texture noise.

### Directional-blur variants

Directional blur remains a signature material. The new study includes one primary implementation plus controlled modes within the lab:

- smooth luminous wake;
- separated ribbed wake;
- subtle chromatic split;
- curved wake following the local flow field.

Only the primary smooth wake appears as a main table column. The other modes appear in an expandable focused study so the table does not multiply near-duplicate columns.

## Compatibility and Composition Roles

Each curated preset has a compact internal manifest:

- allowed materials;
- preferred materials and weights;
- prohibited materials;
- allowed roles: primary, supporting, accent;
- supported size range;
- maximum recommended instances per scene;
- complexity score;
- visual-mass score;
- halo/blur footprint multiplier.

### Roles

- **Primary:** one dominant object. May use directional blur, eclipse glow, procedural light, or richer radial volume.
- **Supporting:** two to four calmer objects. Prefer side light, radial treatments, restrained solid, or broad flow.
- **Accent:** small, visually light objects. Prefer contour or procedural contour; complex interiors are normally prohibited.

### Scene constraints

A generated lab scene must satisfy:

- exactly one primary object;
- no more than two actors from the same morphological group;
- no more than one directional-blur actor;
- no more than one eclipse-glow actor;
- no more than two high-complexity interiors;
- at least one contour-based or otherwise hollow actor when the scene has four or more objects;
- footprint-aware spacing that includes external halo and blur extents;
- deterministic output for the same seed.

The compatibility system is expressed visually through successful generated compositions. The site exposes only concise role filters and a seed control; raw weights remain internal.

## Laboratory Experience

The new section appears immediately before the current `#matrix` section.

### Scene laboratory

The first block contains:

- one Metal-rendered composition;
- seed input and reroll action;
- object-count control using a small bounded set;
- optional role emphasis: balanced, central, or light;
- a short status line naming the selected genome/material combinations.

Rerolling changes the deterministic selection while preserving all compatibility constraints.

### New comparison table

The second block contains twelve shape rows. Columns are the ten approved materials, but only compatible cells render. An incompatible cell uses a quiet dash and does not create or request an asset.

Controls allow filtering by:

- morphological group;
- role;
- material;
- shared seed.

Every visible image is an exported Metal render. Browser-generated approximations are not used in this new table. Selecting an image opens its full-resolution Metal PNG, matching the current table’s established interaction.

### Preservation boundary

The current `#matrix` element and its contents remain byte-for-byte unchanged unless a build system requires a non-semantic anchor insertion before it. The new section receives its own IDs, styles, data, assets, and scripts. Existing navigation anchors continue to target the current matrix; a new navigation link targets the new study.

## Data and Asset Flow

1. Curated genome presets and compatibility metadata live in the iOS experiment code.
2. A deterministic export harness renders every allowed genome/material combination at fixed preview and full sizes.
3. Export filenames include genome ID, material ID, and render seed.
4. A generated manifest records rows, allowed cells, roles, visual-mass metadata, and asset paths.
5. The website reads the manifest and constructs the new lab and table without changing the legacy matrix data.
6. Site build copies only referenced assets into the static output.

The generated manifest is the boundary between the Metal implementation and the website. The site must not duplicate compatibility rules by hand.

## Failure and Fallback Behavior

- Invalid genomes fail export with a concrete validation reason; they do not produce placeholder art.
- A missing table asset renders a labeled unavailable cell and produces a build-time validation failure.
- If WebGL or browser canvas features are unavailable, the new section still works because its comparison images are static Metal exports.
- The scene laboratory may use pre-exported deterministic scene frames on the public site if live Metal execution is unavailable in the browser.
- Reduced Motion freezes scene animation while preserving composition and material readability.
- Eclipse glow and directional blur are bounded so they cannot overlap controls or be clipped without a deliberate preview frame.

## Accessibility

- Every render has an alt label containing genome, material, role, and seed.
- Role and compatibility are never communicated by color alone.
- Controls use native labels and keyboard-accessible elements.
- Table scrolling retains a named region and visible focus.
- Empty/incompatible cells are identified textually for assistive technology.
- Thin contour materials maintain a minimum luminance and apparent width at preview size.

## Validation

### Unit and structural tests

- Determinism for identical genome and render seeds.
- Closed-contour and self-intersection checks.
- Parameter-bound and finite-value checks.
- Minimum-thickness and optical-center checks.
- Compatibility-manifest validation.
- Scene-role and complexity-budget invariants.
- Stable export filenames and complete asset-manifest coverage.
- Assertion that the legacy matrix markup and referenced legacy assets are unchanged.

### Metal render tests

- Snapshot representative presets from all four morphological groups.
- Snapshot every material at least once.
- Explicit regression images for smooth directional blur and eclipse glow.
- Verify preview, hero, and export tiers.
- Check that contour, fill, blur, and glow share the same source silhouette.

### Visual QA

Perform one bounded visual pass over:

- the scene laboratory at representative seeds;
- all twelve rows with their compatible materials;
- the focused directional-blur variants;
- desktop and narrow layouts;
- reduced-motion and keyboard navigation behavior;
- the untouched current matrix immediately below the new section.

Fix observed defects in one batch, then perform one confirmation pass.

## Publication

The existing Sites project ID and URL are reused. A new site version is built and deployed only after Metal exports, manifest validation, the site build, and requested browser QA pass. The public URL remains:

`https://nowhere-composition-atlas.kostill.chatgpt.site/`

## References

- Johan Gielis’ superformula / supershape family: https://www.paulbourke.net/geometry/supershape/
- Apple Metal resources and Metal Shading Language specification: https://developer.apple.com/metal/resources/
- Casey Reas, *Process*: https://reas.com/process
- Tyler Hobbs, *Flow Fields*: https://www.tylerxhobbs.com/words/flow-fields
- Cabral and Leedom, *Imaging Vector Fields Using Line Integral Convolution*: https://digital.library.unt.edu/ark:/67531/metadc1399414/
