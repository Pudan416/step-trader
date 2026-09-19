# Nowhere

An iOS app where sleep, activity and happenings make colors, a daily Canvas,
and generative music. Colors buy access to selected feeds.

## Start here

| Need | Read |
| --- | --- |
| What the app does | [Product](docs/product.md) · [Product principles](PRODUCT.md) |
| Where to change something | [Code map](docs/architecture/overview.md) |
| Canvas, Metal and saved-artwork compatibility | [Canvas components](docs/architecture/canvas-components.md) |
| Build, test, configure or install | [Development](docs/development.md) |
| Audio assets and reproducible sound tools | [Audio](docs/audio.md) |
| Product writing | [Tone of voice](docs/brand/tone-of-voice.md) |
| Working rules for agents | [AGENTS.md](AGENTS.md) |

## Repository

- `StepsTrader/` — app source. `Experiments/DayObjects` and `Experiments/ShapeGenome`
  contain production rendering and audio despite their historical names.
- `Steps4.xcodeproj/`, `Steps4/`, `Config/` — targets, bundle configuration and secrets templates.
- `Shared/` — code/resources shared with extensions.
- `UnlockWidget/`, `DeviceActivityMonitor/`, `ShieldConfiguration/`, `ShieldAction/` — extensions.
- `Steps4Tests/`, `Steps4UITests/` — regression and UI tests.
- `Scripts/`, `Tools/` — development tools; see [development](docs/development.md).
- `supabase/`, `admin-panel/`, `tg-admin/`, `web/` — backend and standalone web/admin projects.
- `docs/` — maintained documentation. Read the relevant page, not the whole directory.

Open `Steps4.xcodeproj` and select the **Steps4** scheme (product: **Nowhere**).
Start with the local setup in [development](docs/development.md).

`main` is the integration branch. Screenshots, exported audio, logs, completed plans
and one-off reviews belong in ignored `artifacts/` or `outputs/`, not the source tree.
Previous designs and reports remain available in Git history; retrieve them only
when investigating a specific historical decision. See [history and housekeeping](docs/development.md#history-and-housekeeping).
