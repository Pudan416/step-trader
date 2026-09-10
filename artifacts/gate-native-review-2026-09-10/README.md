# Happenings artwork on gate screens — 10 September 2026

The independent silhouette generator has been replaced by transparent snapshots from the app's actual Metal happening catalog. `objects.png` shows all 21 bundled variants.

- `03-paygate.png` through `06-paygate-alternative.png`: real simulator screenshots of production `PayGateView`, with temporary fixture data. Includes a normal balance, insufficient colors and the approaching day boundary.
- `01-shield.png`, `02-shield-notification.png`: SwiftUI reconstructions of the system-owned Screen Time shield. Use the actual artwork renderer and current copy, but are not iOS Shield screenshots. System layout still needs physical-iPhone verification.
- `01-flow.png` and `02-paygate-states.png`: contact sheets arranging those unedited screenshots.
- `ScreenshotFixture.swift`: temporary launch fixture retained for reproduction. It was removed from the production source after capture. No screenshot-specific model changes are shipped.

Seeds: 0 for the shield and normal PayGate (concave square / side light), 9 for insufficient colors (windflower / radial two), 18 for the day boundary (soft square / procedural light), 16 for another entry (windflower / procedural light). Real sessions choose randomly, independently of balance.

Validation: app + extensions built successfully; all 10 GateArtworkTests passed, including matching images in both app and ShieldConfiguration bundles.
