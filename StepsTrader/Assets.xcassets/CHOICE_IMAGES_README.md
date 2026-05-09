# Canvas image assets

How the generative canvas (`GenerativeCanvasView`) picks bitmaps for **mind** and **heart** elements, and how to add or replace assets.

> Body elements are **procedural** (no bitmap). Only mind and heart elements consume Image Sets from this catalog.

## 1. Where things live

| Concern | File |
|---|---|
| Asset name catalog (drives picker / round-robin) | `StepsTrader/Models/ChoiceImageCatalog.swift` (enum `CanvasImageCatalog`) |
| Energy categories (`body` / `mind` / `heart`) | `StepsTrader/Models/DailyEnergy.swift` (`EnergyCategory`) |
| Option metadata (`id`, `titleEn`, `titleRu`, `category`, `icon`) | `StepsTrader/Models/DailyEnergy.swift` (`Option` registry) |
| Spawn / variant assignment | `StepsTrader/Views/GalleryView.swift` (`spawnElement`) |
| Variant cycling (long-press die) | `StepsTrader/Models/CanvasElement.swift` (`cycleAssetVariant`) |
| Per-frame draw | `StepsTrader/Views/GenerativeCanvasView.swift` (`drawCircle`, `drawRay`) |
| Heart beam swap helper | `Scripts/copy-heart-beam.sh` |

There is **no user-facing image picker**. When a category option is confirmed in `CategoryDetailView`, `GalleryView.spawnElement` randomly picks an `assetVariant` index into the catalog. Long-pressing an element on the canvas triggers `CanvasElement.cycleAssetVariant` to shuffle to a different variant.

## 2. Current asset counts

| Category | Catalog entries | Image Sets present | Notes |
|---|---|---|---|
| `mind` | **18** (`mind 1` … `mind 18`) | 18 | `mind 19.imageset` deleted as orphan |
| `heart` | **13** (`heart 1` … `heart 13`) | 13 | `heart 1` doubles as the soft-beam source for `drawRay` |
| `body` | **0** | 0 | Body uses `ProceduralShapeGenerator`, never reads this catalog |

Auxiliary (non-catalog) Image Sets in this xcassets:

- `grain 1` — paper-grain overlay used by the canvas backdrop
- `colors` — palette swatch reference image
- `instagram`, `tiktok`, `youtube`, `x`, `facebook`, `linkedin`, `pinterest`, `reddit`, `snapchat`, `telegram`, `whatsapp` — Shields icons (see §6)

## 3. Adding a new mind / heart asset

1. Open `StepsTrader/Models/ChoiceImageCatalog.swift` and append the new name to the matching array, e.g.

```swift
static let mind: [String] = [
    "mind 1", "mind 2", /* … */ "mind 18",
    "mind 19",                      // new
]
```

2. In Xcode → **Assets.xcassets** → right-click → **New Image Set**. Name it **exactly** like the catalog string (whitespace and case matter): `mind 19`.
3. Drop the PNG (or JPG) into the **1×** slot, or hand-edit `Contents.json`.
4. Recommended source: square (1:1), ≥ 200 × 200 pt so the @2x/@3x slots can downscale cleanly. Transparent background for hearts that need to feather over arbitrary canvas tints.
5. Build. The element type that uses this catalog will pick up the new entry on the next spawn / variant cycle (round-robin via `assetVariant % count`).

If a name in the catalog has no matching Image Set, `UIImage(named:)` returns `nil` and the canvas will silently skip that draw — see `CanvasImageCatalog.hasImage(named:)`.

## 4. Naming conventions

- **Spaces are part of the name.** `"mind 1"` (with a space), not `"mind1"` or `"mind_1"`. The Image Set folder, `Contents.json` `filename`, and the catalog string must all agree.
- The `filename` field inside an Image Set's `Contents.json` is what Xcode reads, **not** the folder name. If you rename one, rename both.
- One PNG per Image Set (1× slot only). Apple compiles 2×/3× downscales automatically when the slots are empty.

## 5. Heart soft-beam (`heart 1`)

`GenerativeCanvasView.drawRay` uses `heart 1` as the beam source bitmap (first entry in `CanvasImageCatalog.heart`). To swap in a new beam (e.g. a fresh Figma export):

- **Script (preserves filename `heart 1.png`):**

```bash
bash Scripts/copy-heart-beam.sh /full/path/to/your-beam.png
```

- **Manual:** open `StepsTrader/Assets.xcassets/heart 1.imageset/`, replace `heart 1.png` with the new file under the same name.

For best compositing on arbitrary canvas tints, prefer **PNG with alpha** (feathered edges). A flat black-on-white PNG also works but will visually clip on dark backdrops.

## 6. Shields icons (separate flow)

Shield template icons (Instagram, TikTok, etc.) are **not** loaded from `ChoiceImageCatalog`. They flow through:

- `StepsTrader/TargetResolver.swift` — `bundleToImageName` maps `bundleIdentifier → assetName`. Lookup tries the literal name, then `lowercased()`, then `capitalized`, so `instagram` and `Instagram` both resolve.
- `StepsTrader/Views/Apps/AppsPageSimplified.swift` — `allTemplates` lists the bundleIds offered when creating a new shield.

To wire a new shield icon:

1. Add Image Set in this xcassets (e.g. `mynetwork`).
2. Add `"com.example.app": "mynetwork"` to `bundleToImageName`. Add display name / scheme entries if needed.
3. Add `"com.example.app"` to `allTemplates.bundleIds` so users can pick it.

## 7. Known asset issues

- **`mind 15.imageset`** — historically shipped `mind 1.png` (md5 duplicate of `mind 1`). The Image Set has been migrated to a distinct PNG (`mind15.png`) and the duplicate has been removed; verify visually after pulling that the Mind canvas does not show two identical bitmaps for indices 0 and 14.
- **`heart 3.imageset`, `heart 6.imageset`, `heart 13.imageset`** — these intentionally `Contents.json` → reference earlier hearts (`heart 1.png`, `heart 3.png`, `heart 6.png` respectively). They render as visual duplicates of their referenced index. Replace the inner PNG and update `Contents.json.filename` if you want to introduce real variants.

If you remove an asset, also remove its catalog entry — orphan catalog strings cause `UIImage(named:)` lookups to return `nil` at runtime (silent skip in the renderer, but it shifts the round-robin distribution).
