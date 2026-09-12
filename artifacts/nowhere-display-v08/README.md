# Nowhere Display 0.8 — simpler Cyrillic б

A second optical revision of lowercase б in Regular and Bold. The wavy 0.7 flag is replaced with a level upper stroke, a single rounded shoulder and a vertical end. The lower bowl and counter retain their 0.7 geometry.

All other glyph outlines and advances, including the 0.6 numerals, remain unchanged. Affected letter-pair kerning is recalculated.

Preview: `preview.html`, 0.7 on the left and 0.8 on the right. Static comparison sheets: `review/Regular.png` and `review/Bold.png`. Local URL: http://127.0.0.1:8772/v08/preview.html

`source/verify.py` checks exported contours, unchanged glyphs, TTF/WOFF2 outlines and 29,041 shaped pairs per weight. See `verification.json`. Geometric validation is separate from optical judgment. This package has not been installed in the app.

Rebuild with fonttools, shapely 2.x, brotli, uharfbuzz and Pillow:

```
python source/build.py
python source/verify.py
python source/render.py
```

Family: Nowhere Display 08. PostScript names: NowhereDisplay08-Regular/Bold. Version 0.800. Inputs are the actual 0.7 fonts. SIL Open Font License 1.1; see OFL.txt.
