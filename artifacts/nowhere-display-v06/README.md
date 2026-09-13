# Nowhere Display 0.6 — numerals

Regular and Bold, revising the numeral family and date separator from 0.5. Changed characters: `0123456789/`. All other glyph outlines and advances are preserved.

## Changes

- Coordinated oval construction, stroke contrast and round overshoot.
- Taller 6/9 counters; a reflected, shared construction for the pair.
- More open 8 counters and a balanced waist.
- Short flat base on 1; smoother 2/3/5 bowls and clean 4/7 terminals.
- Slash height reduced from 906 units to 720 units, matching the flat numerals.
- Optical spacing recalculated for digits and date/time separators.
- Tabular alternates use the same actual quadratic outlines with horizontal translation only.

## Preview

`preview.html`: 0.5 before / 0.6 after, Regular or Bold, editable dates and times, proportional or tabular figures. The tabular checkbox applies to both editable specimens and the numerical column. English interface.

Local preview: http://127.0.0.1:8772/v06/preview.html

Static comparison sheets: `review/Regular.png`, `review/Bold.png`. The sheets use proportional figures; interactive tabular figures are on the preview page.

## Verification

- 163 encoded characters and 173 glyphs per weight.
- 29,041 shaped pairs per weight, including tabular-digit contexts, without detected collisions.
- Exported contours valid under dense curve flattening; expected contour counts, numeral heights, slash bounds and sidebearings checked.
- Untouched encoded outlines and advances preserved; tabular outline geometry checked against translated proportional forms.
- TTF and WOFF2 outlines agree. Detailed hashes and results: `verification.json`.
- Inspected dates, time and digit rows at large sizes and 24 px in both weights; preview controls checked in the browser.

These checks do not replace optical judgment. No hinting or additional character coverage is introduced, and this package has not been installed into the native application.

## Rebuild

Dependencies: fonttools, shapely 2.x, brotli, uharfbuzz, Pillow.

```
python source/build.py
python source/verify.py
python source/render.py
```

Input fonts: the actual 0.5 exports in `source/base-*.ttf`. Family name **Nowhere Display 06**; PostScript names **NowhereDisplay06-Regular/Bold**; version **0.600**. SIL Open Font License 1.1; see `OFL.txt`.
