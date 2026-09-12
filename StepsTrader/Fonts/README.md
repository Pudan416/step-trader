# Nowhere typography

- **Onest**: primary interface and poster metadata, weights 100–900.
- **Nowhere Display 02**: original display font, Regular (400) and Bold (700), from the approved 0.2 specimens.

Both font families are bundled offline. Copyright notices and SIL OFL 1.1 texts are included in the app and readable in Settings → About → Font licenses.

## Sources

Onest variable source: https://github.com/google/fonts/blob/main/ofl/onest/Onest%5Bwght%5D.ttf

Source SHA-256: `966c5c29b4755da84b6854d5c21dd4eaa2420225d0e9874de602de176d4a9f31`

The nine static Onest files were instantiated from this source with fontTools.varLib.instancer at wght=100, 200, …, 900, using updateFontNames=True. Outlines and other font features were preserved. Their PostScript names are Onest-Thin through Onest-Black.

Nowhere Display files were copied from `artifacts/nowhere-display-v05/fonts/`. PostScript names: NowhereDisplay05-Regular and NowhereDisplay05-Bold. This prototype covers basic Latin, Russian Cyrillic, digits, and selected punctuation; iOS supplies fallback for other characters.

## App mapping

`AppTypography` selects real faces by weight. Onest body text defaults to Regular; headline text uses SemiBold. Nowhere Display weights up to Medium use Regular; SemiBold and above use Bold. Fixed poster sizes and relative UI text sizing are preserved.

Legacy `geist`, `geistMono`, and `unbounded` helpers forward to the new pair to keep existing screens source-compatible. Old font files retained in this directory are no longer included in the app target.
