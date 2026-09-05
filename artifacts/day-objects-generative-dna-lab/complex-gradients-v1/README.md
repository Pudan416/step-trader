# Day Objects — complex gradient review

These four stills were captured from the real instanced Metal renderer in Day Objects Lab with ten happenings, the Generative DNA material mode, and depth-field placement.

- `01-two-colour-2026-01-04.png`: broad two-colour sweep.
- `02-three-colour-2026-01-14.png`: asymmetric three-colour field.
- `03-three-colour-2026-01-19.png`: saturated three-colour field.
- `04-three-colour-2026-01-24.png`: airy low-contrast three-colour field.

The colours come only from each day's approved object palettes. A day selects one gradient topology and one coherent colour relationship, while actor-local field orientation varies slightly. All transitions are overlapping radial fields; there are no angular splits, linear stops, hard patches, or animated colour rerolls.

Capture test:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4UITests/DayObjectsLabUITests/testComplexGradientExamplesVisualHandoff \
  CODE_SIGNING_ALLOWED=NO
```
