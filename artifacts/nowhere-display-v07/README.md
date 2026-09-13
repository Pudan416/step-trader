# Nowhere Display 0.7 — Cyrillic б

Targeted revision of lowercase Cyrillic б in Regular and Bold. Continuous outer bowl and neck replace the previous joined ring and angular flag. The upper flag remains distinct from the numeral 6; Bold has a taller, more open counter.

All other outlines and advances, including the revised 0.6 numerals and their tabular alternates, are preserved. Kerning is recalculated for affected letter pairs.

Preview: `preview.html`, 0.6 before / 0.7 after. Local URL: http://127.0.0.1:8772/v07/preview.html

Word comparison sheets: `review/Regular.png` and `review/Bold.png`. Reviewed at enlarged size and in words at 24/44/46 px, plus the desktop browser.

Verification: 163 encoded characters / 173 glyphs in each weight; valid flattened contours, two intended contours for б, real TrueType curved points, untouched glyph preservation and TTF/WOFF2 outline agreement. 29,041 shaped pairs per weight checked without detected collisions. See `verification.json` for hashes and details. Geometric tests do not replace optical judgment or physical-device review.

Family: Nowhere Display 07. PostScript names: NowhereDisplay07-Regular/Bold. Version: 0.700. No new coverage or hinting. This package does not replace the app's installed fonts.

Rebuild with fonttools, shapely 2.x, brotli, uharfbuzz and Pillow:

```
python source/build.py
python source/verify.py
python source/render.py
```

The base fonts are the exact 0.6 exports. SIL Open Font License 1.1; see `OFL.txt`.
