# Happenings: three iPhone sizes — 2026-09-15

Verified code revision `95c698d9ba76066c0472580aa726fccc99b86e62`, the revision already installed on iPhone Costa. No product code change was needed during this verification.

All **6 UI tests passed** on iOS **26.3.1 simulators**, in portrait:

| Model | Tab bar baseline | Frequent | All | Accessibility text |
| --- | --- | --- | --- | --- |
| iPhone 13 mini | [Screenshot](mini-baseline.png) | [Screenshot](mini-frequent.png) | [Screenshot](mini-all.png) | [Screenshot](mini-large-type.png) |
| iPhone 15 Pro | [Screenshot](pro-baseline.png) | [Screenshot](pro-frequent.png) | [Screenshot](pro-all.png) | [Screenshot](pro-large-type.png) |
| iPhone 17 Pro Max | [Screenshot](max-baseline.png) | [Screenshot](max-frequent.png) | [Screenshot](max-all.png) | [Screenshot](max-large-type.png) |

The automated check reads the original Canvas tab button's vertical center, opens Happenings, and verifies the list, close, Frequent and All buttons are centered at that same level within **1 point**. It verifies the alignment in both modes, tap availability, a fixed switch frame during panning, the return to the original Frequent layout, and reopening. The second scenario exercises the accessible large-text list and Health choices.

The baseline, Frequent, All and large-text screenshots were also visually inspected on all three sizes. No alignment or button clipping defect was found in the requested row. These are simulator results, not physical verification on three phones.

## Reproducibility

- Both tests: `Steps4UITestsLaunchTests/testFrequentDefaultsIncludeHealthAndSwitchBackFromAll` and `Steps4UITestsLaunchTests/testFrequentSwitchAndHealthChoicesRemainReachableAtLargeType`.
- Result bundles and simulator identifiers: [verification.json](verification.json).
- Native Xcode summaries: [mini](mini-summary.json), [Pro](pro-summary.json), [Max](max-summary.json).
- The build mirror matches all 1164 tracked non-artifact files in the feature worktree.

Initial attempts were blocked by CoreSimulator service failures and fresh-device CoreLocation data migration. No Xcode builds or tests were active when the shared simulator service was restarted. Successful verification used separate clones of already initialized iOS 26.3 devices; their source devices were not modified or erased. Attempts to use fresh iOS 26.5 devices were abandoned before testing. The earlier blocked report in `happenings-tab-level-2026-09-15` is superseded by these successful UI results.

After verification, the three QA clones were shut down and all six simulators that had been booted before the service restart were restored to the Booted state. No simulator data was erased.
