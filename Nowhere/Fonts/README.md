# Bundled typography

- **Onest** — interface and poster metadata, nine static weights from Thin to Black.
- **Nowhere Display 0.9.1** — display accents, Regular and Bold.

`Utilities/Font+Custom.swift` selects the real font faces. Weights up to Medium use
Nowhere Display Regular; SemiBold and above use Bold. Compatibility helpers named
`geist`, `geistMono` and `unbounded` forward to these current families.

Onest's variable source is [Google Fonts](https://github.com/google/fonts/blob/main/ofl/onest/Onest%5Bwght%5D.ttf),
SHA-256 `966c5c29b4755da84b6854d5c21dd4eaa2420225d0e9874de602de176d4a9f31`.
The static files were instantiated at weights 100–900 with fontTools, preserving
outlines and assigning the Onest PostScript names used by the app.

Nowhere Display PostScript names are `NowhereDisplay091-Regular` and
`NowhereDisplay091-Bold`. Earlier font prototypes/specimens remain in Git history;
only the distributed font files belong here.

Keep `Onest-OFL.txt` and `NowhereDisplay-OFL.txt` with the fonts. Both families are
bundled offline, registered through the app configuration and acknowledged in Settings.
