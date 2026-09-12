# Nowhere Display 0.4

An edited Regular and Bold family, refining the audited Nowhere Display 0.3 outlines. This package contains the actual revised TTF/WOFF2 files, not only review images.

## Changes

- Distinct Cyrillic У, lowercase ё built from е, x-height к, and a clearer ф stem.
- Continuous U/J/g/u curves, smooth n/m/h/r shoulders at a shared x-height, and cleaner Л/Д/л/д joins.
- Connected question-mark hook; cleaned ampersand and at-sign interiors.
- More open Bold e/е and Cyrillic counters; refined A/А and percent counters.
- Cleaner G/Q/f/t transitions, round punctuation dots, separated curly quotes and № components.
- A compact j hook and revised spacing using profiles that include descenders and accents, with exact geometric pair checks.
- Original numeral shapes from 0.3 and tabular numeral alternates retained. No special-case wordmark or WH ligature.

The new family is **Nowhere Display 04**, with PostScript names **NowhereDisplay04-Regular** and **NowhereDisplay04-Bold**. Version 0.400. Weight classes 400/700. Separately named so 0.3 remains available for direct comparison.

## Preview

Open `preview.html` through a local HTTP server. Previous 0.3 is on the left, revised 0.4 on the right. Select Regular/Bold, change size, enter text, inspect changed forms and expand the full character set. All interface copy is English; specimen text includes Russian.

`review/Regular.png` and `review/Bold.png` are static before/after comparisons.

## Verification

- 163 Unicode characters, 173 glyphs per font, including 10 unencoded tabular alternates.
- 58,082 shaped pair checks across both weights and proportional/tabular contexts: no outline collisions in the final files.
- All individual contours and filled geometries valid after integer-coordinate export.
- 17 targeted regression checks pass in Regular and 22 in Bold; the same checks reproduce 12 and 21 failures respectively in the retained 0.3 inputs.
- Outlines and advances outside the stated change list are preserved exactly. Kerning is intentionally updated for affected pairs.
- TTF/WOFF2 outlines, metrics, cmap, GPOS and GSUB agree.
- Browser preview verified with all four font files loaded; Regular/Bold, text, size and numeric controls exercised.

Details: `build.json`, `verification.json`, `review/full/audit.json`.

## Rebuild

Python dependencies: fonttools, shapely (2.x), brotli, uharfbuzz, Pillow.

```
python source/build.py
python review/full/audit.py
python source/verify.py
python source/render.py
```

`source/base-*.ttf` are the unchanged 0.3 inputs. `source/geometry.py` retains the earlier geometry helpers. The sources and license are included for reproducibility.

## Scope

This remains an experimental display font. No new character coverage or production hinting was added. Small-size appearance depends on the rasterizer and display density; verification here uses FreeType and the desktop browser, not a physical iPhone. Missing symbols such as $, €, ₽ and braces still require fallback. This package does not install or replace fonts in the native app.

SIL Open Font License 1.1; see `OFL.txt`.
