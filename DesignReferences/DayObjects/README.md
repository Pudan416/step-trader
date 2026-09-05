# Day Objects reference board

This directory is the persistent visual reference board for the experimental
Day Objects generator. References describe behaviors to preserve; they are not
pixel-perfect targets.

## System contract

### 01 — Generative DNA

- File: `system/01-generative-dna.md`
- Role: the shared procedural contract that converts visual references into
  deterministic scene and actor genomes, compatible mutations, and frozen
  `SceneRecipe` phenotypes.
- Core rules:
  - one generated day selects one primary visual family;
  - that family resolves into one daily art direction with a primary geometry
    region, a primary material, and at most one compatible supporting geometry
    and accent material;
  - geometry, material, edge, interaction, palette, depth, composition, and
    motion are separate DNA layers with explicit compatibility;
  - variation comes from correlated parameters rather than finished shape
    presets or unrestricted effect mixing;
  - happening identities remain stable when other happenings are added or
    removed;
  - a deterministic fourteen-day novelty schedule prevents adjacent days from
    repeating the same high-level visual fingerprint;
  - visible point clouds are excluded, while invisible control samples remain
    valid implementation details.
- Detailed reference files define family-specific ranges and negative
  signatures. The system contract defines the shared generation architecture.

### 02 — Shape and Material Capability Specimen V1

- Files:
  - `system/02-shape-material-specimen-v1.png`
  - `system/02-shape-material-specimen-v1.md`
- Status: approved in conversation on 2026-09-05 as a visual direction.
- Role: demonstrates that circle-derived carriers and material mechanisms are
  independent procedural axes.
- Important: this is a comparison atlas, not a valid single-day composition.
  Generated days still use one primary art direction with tightly bounded
  related mutations.

## Composition

### 01 — Asymmetric soft depth field

- File: `composition/01-asymmetric-overlap-reference.jpg`
- Source: https://pin.it/5SSddFwB6
- Pinterest pin: https://ru.pinterest.com/pin/1068127236602386787/
- User note: composition is the important reference behavior.
- Preserve:
  - extreme scale contrast between very large fields and small accents;
  - large circles cropped by several different canvas edges;
  - asymmetric distribution without a common ring, row, grid, or center;
  - overlapping objects at visibly different depth and focus;
  - soft transitions that let objects merge into one atmospheric scene;
  - a few small high-contrast details that prevent the large masses from
    feeling empty.
- Do not copy literally:
  - the exact palette;
  - the central sparkle symbol;
  - the exact positions of the circles.

### 02 — Related shape variety and dense overlap

- File: `composition/02-related-shape-variety-dense-overlap.jpg`
- Source: user-provided Pinterest collage.
- User note: the important qualities are the variety of forms, their
  relationships, and the composition.
- Preserve:
  - a dense full-canvas composition with large and small actors interlocking
    rather than sitting in isolated clusters;
  - substantial overlap and edge cropping, with no single common center;
  - one shared circular visual universe with clearly different members;
  - variation through shifted radial centers, rings, soft organic deformation,
    contour treatment, internal flow, and different color counts;
  - actors that visually react to their neighbors through overlap, scale
    contrast, and foreground/background order;
  - saturated color and readable individual silhouettes even in a busy scene.
- Do not copy literally:
  - the flower symbol as a mandatory shape;
  - the Pinterest overlay and text;
  - the exact palette, positions, or number of objects;
  - every material family appearing in one production day. A generated day
    should retain one primary material DNA with related mutations.

### 03 — Small objects distributed across the full canvas

- File: `composition/03-small-objects-full-canvas-scatter.jpg`
- Source: user-provided image.
- User note: the important quality is how the small figures are scattered
  throughout the canvas.
- Preserve:
  - occupation of the complete portrait canvas, including every vertical and
    horizontal region;
  - irregular but visually balanced spacing without a central cluster;
  - several objects touching or crossing canvas edges;
  - generous breathing room between most neighbors;
  - a related small-to-medium scale family with restrained size variation;
  - color rhythm distributed across the scene rather than grouped by hue;
  - soft focus that makes the actors atmospheric while keeping them visible.
- Do not copy literally:
  - a regular grid or fixed row/column spacing;
  - identical object size, focus, or internal center;
  - the exact palette or number of objects.

### 04 — Orbital linework constellation

- Files:
  - `composition/04-orbital-linework-constellation-reference.jpg`
  - `composition/04-orbital-linework-constellation-reference.md`
- Source: user-provided image.
- User note: the important qualities are the variety of circle-derived forms
  and the way they interact as one directional composition.
- Preserve:
  - one strong anchor feeding a curved, tapering chain of related actors;
  - filled discs, heavy and hairline rings, nested contours, incomplete arcs,
    radial thread bodies, woven annuli, nodes, and ghost circles remaining in
    one circular visual universe;
  - interaction through overlap, nesting, threading, tangency, echo, bridging,
    and line-density accumulation;
  - depth expressed primarily through scale, contour weight, density, opacity,
    and occlusion rather than global blur;
  - large intentional negative space around alternating clusters and bridges;
  - restrained color roles and stable fine-line texture.
- Do not copy literally:
  - the exact palette, orientation, coordinates, ring count, or spirograph
    formula;
  - every visible sub-circle as an independent happening;
  - a mechanical diagram, gear system, flower, or regular chain of rings;
  - the complete Linework Constellation and gradient-field catalogs mixed into
    one production day.
- Use the companion Markdown file as the detailed behavioral contract and
  acceptance checklist for this separate Day Objects family.
- Apply the shared generation architecture from
  `system/01-generative-dna.md`.

### 05 — Radial Fiber Fields

- Files:
  - `composition/05-radial-fiber-fields-reference.jpg`
  - `composition/05-radial-fiber-fields-reference.md`
- Source: user-provided image.
- User note: preserve the construction of circles from radial marks and use it
  as a procedural grammar rather than a catalog of finished shapes.
- Preserve:
  - a clear but asymmetric hierarchy of anchor, partners, counterweight, and
    terminal accent;
  - soft cores dissolving into dense radial fibers and porous perimeters;
  - optical gradients produced by line density, opacity, and overlap;
  - circle-derived variation through envelope complexity, inner and outer
    radius, contour completeness, low-frequency lobes, and restrained
    star-like fields;
  - woven intersections, a limited connective arc, stable fine-line texture,
    and generous negative space;
  - deterministic actor identities generated from correlated parameters.
- Do not copy literally:
  - the exact palette, coordinates, count, vertical orientation, or ray count;
  - the five visible actors as fixed reusable presets;
  - literal flowers, sunbursts, gears, sharp stars, pupils, or orbital diagrams;
  - unstable high-frequency lines that create aliasing, moire, or flicker;
  - every possible radial mutation in one generated day.
- Use the companion Markdown file as the detailed behavioral contract,
  procedural shape-space proposal, and acceptance checklist for this separate
  Day Objects family.
- Apply all seed, identity, compatibility, and mutation-budget rules from
  `system/01-generative-dna.md`; visible point clouds are not part of this
  family.

### 06 — Tensioned Loop Network

- Files:
  - `composition/06-tensioned-loop-network-reference.jpg`
  - `composition/06-tensioned-loop-network-reference.md`
- Source: user-provided image.
- User note: preserve the circle-derived forms and especially their interaction
  as a connected procedural system rather than reusable finished rings.
- Preserve:
  - loops deforming toward selected neighbors and merging through narrow,
    smoothly widening tension bridges;
  - shared saddle-like junctions emerging from contour curvature rather than
    repeated decorative symbols;
  - strong scale hierarchy, a dense connective middle, large openings, sparse
    terminal arcs, and broad surrounding negative space;
  - variable contour width from elegant hairline to broader structural node;
  - one bright foreground network with an optional derived low-contrast depth
    echo;
  - stable local topology whose unrelated branches survive happening insertion
    and removal unchanged.
- Do not copy literally:
  - the black-and-white palette, coordinates, orientation, exact loop count, or
    literal bright four-point junction shapes;
  - regular foam, chainmail, molecular diagrams, ring lattices, or straight
    node-link connectors;
  - filled metaballs, disconnected particles, rapid topology changes, or
    repeated star icons;
  - the full Linework Constellation catalog inside the same generated day.
- Use the companion Markdown file as the detailed family profile and apply the
  shared architecture from `system/01-generative-dna.md`.

### 07 — Harmonic Loop Fields

- Files:
  - `composition/07-harmonic-loop-fields-reference.jpg`
  - `composition/07-harmonic-loop-fields-reference.md`
- Source: user-provided image.
- User note: preserve the greater variety of forms as procedural outcomes, not
  a collection of finished spirograph assets.
- Preserve:
  - one continuous harmonic-path grammar producing annuli, dense optical
    fields, broad rosettes, elongated loops, partial gestures, and restrained
    low-lobe bouquets;
  - visible variation through frequency ratio, phase, amplitude, opening ratio,
    eccentricity, traversal completeness, and path density;
  - strong independent variation of actor scale and internal lobe scale;
  - transparent superposition, density weaving, aperture framing, and coherent
    single-color identity for each complete path actor;
  - a dense overlap region balanced by an isolated readable counterweight,
    internal openings, edge crops, and external negative space;
  - deterministic continuous paths with scale-aware full-screen and tile
    rendering.
- Do not copy literally:
  - the exact palette, paper texture, coordinates, equations, actor count, or
    visible source rosettes;
  - literal flowers, atoms, toy spirographs, or security-pattern wallpaper;
  - identical symmetry, lobe count, opening, orientation, or color allocation
    across actors;
  - visible sampling points, disconnected paths, moire, shimmer, or rapid
    rotation;
  - every harmonic outcome or every linework family in one generated day.
- Use the companion Markdown file as the detailed family profile and apply the
  shared architecture from `system/01-generative-dna.md`.

## Materials

- Reference 02 also defines useful related material mutations: smooth radial
  fill, offset core, concentric contour, soft organic body, and internal flow.
  These are a catalog across different days, not permission to mix unrelated
  materials arbitrarily inside one day.

### 01 — Mist, depth, and fine texture

- File: `materials/01-mist-depth-and-grain-texture.jpg`
- Source: user-provided image.
- User note: the important qualities are mistiness and texture.
- Preserve:
  - atmospheric softness that feels volumetric rather than like a uniform
    Gaussian blur over the complete frame;
  - several focus depths, from a nearly dissolved foreground or background
    mass to a more readable middle object;
  - silhouettes that merge softly while retaining their approximate volume;
  - fine, stable, tactile grain visible inside broad color fields;
  - restrained low-contrast color transitions with occasional warmer or
    darker cores;
  - partially cropped forms that continue beyond the canvas.
- Do not copy literally:
  - making every day desaturated or green;
  - using heavy noise to hide gradient seams;
  - applying identical blur to every actor and to the background;
  - reducing visibility until the scene appears empty.

### 02 — Editorial gradient overlap and print grain

- Files:
  - `materials/02-editorial-gradient-overlap-reference.jpg`
  - `materials/02-editorial-gradient-overlap-reference.md`
- Source: user-provided image.
- User note: this is a primary reference for gradient behavior, transparency,
  color variety, grain, and composition.
- Preserve:
  - broad two- and three-color fields spanning complete objects;
  - shifted radial centers, including centers near or outside object edges;
  - transparency that creates clean new colors and lens shapes at overlaps;
  - an asymmetric scale hierarchy with cropped giants, anchors, connectors,
    small satellites, and meaningful negative space;
  - dense stable print-like grain shared by background and objects;
  - materially different actors whose dominant colors and gradient directions
    remain visibly distinct.
- Do not copy literally:
  - the exact palette, coordinates, object count, or overlap silhouettes;
  - directional gradients implemented with forbidden linear or angular fields;
  - the same dense lower-heavy composition for every generated day.
- Use the companion Markdown file as the detailed behavioral contract and
  acceptance checklist for future Lab renders.
- Apply the shared generation architecture from
  `system/01-generative-dna.md`.

### 03 — Soft Constructed Body Atlas

- Files:
  - `materials/03-soft-constructed-body-atlas-reference.jpg`
  - `materials/03-soft-constructed-body-atlas-reference.md`
- Source: user-provided image.
- Role: a cross-family geometry/material compatibility atlas, not one visual
  family and not a composition target.
- User note: preserve the variety of materials, forms, textures, and colors as
  procedural possibilities.
- Preserve:
  - circle-derived soft compound carriers including four-lobe, paired-lobe,
    rounded rectangular, cleft, circular-inset, and soft angular bodies;
  - independent but compatible Geometry DNA and Material DNA;
  - broad geometry-aware radial fields anchored near lobes, clefts, rounded
    corners, sides, insets, or significant neighbors;
  - dark-core chromatic fields, luminous boundaries, layered membranes,
    integrated insets, and stable tactile modifiers as separate controlled
    constructions or parameters;
  - coordinated outline, interior, and field palette roles;
  - one primary material mechanism transferred across a related carrier region
    within one generated day.
- Do not copy literally:
  - the poster grid, typography, labels, date, equal scale, or centered specimen
    presentation;
  - all visible materials and carriers in one scene;
  - literal clovers, repeated app icons, face-like insets, pupils, decals, or
    dirty corner stains;
  - sharp angular or linear gradients, hard masks, visible particles, or fast
    carrier-category morphing.
- Use the companion Markdown file as the compatibility contract and apply the
  shared generation architecture from `system/01-generative-dna.md`.

## Depth and scale

### 01 — Extreme continuous size hierarchy

- File: `depth-and-scale/01-extreme-size-hierarchy-bubbles.jpg`
- Source: user-provided image.
- User note: the important quality is the variability of sizes.
- Preserve:
  - several clearly distinct scales visible in the same frame: cropped giant,
    large anchor, medium support, small satellite, and tiny distant accents;
  - a continuous diameter spectrum rather than two or three repeated presets;
  - scale contributing to depth, with tiny actors reading as distant and large
    cropped actors reading as near;
  - irregular relationships between size and position;
  - small actors remaining visible and useful instead of becoming noise;
  - overlaps and edge cropping that reinforce the depth hierarchy.
- Do not copy literally:
  - the photorealistic bubble highlights;
  - the exact blue and pink palette;
  - a fixed rule requiring one dominant giant in every scene;
  - identical circular geometry for every material family.

## Sources

- `source/random-gradient-circle.html` — procedural material reference for
  shifted radial centers, layered color fields, softness, transparency,
  outlines, counterforms, and deterministic shape/color seeds.

## Local-use note

The downloaded image is retained as an internal design reference with its
source URL. Confirm reuse rights before publishing or redistributing the image
itself.
