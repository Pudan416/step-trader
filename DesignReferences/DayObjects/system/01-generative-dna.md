# Day Objects Generative DNA

## Status and role

This document is the system-level generative contract for Day Objects.

Individual reference documents describe what a particular visual family should
feel like. This document describes how all such families become deterministic,
varied, and coherent generated scenes rather than catalogs of finished shapes.

The central rule is:

> Generate related visual behavior from stable DNA. Do not select finished
> pictures or freely mix unrelated effects.

This contract is independent of the final rendering backend. A sandbox, Metal
renderer, still-image exporter, and calendar-tile renderer should all be able to
consume the same frozen scene phenotype.

## Decision summary

- One generated day selects one primary visual family.
- The family is resolved into one scene-level art direction before any actor is
  generated. Actors never choose unrelated styles independently.
- Variety comes from mutations inside that family.
- One day uses one primary geometry region and one primary material mechanism,
  with at most one compatible supporting geometry region and one compatible
  accent material.
- Geometry and material are separate DNA layers with explicit compatibility.
- Composition is generated from roles and relationships before coordinates.
- A happening owns one stable actor identity.
- Actor identity survives insertion and deletion of other happenings.
- Randomness is deterministic, hierarchical, correlated, and bounded.
- A generated phenotype is frozen into a `SceneRecipe` before rendering.
- Fine visual modifiers such as opacity, softness, and grain are parameters,
  not separate material families.
- Visible point clouds are outside the approved shape vocabulary.
- Invisible mathematical control samples may be used to construct smooth
  contours, fibers, or fields, but they must not appear as standalone dots.
- A deterministic novelty schedule prevents neighboring days from repeatedly
  selecting the same high-level art direction while preserving reproducibility.

## Why a shared DNA system is necessary

A list of manually designed circles can produce attractive screenshots but not
a durable generative product. It eventually repeats recognizable assets, makes
new references expensive to integrate, and confuses object identity with a
bitmap or shader preset.

Pure unrestricted randomness fails in the opposite direction. If geometry,
color, texture, position, blur, and movement are sampled independently, most
results are visually incoherent. Increasing the number of available options
then increases noise rather than meaningful variety.

Generative DNA is the middle layer between those extremes:

- references define authored visual principles;
- family profiles turn principles into allowed parameter ranges;
- stable seeds select related values inside those ranges;
- compatibility and composition constraints reject incoherent combinations;
- a frozen recipe records the resulting artwork for all renderers.

## Genotype and phenotype

### Genotype

The genotype is the compact deterministic description from which a scene can be
generated. It contains seeds, selected family, role assignments, parameter
ranges, and compatibility decisions.

The genotype should express causes, not final pixels. Examples include:

- this actor is an anchor at near depth;
- its geometry is a softly lobed closed radial body;
- its material is a broad radial color field;
- its boundary is feathered;
- it should overlap one partner and remain separated from a satellite;
- its motion is slow and phase-shifted from its neighbors.

### Phenotype

The phenotype is the concrete scene produced from the genotype:

- exact actor positions and radii;
- exact closed contours;
- exact material centers and color roles;
- exact blur, opacity, grain, and draw order;
- exact motion parameters;
- exact interaction relationships.

The phenotype is what should be frozen into `SceneRecipe`. Rendering the same
phenotype must produce the same visual identity across time, resolution, and
backend, allowing only documented scale-aware sampling differences.

### Why both are needed

The genotype makes the system generative and extensible. The phenotype makes it
reproducible, debuggable, and portable.

Do not ask a renderer to rediscover aesthetic decisions every frame. The
generator makes those decisions once; the renderer faithfully expresses them.

## Four-level architecture

### Level 1 — Universal laws

Universal laws apply to every Day Objects family:

- stable happening identity;
- deterministic seeds;
- slow continuous motion;
- Reduce Motion preserving the same artwork;
- approved palette authority;
- no abrupt angular or linear color fields;
- no accidental eyes, flowers, grids, or identical clusters;
- composition organized by hierarchy and relationships;
- actual visibility at both full-screen and calendar-tile size;
- no visible point-cloud phenotype.

Universal laws belong only in this system contract or in the approved product
specification. Family documents should link to them rather than redefine them.

### Level 2 — Family profile

A family profile defines one coherent physical or graphic process. Examples:

- Editorial Gradient Overlap;
- Linework Constellation;
- Radial Fiber Fields;
- future circle-derived or non-circular families approved from references.

A family profile declares:

- allowed geometry regions;
- primary material construction;
- permitted edge treatments;
- typical interaction types;
- composition tendencies;
- correlated parameter rules;
- rare mutation budget;
- family-specific negative signatures;
- scale-aware rendering requirements.

It does not contain fixed final actors.

### Level 3 — Scene genome

The scene genome selects one family profile and establishes shared behavior for
one generated day:

- compositional gesture;
- anchor count;
- density and negative-space pattern;
- scale spectrum;
- depth direction;
- palette roles;
- dominant material regime;
- interaction graph;
- motion character;
- optional compatible accent mutation.

The scene genome is the main source of family resemblance. Actors in one scene
should appear to belong to the same artwork even when their individual forms
differ strongly.

### Daily art direction

Before actor generation, the scene genome is frozen into a single daily art
direction. This is the coherence envelope for the complete picture, not a
finished preset and not a list of independent effects.

The art direction records:

- one primary family profile;
- one composition behavior;
- one primary geometry region;
- zero or one closely related supporting geometry region;
- one primary material mechanism;
- zero or one family-approved accent material;
- palette roles and palette temperature;
- one edge character;
- one depth and focus policy;
- one motion character;
- one scene-wide grain character.

These choices are correlated. A complex geometry region receives a simpler
material and quieter motion. Fine linework receives enough contrast and focus
to survive at target size. Highly transparent materials receive palette roles
that remain visible on the selected background.

The generator must never sample the complete catalog once per actor. A scene of
ten happenings is one artwork containing ten relatives, not a specimen sheet
containing ten unrelated techniques.

### Within-day coherence proportions

The initial policy for scenes with enough actors is:

- roughly `70...90%` of actors use the primary geometry region;
- roughly `10...30%` may use the supporting geometry region;
- roughly `75...100%` use the primary material mechanism;
- no more than `25%` may use the compatible accent material;
- zero, one, or two actors may consume the rare-mutation budget;
- all actors share palette, grain, edge, depth, and motion logic from the same
  scene genome.

These are deterministic weighted ranges rather than quotas. Sparse scenes still
follow the same priority: at one happening the actor expresses the primary art
direction; at two or three happenings, an accent appears only when it improves
the relationship and remains clearly related.

### Art-direction fingerprint

Every generated day exposes a compact fingerprint for scheduling, debugging,
and diversity checks:

```text
family
composition behavior
primary geometry region
supporting geometry region, if any
primary material
accent material, if any
palette mood
depth policy
edge character
motion character
```

The fingerprint describes high-level decisions only. Two days may share a
family while producing different contours, positions, colors, and actors, but a
repeated fingerprint indicates that the generator is relying on small parameter
noise rather than meaningful daily variation.

### Deterministic novelty schedule

Daily variety is scheduled above actor-level randomness. The initial scheduler
uses deterministic fourteen-day epochs:

1. Derive an epoch seed from the stable Day Objects root seed and the calendar
   epoch identifier.
2. Build a weighted shuffle bag of eligible family and composition pairings.
3. Expand each pairing into compatible geometry, material, palette, depth,
   edge, and motion candidates.
4. Resolve the epoch sequentially from its first day, rejecting candidates that
   are too similar to the already resolved recent fingerprints.
5. Include the final fingerprints of the preceding epoch when resolving the
   boundary, so a new epoch does not visibly restart the sequence.
6. Select the entry for the requested date. No mutable viewing history is
   required, and direct generation of an old date remains reproducible.

The initial novelty constraints are:

- the same primary family does not appear on adjacent days when another
  compatible family is available;
- the same combination of composition behavior, primary geometry, and primary
  material does not repeat inside a rolling seven-day window;
- at least two major fingerprint axes change from the previous day;
- palette changes alone do not count as sufficient novelty;
- a rare family may not be promoted merely to satisfy the schedule if its
  target-size or compatibility requirements cannot be met.

The schedule controls visual recurrence, not health semantics. Steps, sleep,
happenings, and other daily inputs modulate the selected scene's density,
clarity, tempo, and actor count without silently changing its primary visual
family during the day.

### Level 4 — Actor genome

Each happening receives an actor genome. It specializes the scene genome:

- compositional role;
- position tendency;
- size and depth;
- geometry mutation;
- material parameters;
- boundary treatment;
- color role;
- opacity and focus;
- interaction participation;
- motion phase and amplitude.

Actor genomes are stable and addressable by happening identity. They must not
depend on iteration order or total happening count.

## DNA layers

The following layers are conceptually independent. A family profile controls
which combinations are valid.

## 1. Composition DNA

Composition DNA answers where actors live and why.

It contains:

- global gesture or flow spine;
- occupied regions;
- protected negative-space regions;
- visual center of mass;
- anchor, partner, bridge, counterweight, satellite, and accent roles;
- intended overlap and separation relationships;
- edge-contact policy;
- scale distribution;
- local cluster and interval rhythm.

Composition is not generated by sampling independent `x` and `y` values for
each actor. Roles and relationships are selected first, then coordinates are
solved within those constraints.

### Approved composition behaviors

The current board supports several broad behaviors:

- asymmetric depth field with cropped giants;
- dense related overlap across much of the canvas;
- irregular full-canvas distribution of small actors;
- directional constellation with clusters and bridges;
- loose vertical or curved stack with unequal weight;
- continuous extreme size hierarchy.

A family may support one or several behaviors. A single scene chooses one
primary behavior rather than averaging all of them.

### Composition mutation

Composition may vary through:

- gesture orientation and curvature;
- role count within family bounds;
- location and size of protected voids;
- anchor placement;
- degree of overlap;
- crop frequency;
- scale-spectrum skew;
- cluster density and separation.

Variation must preserve the selected behavior's recognizable logic.

## 2. Geometry DNA

Geometry DNA defines the actor's carrier shape independently of how it is
filled or drawn.

The current preferred universe is circle-derived. The architecture should not
hardcode a perfect circle, because the same system may later support additional
approved forms. The initial geometry vocabulary is deliberately bounded.

### Approved initial geometry regions

#### Closed radial body

A continuous closed contour expressed relative to a center. It can range from:

- circle;
- ellipse;
- gently asymmetric organic circle;
- softly lobed body;
- restrained soft star.

The transition between these results is continuous. A star-like result remains
rounded and radial rather than becoming a literal icon.

#### Annular body

A closed radial body with a broad internal void. The void may be centered or
offset and can vary smoothly in size.

Avoid small centered holes that read as pupils, buttons, or accidental errors.

#### Complete contour

A circle-derived perimeter without a dominant filled interior. It may be thin,
heavy, soft, or fiber-built according to the selected material and edge DNA.

#### Incomplete contour

One or more arcs imply a larger closed body. Arc endpoints and gaps are stable
and intentional.

#### Radial fiber body

A closed radial envelope whose visible body is constructed from fibers between
inner and outer radius profiles.

This is geometry plus a required compatible fiber material. It must not be
represented as isolated visible dots.

#### Connected loop network

Two or more circle-derived loops may deform locally toward selected neighbors
and share tension bridges, saddle-like junctions, or short common boundaries.

The interaction graph is generated before the relational geometry. Base loop
identity remains recoverable, and unrelated branches remain stable when a
happening is added or removed.

This geometry is mostly hollow. It must not collapse into filled metaballs,
regular foam, straight node-link diagrams, or repeated stamped junction symbols.

#### Harmonic path body

One continuous periodic path or a few tightly phase-related passes create a
circle-derived actor. Frequency ratio, amplitude, phase, opening ratio, envelope,
and traversal completeness produce annular, radial, elongated, softly lobed,
and partial outcomes.

The path remains continuous. Renderer samples are invisible construction data,
and the phenotype must not expose disconnected dots. Low-lobe outcomes remain
abstract rather than becoming literal flowers or atom symbols.

#### Soft compound body

A continuous carrier is assembled from circles, ellipses, rounded bodies, soft
arcs, and broad smooth union or subtraction. Stable parameters control lobes,
clefts, aspect, roundness, symmetry deviation, and occasional soft directional
features.

The circle remains the preferred common region. Compound outcomes are related
mutations, not fixed clover, app-icon, bow-tie, or polygon assets.

The geometry exposes stable semantic feature sites such as lobe centers, cleft
centers, rounded corners, long sides, insets, and neighbor-facing boundaries.
Compatible materials may anchor broad fields to those sites.

### Invisible control samples

An implementation may approximate any contour with control samples or vertices.
Their count may influence smoothness, lobing, and structural rhythm.

These samples are construction data only:

- they are interpolated into a continuous contour or connected structure;
- they are never rendered as a freestanding cloud;
- reducing their count must not expose a set of unrelated dots;
- temporal motion must not resample them frame by frame.

### Future geometry extensions

Future references may justify non-circular forms. To enter the system, a new
geometry region must define:

- a continuous parameterization;
- valid deformations;
- compatible materials and edges;
- interaction behavior;
- scale and motion behavior;
- negative signatures;
- a reason it still belongs to Day Objects.

Adding a geometry family is an explicit design decision, not a random chance to
emit arbitrary polygons or symbols.

## 3. Material DNA

Material DNA defines how the carrier geometry becomes visible.

Materials are classified by construction mechanism, not by vague appearance.
Words such as translucent, soft, misty, and colorful describe parameters or
outcomes; they do not automatically create separate families.

### Solid color field

One approved color covers the actor. Tonal change may arise from opacity,
lighting-like density, grain, or interaction with the background, but the actor
does not acquire a second hue.

Compatible variation:

- opacity;
- broad density falloff;
- edge softness;
- grain strength;
- contour presence;
- depth-dependent focus.

### Smooth radial color field

One to three broad overlapping radial fields color the actor. Centers may be
shifted near or beyond the geometry boundary.

Required behavior:

- transitions span meaningful portions of the complete actor;
- boundaries remain smooth;
- there are no angular wedges, linear bands, pyramids, or hard inner spots;
- colors come from one approved palette relationship;
- orientation and center arrangement vary by stable seed.

### Boundary field

The perimeter or annular region carries most of the visible material. It can
produce thin outlines, soft outlines, heavy contours, and incomplete arcs.

Line width, softness, completeness, and opacity vary continuously. Thin elegant
outlines and broad soft outlines are regions of one construction, not unrelated
presets.

### Fiber field

Many connected radial or curved marks create an optical body. Density, length,
opacity, and accumulation create softness and gradient-like volume.

Fibers remain connected to the actor's geometry. Their endpoints do not become
a separate point-cloud material.

### Linework structure

Nested contours, woven annuli, radial threads, arcs, and orbital relations form
a structured line-led actor or constellation.

This material is more topologically varied than a fiber field and belongs
primarily to the Linework Constellation profile.

### Tensioned contour network

Variable-width boundaries create one connected membrane-like structure. Thin
arcs widen gradually into relation-driven bridges and shared junctions, then
return to hairline.

The widening must emerge from geometry and curvature. It must not be implemented
as a repeated star or diamond placed at every connection.

### Repeated path field

One continuous harmonic path creates both silhouette and apparent interior
density by repeatedly crossing or approaching itself. Line opacity is coupled to
path density so sparse actors remain visible and dense actors do not collapse
into muddy solids.

This construction retains coherent color identity across the complete path and
requires scale-aware antialiasing to prevent moire and temporal crawling.

### Geometry-aware radial field

One or more broad smooth radial fields are anchored relative to stable geometry
features rather than arbitrary interior coordinates. Valid anchors include
lobes, clefts, rounded corners, sides, insets, and significant neighbor-facing
regions.

Fields remain broad, overlapping, and radial. Feature awareness does not permit
small edge spots, hard masks, angular wedges, linear bands, or eye-like cores.

### Layered membrane field

A pale or translucent base body owns a limited number of broad related material
layers. Layers may occupy the interior, cross the boundary, or form integrated
inset membranes while retaining one actor identity.

Translucency itself remains a modifier. The construction is distinct because it
uses owned overlapping membrane layers tied to stable geometry sites.

### Controlled hybrid

A family profile may combine two mechanisms when the reference demonstrates a
clear relationship, for example:

- radial color field plus thin contour;
- fiber field plus incomplete arc;
- solid field plus soft boundary;
- linework structure plus restrained filled node.

A hybrid is declared by the family profile. It is not created by independently
turning every available effect on.

## 4. Edge DNA

Edge DNA controls the transition between actor and environment.

Approved edge regions include:

- clean but antialiased boundary;
- broad soft boundary;
- feathered fiber boundary;
- thin elegant outline;
- soft outline;
- heavy structural contour;
- variable-width tension contour;
- continuous harmonic hairline;
- chromatic boundary;
- incomplete arc;
- gradual dissolution while retaining a recoverable silhouette.

Edge behavior must support the material. A crisp vector contour pasted over a
misty actor usually fails unless the family explicitly integrates that contrast.

The generator should couple:

- edge softness to actor depth;
- line width to target resolution;
- contour opacity to background contrast;
- feather length to fiber density;
- dissolution strength to silhouette readability.

## 5. Interaction DNA

Interaction DNA defines how actors influence one another visually.

Approved relationship types include:

- transparent overlap producing a lens color;
- opaque or semi-opaque occlusion;
- fiber-over-fiber weaving;
- contour threading in front of and behind a neighbor;
- containment or nesting;
- tangency and near-tangency;
- contour crossing;
- tension bridge;
- shared saddle junction;
- short shared boundary;
- transparent curve superposition;
- density weave;
- aperture framing;
- transparent body overlap;
- inset membrane overlap;
- geometry-aware material response;
- scale echo;
- deliberate separation across negative space.

The generator creates a sparse interaction graph before final placement. Each
edge in the graph describes an intended relationship, not merely a geometric
accident.

### Interaction constraints

- Not every pair should overlap.
- Not every overlap should use the same opacity.
- Repeated exact tangency creates bubble chains and is discouraged.
- Overlap colors must remain chromatic rather than muddy.
- Draw order is stable during motion.
- Dense interaction zones require quieter space elsewhere.

## 6. Palette DNA

Palette DNA selects relationships from the approved palette authority.

It separates:

- background palette;
- actor palette family;
- scene-level color roles;
- actor-specific deterministic selections;
- overlap compatibility;
- contrast constraints.

The goal is authored variety, not maximum hue distance.

### Scene color roles

A scene may assign:

- dominant anchor role;
- related support role;
- contrasting partner role;
- low-contrast atmospheric role;
- limited accent role.

Roles may repeat across spatially separated actors to connect the composition.

### Single-color integrity

When an actor selects one color, that color remains unified across its body and
stable over time. Opacity and density may alter perceived value, but the
generator must not inject an unrelated core color.

### Multicolor integrity

Multicolor actors use only family-approved smooth fields. Color count, centers,
field radius, and opacity are coupled so no field becomes a sharp eye-like spot.

### Background awareness

Color selection responds deterministically to background type and brightness.
This prevents disappearance, but it must not repeatedly collapse to the same
highest-contrast primaries.

## 7. Depth DNA

Depth DNA coordinates:

- scale;
- focus;
- opacity;
- occlusion order;
- edge softness;
- material resolution;
- parallax.

The default Editorial Field relationship is:

- large near actors are more defocused;
- medium actors occupy a readable middle plane;
- small distant actors are more focused;
- draw order and overlap reinforce these planes;
- no actor disappears merely because it is atmospheric.

A family may use a more graphic depth system, such as contour weight and line
density in Linework Constellation. Family profiles specify which cues dominate.

## 8. Motion DNA

Motion DNA animates a frozen phenotype without changing its identity.

It includes:

- base drift direction;
- amplitude;
- period;
- phase;
- depth-based parallax coefficient;
- optional family-approved internal breathing;
- appearance and removal transition behavior.

Motion is slow, continuous, and individually phased. It must not reroll shape,
material, palette, internal centers, or line construction.

### Appearance and removal

When happenings are added or removed:

- surviving actor genomes remain unchanged;
- surviving actors keep their colors and materials;
- composition adjustments, if required, are minimal and deterministic;
- appearing actors enter without forcing a scene-wide reshuffle;
- removed actors exit without changing the identity of neighbors.

### Reduce Motion

Reduce Motion presents the same phenotype at rest:

- parallax is removed or strongly reduced;
- internal phase movement is frozen;
- no simplified replacement shapes are generated;
- no material or color is rerolled;
- the static composition remains visually complete.

## Modifiers are not families

The following properties modify a construction but do not define an independent
material family:

- opacity;
- blur or focus;
- mistiness;
- softness;
- saturation;
- contrast;
- grain;
- translucency;
- scale;
- line density.

For example, “single-color translucent,” “single-color misty,” and
“single-color soft” are parameter regions of Solid Color Field unless another
construction mechanism is present.

Likewise, “transparent multicolor” is Smooth Radial Color Field with a lower
opacity and compatible compositing, not a separate material by itself.

This distinction prevents an inflated catalog in which visually identical
results are given different names.

## Seed hierarchy

Seeds are derived hierarchically so changes in one domain do not accidentally
reroll another.

### Day seed

The stable root for one day. It selects or schedules the primary family and
provides namespaces for the lower-level seeds.

### Scene seed

Controls composition behavior, shared palette roles, global depth direction,
and interaction graph.

### Actor identity seed

Derived from the stable happening identity rather than actor index. It controls
role-compatible geometry and persistent actor traits.

### Material seed

Controls material centers, contour details, fiber phase, density variation, and
grain phase without changing geometry.

### Motion seed

Controls phase, amplitude, period, drift direction, and parallax without
changing the static phenotype.

### Domain separation

Changing the palette seed should recolor a stable geometry when explicitly
requested. It should not move actors or alter contours.

Changing motion settings should not change static appearance.

Changing happening count should not regenerate surviving actor seeds.

## Randomness model

### Weighted regions, not uniform ranges

Uniform sampling over every numeric parameter gives too much probability to
uninteresting middle values and incoherent extremes.

Each family profile defines weighted regions such as:

- common;
- supporting;
- rare;
- forbidden.

Continuous variation still occurs inside each region.

### Correlated genes

Genes are conditionally related. Examples:

- large near actors are softer and use stronger parallax;
- thin contours receive enough contrast to survive calendar-tile rendering;
- highly transparent actors avoid weak low-contrast palette roles;
- dense fiber fields use lower per-fiber opacity;
- strongly lobed geometry uses simpler internal color structure;
- busy interactions reduce detail elsewhere in the scene.

Correlation is the main defense against random visual noise.

### Mutation budget

Every scene receives a bounded mutation budget. Most actors occupy the common
family region. A small number may explore rare extremes.

For a ten-happening scene, a useful initial policy is:

- six or seven common actors;
- two or three supporting mutations;
- zero to two rare actors;
- never ten rare actors.

These are design proportions, not mandatory fixed counts.

### Bounded surprise

A rare actor may use:

- unusually large or small scale;
- a broader void;
- a more incomplete contour;
- a more strongly lobed but still soft body;
- an exceptionally thin outline;
- unusually long fibers;
- a compatible accent palette role.

Rare does not mean unrelated. Every surprise must still pass the family profile.

## Compatibility system

Geometry, material, edge, and interaction genes cannot be combined freely.

Each family profile provides an allowlist and conditional rules.

### Example compatibility statements

- A soft radial star may use a solid field or broad radial color field.
- A strongly lobed actor should not also use a complex linework interior and
  three-color material.
- A radial fiber body requires a fiber field and may add one incomplete arc.
- A very thin contour cannot carry a complex interior gradient by itself.
- An annular body may use a boundary field or fiber field, but a tiny centered
  void is forbidden.
- Heavy global blur is incompatible with a family whose identity depends on
  fine linework.
- Soft compound bodies may use Solid Color Field, Smooth Radial Color Field,
  Geometry-Aware Radial Field, Boundary Field, or a family-approved Layered
  Membrane Field.
- A highly complex carrier uses simpler material, interaction, and motion
  channels unless a reference explicitly validates the combination.
- Harmonic Path and Connected Loop Network actors do not automatically receive
  filled membrane materials merely because those materials exist in the atlas.

### Complexity budget

Every actor and scene has a complexity budget across four channels:

- silhouette complexity;
- material complexity;
- interaction complexity;
- motion complexity.

If one channel is high, others should normally decrease. This preserves an
editorial focal hierarchy and keeps rare forms legible.

### Compatibility result

Invalid combinations are not repaired by adding effects. The generator should:

1. reject the conflicting sample;
2. resample only the incompatible gene within its deterministic stream;
3. retain all already valid stable decisions;
4. stop after a bounded number of attempts and choose a conservative valid
   fallback from the same family.

## Generation pipeline

### Step 1 — Schedule the daily art direction

Resolve the date's deterministic novelty epoch and select one primary family.
Freeze its composition, geometry, material, palette, edge, depth, grain, and
motion fingerprint. Do not independently select a family or full material
catalog entry for every actor.

### Step 2 — Build the scene genome

Choose exact composition gesture, palette roles, depth direction, interaction
budget, supporting geometry region, optional accent material, and mutation
budget inside the frozen art direction.

### Step 3 — Assign actor roles

Map stable happenings to anchor, partner, bridge, counterweight, satellite, or
accent roles. Roles are deterministic and not based solely on list index.

### Step 4 — Generate the interaction graph

Select intended overlap, containment, threading, tangency, echo, and separation
relationships.

### Step 5 — Solve composition

Find exact positions and scales that satisfy the role and interaction graph
while preserving protected negative space and canvas coverage.

### Step 6 — Generate actor geometry

Create each stable carrier shape inside the family-approved geometry region.

### Step 7 — Generate material and edge

Apply compatible construction mechanisms and modifiers. Resolve palette roles
with the actual background and compositing model.

### Step 8 — Validate the static phenotype

Check hierarchy, visibility, negative space, overlap color, forbidden patterns,
and target-size legibility before motion.

### Step 9 — Generate motion

Add slow, family-compatible, depth-dependent motion without changing identity.

### Step 10 — Freeze `SceneRecipe`

Persist the complete phenotype needed by all renderers. Do not make additional
aesthetic random choices inside the renderer.

## SceneRecipe boundary

The generator and renderer have different responsibilities.

### Generator owns

- family selection;
- seed derivation;
- composition roles and constraints;
- geometry mutation;
- material and palette decisions;
- compatibility resolution;
- static validation;
- motion parameters.

### SceneRecipe owns

- complete resolved actor identities;
- exact geometry parameters;
- exact positions, depth, and draw order;
- exact material and edge parameters;
- exact palette references and resolved colors where required;
- exact motion parameters;
- scale-aware rendering hints where unavoidable.

### Renderer owns

- faithful rasterization;
- antialiasing;
- GPU instancing and resource management;
- resolution-aware sampling;
- color-space-correct compositing;
- time evaluation from frozen motion parameters.

The renderer does not choose a more attractive color, new geometry, or new
material when the viewport changes.

## Family profile template

Every future detailed reference should be reducible to this profile:

```text
Family name
Primary visual process
Reference sources
Allowed composition behaviors
Allowed geometry regions
Primary material construction
Optional compatible material construction
Allowed edge regions
Allowed interaction types
Palette behavior
Depth behavior
Motion behavior
Common parameter region
Supporting mutation region
Rare mutation region
Forbidden region
Target-size rendering rules
Family acceptance tests
```

The detailed reference document may remain descriptive and visual. This profile
is the bridge from that description to a generator implementation.

## Existing family mapping

### Editorial Gradient Overlap

- Primary construction: Smooth Radial Color Field.
- Geometry: mostly closed circle-derived bodies.
- Edges: clean-soft or depth-softened.
- Interaction: transparent overlap and lens color.
- Composition: asymmetric scale hierarchy and broad overlaps.
- Primary risk: sharp inner spots, repeated gradient orientation, and muddy
  compositing.

### Linework Constellation

- Primary construction: Linework Structure.
- Geometry: rings, contours, annuli, arcs, and radial thread structures.
- Edges: hairline through heavy structural contour.
- Interaction: threading, nesting, tangency, and directional echo.
- Composition: anchor, curved chain, clusters, bridges, and negative space.
- Primary risk: diagram, gear system, flower, identical ring chain, or moire.

### Radial Fiber Fields

- Primary construction: Fiber Field.
- Geometry: closed radial, annular, incomplete, softly lobed, or soft-star
  envelopes.
- Edges: feathered fibers with an optional integrated arc.
- Interaction: woven density and core-over-fiber overlap.
- Composition: unequal stack or related curved gesture with generous margins.
- Primary risk: identical sunbursts, sharp pupil cores, hair, aliasing, and
  visible point-cloud breakup.

### Tensioned Loop Network

- Reference: [`composition/06`](../composition/06-tensioned-loop-network-reference.md).
- Primary construction: Tensioned Contour Network.
- Geometry: connected circle-derived loops with local relational deformation.
- Edges: hairline arcs widening gradually into bridges and shared junctions.
- Interaction: attraction, tension bridge, shared boundary, containment, and
  limited threading.
- Composition: one irregular connected current with unequal openings, dense
  connective regions, large anchors, and broad negative space.
- Depth: primary foreground network with an optional derived low-contrast echo.
- Primary risk: regular foam, chainmail, a node-link diagram, repeated star
  junctions, filled metaballs, or unstable topology.

### Harmonic Loop Fields

- Reference: [`composition/07`](../composition/07-harmonic-loop-fields-reference.md).
- Primary construction: Repeated Path Field.
- Geometry: stable continuous harmonic paths with frequency-, phase-, amplitude-,
  opening-, envelope-, and traversal-based mutation.
- Edges: continuous hairlines whose repetition creates silhouette and optical
  interior density.
- Interaction: transparent curve superposition, density weave, aperture
  framing, scale counterpoint, and deliberate separation.
- Composition: one dense overlap field balanced by a readable isolated actor,
  internal openings, edge crops, and protected external negative space.
- Depth: scale, line density, opacity, overlap order, and restrained focus.
- Primary risk: identical rosettes, literal flowers or atoms, security-pattern
  wallpaper, tangled density, moire, shimmer, or rapid rotation.

## Cross-cutting reference mapping

Some references define a DNA layer or modifier rather than a complete visual
family. They remain available to compatible family profiles.

### Asymmetric soft depth field

- Reference: [`composition/01`](../composition/01-asymmetric-overlap-reference.jpg).
- Primary contribution: Composition DNA and Depth DNA.
- Supplies: asymmetric mass balance, edge crops, overlap, negative space, and
  focus hierarchy.
- Does not define a mandatory material.

### Related shape variety and dense overlap

- Reference: [`composition/02`](../composition/02-related-shape-variety-dense-overlap.jpg).
- Primary contribution: Geometry DNA, Interaction DNA, and Composition DNA.
- Supplies: related mutation, dense interlocking, and neighbor-aware placement.
- Does not authorize every visible mutation in one scene.

### Small objects across the full canvas

- Reference: [`composition/03`](../composition/03-small-objects-full-canvas-scatter.jpg).
- Primary contribution: Composition DNA.
- Supplies: irregular full-field distribution, restrained scale range, edge
  contact, and breathing room.
- The small actors remain continuous objects, not a point-cloud material.

### Mist, depth, and fine texture

- Reference: [`materials/01`](../materials/01-mist-depth-and-grain-texture.jpg).
- Primary contribution: Depth DNA and material modifiers.
- Supplies: atmospheric focus, broad softness, low-contrast transitions, and
  stable tactile grain.
- Mistiness, blur, and grain remain modifiers unless a future approved
  reference establishes a distinct construction mechanism.

### Extreme continuous size hierarchy

- Reference: [`depth-and-scale/01`](../depth-and-scale/01-extreme-size-hierarchy-bubbles.jpg).
- Primary contribution: Depth DNA and Composition DNA.
- Supplies: a continuous diameter spectrum, cropped foreground giants, small
  distant actors, and irregular scale-position relationships.
- Does not require photorealistic bubbles or one giant in every scene.

### Random gradient circle source

- Source: [archived `random-gradient-circle.html`](https://github.com/Pudan416/step-trader/blob/a468729968a5463e379d185098bbedc06c44738c/DesignReferences/DayObjects/source/random-gradient-circle.html).
- Primary contribution: Material DNA and deterministic seed separation.
- Supplies: shifted radial centers, layered broad fields, related palette
  variation, transparency, outlines, and counterforms.
- Its individual style outputs are construction examples, not finished actor
  presets or independent material families.

### Soft Constructed Body Atlas

- Reference: [`materials/03`](../materials/03-soft-constructed-body-atlas-reference.md).
- Primary contribution: Geometry DNA, Material DNA, Edge DNA, Palette DNA, and
  the compatibility system.
- Supplies: soft compound carriers, stable geometry feature sites,
  geometry-aware radial fields, layered membrane fields, chromatic boundaries,
  and integrated inset behavior.
- Does not define one visual family or a Day Objects composition.
- One generated day selects one primary material mechanism and a small related
  carrier region rather than reproducing the source poster catalog.

## Three-reference expansion synthesis

The three references added after the initial DNA contract expand different
system dimensions and must remain distinct:

| Reference | Primary unit | New capability | Main interaction | Must not become |
| --- | --- | --- | --- | --- |
| Tensioned Loop Network | Related loop actors | Shared relational topology | Tension bridge and shared boundary | Foam or node-link diagram |
| Harmonic Loop Fields | One continuous path actor | Broad outcomes from frequency and phase | Transparent curve superposition | Spirograph catalog or literal flower |
| Soft Constructed Body Atlas | Carrier/material pairing | Transferable geometry-aware material | Membrane overlap and material response | Poster grid or effect catalog |

Together they establish three separate axes:

- actor-to-actor topology;
- internal path construction;
- carrier-to-material compatibility.

A family may adopt one primary axis and a small number of validated supporting
genes. The generator must not merge all three complete vocabularies into one
scene.

## No visible point clouds

Point clouds are excluded from the approved Day Objects generative vocabulary.

This means:

- an actor cannot dissolve into isolated dots as its final visible state;
- a circular perimeter cannot be represented only by disconnected particles;
- point scatter cannot be used as a substitute for grain;
- adding points around the canvas cannot be used to fill weak negative space;
- animated particles cannot emerge from or orbit an actor;
- a low-resolution fallback cannot turn fibers into discrete dots.

This does not prohibit invisible control vertices, sampled shader evaluation,
pixel-level grain, or line endpoints. Those are rendering and construction
details, not visual actors.

## Failure signatures across all families

Reject a phenotype when it contains:

- identical actors distinguished only by color;
- random independent materials with no family resemblance;
- a demo catalog showing every available construction at once;
- equal sizes and regular spacing;
- a centered or upper-only pile;
- rings, flowers, grids, rows, targets, pupils, gears, or literal star icons;
- sharp angular, linear, pyramidal, or pasted-on color transitions;
- muddy color overlaps;
- actors that disappear against the background;
- uniform focus with no depth;
- excessive blur hiding material problems;
- visible disconnected point clouds;
- rapidly spinning or locally jittering details;
- identity changes when another happening is added or removed;
- different artwork under Reduce Motion;
- renderer-specific random choices.

## System acceptance tests

### Determinism

- [ ] The same input and seed produce the same genotype.
- [ ] The same genotype produces the same frozen phenotype.
- [ ] Re-rendering a phenotype does not change actor identity.
- [ ] Changing only motion settings leaves the static frame unchanged.

### Stable identity

- [ ] Adding a happening preserves every surviving actor genome.
- [ ] Removing a happening preserves every surviving actor genome.
- [ ] Actor color, geometry, material, and phase remain stable.
- [ ] Any composition adjustment is bounded and deterministic.

### Family coherence

- [ ] One primary visual family is identifiable.
- [ ] Actor differences are mutations of that family.
- [ ] No scene displays the complete material catalog.
- [ ] Rare actors remain compatible with common actors.
- [ ] A ten-happening scene still reads as one artwork rather than ten style
      demonstrations.
- [ ] Supporting geometry remains a minority and is visibly derived from the
      primary geometry region.
- [ ] Accent material remains at or below the scene's approved budget.

### Across-day variety

- [ ] Adjacent days do not select the same primary family when another eligible
      family is available.
- [ ] Composition, primary geometry, and primary material do not repeat as one
      combination inside the rolling seven-day window.
- [ ] At least two major fingerprint axes change between adjacent days.
- [ ] Changing only the palette cannot satisfy the novelty test.
- [ ] Generating dates in a different order produces the same fingerprints.
- [ ] The boundary between two fourteen-day epochs does not restart with a
      duplicate of the preceding art direction.

### Geometry and material independence

- [ ] Approved materials can be evaluated on multiple compatible geometries.
- [ ] Geometry retains identity when a compatible material seed changes.
- [ ] Materials do not silently introduce unrelated geometry.
- [ ] Compatibility rules reject invalid pairings deterministically.

### Composition

- [ ] Roles and relationships explain actor placement.
- [ ] Scale hierarchy is intentional.
- [ ] Negative space remains legible.
- [ ] The scene avoids grids, rows, common rings, and central piles.

### Rendering

- [ ] Full-screen and calendar-tile renders express the same phenotype.
- [ ] Thin structures remain stable without crawling or false color.
- [ ] Color compositing remains clean in the target color space.
- [ ] No visible point-cloud fallback appears at small size.

### Motion

- [ ] Movement is slow, continuous, and individually phased.
- [ ] Depth produces readable parallax.
- [ ] Internal motion remains subordinate to whole-actor motion.
- [ ] Reduce Motion shows the same artwork at rest.

## Documentation rules

When a new visual reference is added:

1. Describe the reference on its own terms.
2. Identify which existing DNA layers it informs.
3. Decide whether it extends an existing family or justifies a new family.
4. Express new behavior as continuous parameters where possible.
5. Add compatibility and negative-signature rules.
6. Avoid copying universal seed, identity, and Reduce Motion rules into full.
7. Link back to this document.
8. Do not add a new named material for a mere opacity, blur, or grain change.

Reference documents remain visual evidence. This system document remains the
authority for how evidence becomes procedural generation.

## Incremental implementation strategy

The system should be introduced gradually rather than by replacing the current
Lab renderer all at once.

### Phase 1 — Document and normalize

- map existing references to DNA layers;
- remove duplicated or conflicting terminology;
- define family profiles;
- preserve existing approved visual checkpoints.

### Phase 2 — Extract stable generator inputs

- separate geometry, material, palette, and motion seeds;
- preserve actor identity across count changes;
- expose family and role decisions in debug output.

### Phase 3 — Add compatibility and mutation budgets

- encode family allowlists;
- add correlated parameter selection;
- add deterministic fallback for invalid combinations;
- verify diversity without weakening visual constraints.

### Phase 4 — Expand family by family

- implement one family profile at a time;
- compare procedural results with its references;
- keep new families inside Day Objects Lab until approved;
- freeze valid phenotypes into versioned `SceneRecipe` data.

This strategy preserves completed work. Existing approved scenes become known
phenotypes or fixtures while their underlying logic is progressively moved into
the common DNA generator.

## Final principle

The objective is not to maximize the number of named shapes.

The objective is to define a small number of visual processes with enough
continuous, deterministic variation to produce many distinct authored scenes.

A successful generation feels surprising in its specific composition and
actors, but inevitable in its visual language.
