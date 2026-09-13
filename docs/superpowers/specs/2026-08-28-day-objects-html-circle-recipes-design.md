# Day Objects HTML Circle Recipes Design

Date: 2026-08-28
Status: Approved
Branch: `codex/current-integration`

## Goal

Replace the simplified five-material Day Objects implementation with a faithful
Metal adaptation of `/Users/kosta/Downloads/random-gradient-circle.html`.
Consecutive days choose different circle recipes, while all happenings inside
one day remain members of one coherent visual family.

## Daily recipe

The day seed selects one weighted recipe from the HTML catalog:

- `gradient` (weighted twice, matching the HTML source);
- `solid`;
- `sphere`;
- `glass`;
- `mist`;
- `halo`;
- `luminous`;
- `outline`;
- `counterform`.

One recipe is shared by every actor in a day. Per-event mutation may vary focal
offset, radial radius, stop placement, layer opacity, outline spacing, glow,
softness, and up to five-percent elongation, but may not switch recipe.

## Radial construction

Visible fill color is generated from a single scalar radial distance around a
seeded, shifted focal point. One to three palette colors form ordered smooth
stops. Additional radial layers may modulate light and surface depth, but they
must not compete as independently normalized color lobes and must not produce
angular, conic, pyramidal, or Voronoi-like seams.

The Metal adaptation keeps at most three analytic layers per actor for the
existing single instanced pass. This represents the HTML layer stack without
per-object textures or SVG filters.

## Recipe-specific rendering

- `gradient`: dense smooth radial fill with a shifted center.
- `solid`: one-color body with only subtle radial lighting.
- `sphere`: dense body, broad directional volume, rim, and soft highlight.
- `glass`: colored translucent body, background refraction, visible rim, and
  highlight; it must not dissolve into the background.
- `mist`: soft edge and depth, with a visible chromatic core.
- `halo`: luminous colored body plus a broad outer aura.
- `luminous`: bright internal radial source and restrained halo.
- `outline`: one to three colored circular contours with related spacing and
  wobble; every actor in an outline day remains contour-based.
- `counterform`: a radial body with a soft subtracted center and a colored
  corona around the opening.

## Visibility

At steady state every recipe must retain a readable silhouette. Body alpha may
reach zero only during explicit insertion or removal transitions. The actor
render pass enforces a recipe-appropriate visible-alpha floor, and glass/mist
retain enough direct palette tint to remain distinguishable from the sampled
background. At least two actors remain in a readable depth phase in animated
multi-actor scenes.

## Size and motion

The existing full-canvas choreography remains. Per-actor size hierarchy and
depth/breathing phases stay deterministic and independent. The recipe change
does not reintroduce upper-screen clustering, synchronized scale, or rapid
local spinning.

## Constraints

- Maximum ten actors and one instanced actor draw.
- One to three object colors from the day's two object palettes.
- No bitmap material or per-object offscreen pass.
- Stable per-day and per-event seeds.
- Adding an event does not reroll retained appearances.
- Procedural grain remains unchanged.
- Unrelated feed, localization, and application-shell changes in the worktree
  are not modified or staged.

## Acceptance

Tests must prove that every recipe is reachable across day seeds, all actors in
a day share the selected recipe, outline actors emit contour parameters,
counterform actors emit a non-zero cutout and corona, radial stop order remains
monotonic, and steady-state visibility floors are respected. GPU captures must
distinguish outline and counterform from filled recipes and demonstrate a
smooth shifted radial fill without angular seams.
