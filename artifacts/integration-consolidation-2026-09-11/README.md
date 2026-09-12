# Current Integration consolidation — 11 September 2026

## Root cause
The installed b1dfca54 was the current remote integration revision, but its source composition was incomplete. The muted reading-page background remained in backup commit 514e89e4. During the previous consolidation it was incorrectly treated as superseded by CanvasChromePalette. Those changes serve different roles: page background and control colors. The shipped light theme still applied a 76% white veil.

## Included in this revision
- Restore TodayCanvasInterfacePalette from 514e89e4: muted daily pigment, bounded perceptual background lightness around 0.69, readable dark text, opaque light-theme background including Reduce Transparency. Preserve current daily CanvasChromePalette buttons and global accent handoff.
- Restore Feeds selected-group title/detail and custom group name on its Open action.
- Restore darker secondary ink for the muted page background.
- Port PR #22 (bd579cb4): purchased access deadlines, including widgets and day-boundary changes.
- Port PR #23 (bdb4fb4e): verify Screen Time authorization before charging in app and widget.
- Port PR #24 (1857c292): distinguish unavailable notifications and discard stale PayGate requests. Preserve current real-shape artwork handoff and artwork in the new fallback state.
- Port PR #25 (f269b443): all embedded extension minimum iOS versions match the host app; regression checks inspect actual built bundles.

## Existing work retained
- Current 21 real Happening gate images and random fallback with no user objects.
- Widget/settings integration (62538e26), current daily accents and Play controls, spaced Feeds cards, Me calendar selection and removed clipped poster shadow.
- Canvas rotation/smudge preservation and audio performance fixes (c1385efe).
- Vertical lead filter sweep (b1dfca54).
- Apple sign-in loading cleanup from 2424cda7 is already implemented in current AuthenticationService.runSignIn, including defer reset, cancellation, timeout, and AuthSignInLoadingStateTests. Do not overwrite later account/session fixes with the older branch.
- ModernPaletteCatalog matches the catalog branch; newer rendering and routing changes are retained.

## Preserved separately
- Canvas V2 is an alternative experimental renderer with 48 dirty tracked files, not an additive visual fix. It remains separately preserved pending an explicit choice to switch renderer. Current Canvas continues to ship.
- Editorial composition/material/outline A/B experiments contain competing rendering alternatives and evidence tools. They are not blindly merged over the selected production renderer.
- Chat-wiki, local archive, and web shader-roulette are separate tools/sites, not iPhone app updates.
- Older orb/cleanup branches are divergent historical rendering stages. Current newer rendering, modern palette selection, and production routing are retained.
- Original dirty worktrees and archive-current-integration-wip-20260911 remain intact.

Verification and installation results are recorded below after completion. Simulator screenshots are visual evidence for the simulator only; device installation/launch does not claim physical UI or listening verification.

## Verified
- 117 selected unit tests passed, 0 failures: background/contrast, Feeds layout, payment, access expiry, monitoring errors, widget bundles and gate artwork.
- 1 UI test passed: Settings, Appearance, Feeds, Me, Play fullscreen, landscape and return to portrait.
- Screenshots here are real simulator captures. Feeds shows the empty state; Me uses a static-poster fixture.
