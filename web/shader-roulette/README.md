# Shader Roulette

A one-page generative-art engine built around deterministic visual genomes. Each unsigned 32-bit seed selects a coherent geometry family, material, palette, composition, and motion profile; the same seed always recreates the same identity.

## Local development

```bash
npm run dev
npm test
npm run build
```

The app uses WebGL2 for its full renderer and falls back to deterministic Canvas 2D artwork when WebGL2 is unavailable. Use `?seed=0x00008F31` to reopen a particular result.

## Sculptural generator (edition 3)

The default “Все” collection mixes new surface studies with the original generator (25% classic). “Новые” selects only the new generator; “Классика” directly restores the original six-family generator. The simple edition-2 silhouettes remain available through their saved URLs and are excluded from new rolls.

New objects combine parametric paths, variable widths, independent crossing depths, cross-section profiles, folds, and finishes. Eight curve constructions include torus knots, harmonic waves, apertures, hypotrochoids and coiled shells; four membrane constructions create wide folded, pleated, faceted and paired surfaces. Continuous parameters and variations change the geometry while preserving a study's palette and construction. They are handcrafted generative recipes, not imported gallery artworks or a claim to exhaust Shader Park's capabilities.

Shader Park compiles the surface profile and membrane contours during `npm run shaders`. The WebGL renderer evaluates their profiles against 128-segment swept curves or bounded membrane fields, with studio reflections, iridescence, glass, satin and optional fine engraving. Curves are centred and fit into a safe disc; the stage reserves room for controls and titles. The Canvas fallback uses the same curves and contours with simplified reflections, caches the image, and animates its orientation. WebGL animates both the shape orientation and surface folds.

Links encode `v=3`, `seed`, optional `variation`, and collection. Version-1 and version-2 URLs retain their generators. PNG export is 2048 × 2048. “Похожее” works for new and classic forms. The earlier generator is fitted to the available stage in edition 3; direct version-1 links preserve the earlier framing.

Validation includes deterministic variation/collection restoration, original-genome equivalence, curve and membrane bounds, visible Canvas fallback rasters, and actual compilation/linking/rendering of 36 specimens using macOS OpenGL with a GLSL 330 wrapper. This validates the shaders, not browser UI interactions.

## Archived flat figures (edition 2)

Archived recipes use eight bounded silhouette families: rosette, spark, organism, loop, crescent, emblem, fan and ribbon. Every family is authored in `scripts/flat-recipes.mjs` using Shader Park scalar expressions. The compiler runs before development and production builds; generated modules are tracked so ordinary tests need no browser or compiler setup.

This archived experience has solid, softly graded, iridescent or outlined fills. “Похожее” retains its recipe; “Ещё” returns to edition 3. Links encode `v=2`, `seed`, and optional `variation`; URLs with just a seed continue to use the original generator.

Validation covers legacy behavior, seed and variation reproducibility, URL restoration, and finite, nonempty distance fields with safe margins across 256 varied seeds. For GPU validation, the generated WebGL shader was also compiled and rendered on macOS OpenGL using an equivalent GLSL 330 wrapper; this is shader validation, not a browser UI test.
