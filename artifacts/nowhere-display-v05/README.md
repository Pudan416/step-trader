# Nowhere Display 0.5

Optical revision of 0.4, in Regular and Bold. Fourteen encoded characters were redrawn: `e е ё к g m n h r G & @ f t`.

The revised forms use continuous designed contours. Curved segments are compiled from cubic design paths into TrueType quadratic curves with a maximum conversion error of 0.5 font units. Cyrillic к deliberately uses straight contours. Bold has its own stroke and counter dimensions. Other glyph outlines, including the digits, remain unchanged.

- e/е/ё: continuous aperture, no rectangular ledge; balanced dots.
- к: relieved diagonal junction and consistent terminal cuts.
- g: continuous right stem and descending bowl.
- m/n/h/r: coordinated shoulder family with individually drawn m arches.
- G: continuous bowl and return, no rectangular inner tooth.
- &: new outline, clear right arm and separately drawn counters.
- @: continuous spiral and clear inner channel.
- f/t: flat hook terminals and more controlled curves.

## Preview

`preview.html` shows **0.4 on the left / 0.5 on the right**, in either weight, with editable text and numerical controls. English UI. Large sheets and words are in `review/optical/`.

Local URL: http://127.0.0.1:8772/v05/preview.html

Family: **Nowhere Display 05**; PostScript names `NowhereDisplay05-Regular` and `NowhereDisplay05-Bold`; version 0.500. Separately named files keep comparison and font caching unambiguous.

## Verification

`source/verify.py` checks exported TTF/WOFF2 outlines, coverage, intended contour counts, actual curved points, vertical bounds, preserved untouched glyphs and shaped pair geometry. Curve geometry is flattened densely for intersection testing; it is not a symbolic proof of Bézier intersections.

Both weights retain 163 encoded characters / 173 glyphs. 29,041 shaped pairs per weight are tested across normal kerning and tabular-digit contexts. No collisions were detected. Detailed hashes and results: `verification.json`.

Visual inspection covers the enlarged problem glyphs and word specimens in both weights. This is an experimental display font; no hinting or new character coverage has been added. Physical-device appearance has not been reverified in this revision.

## Build

Python dependencies: fonttools, shapely 2.x, brotli, uharfbuzz, Pillow.

```
python source/build.py
python source/verify.py
python review/optical/render_review.py
```

`source/base-*.ttf` preserve the actual 0.4 inputs. `compile.py` handles naming, export, kerning and tabular figures. `build.py` defines the new contours; `geometry.py` contains the geometric inspection helpers inherited and extended from the previous revision.

SIL Open Font License 1.1; see `OFL.txt`.
