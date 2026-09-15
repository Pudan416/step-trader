# Happenings controls at the tab bar level — 2026-09-15

Code revision: `95c698d9ba76066c0472580aa726fccc99b86e62` on `codex/happenings-field`.

The list, Frequent/All and close controls now use the measured global center of the tab bar. MainTabView retains that measurement when the tab bar disappears for Happenings. The palette row calculates its inset from its own container's global bottom, avoiding a mismatch with the canvas safe-area origin.

Both simulator and signed iPhone app builds completed. All four embedded extensions, strict signatures, provisioning and required resources passed verification; the build mirror matches 1164 tracked source files. The existing Frequent/All UI regression now asserts all four buttons share the original tab bar's center within 1 point.

UI verification could not complete: Xcode timed out preparing the simulator before any test assertions ran. Retries remained stuck before test execution. The owned simulator was restarted once; ordinary app launch also remained on its launch screen. Pending test/launch commands were stopped; other simulators were preserved. Therefore no successful UI test or visual alignment verification is claimed for this revision.

Failed setup result: `/tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_21-17-24-+0200.xcresult`.

Isolated feature build, as requested. No integration push. Device installation and launch results are recorded in `device-verification.json`; physical-device visual verification was not performed.

Wi-Fi installation on iPhone Costa succeeded; normal launch succeeded at 21:29 Europe/Belgrade. Installed revision: `95c698d9ba76066c0472580aa726fccc99b86e62`.
