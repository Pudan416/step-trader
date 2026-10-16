# Widget app opening

An active widget link opens `steps-trader://openapp?bundleId=<public-id>`. Nowhere validates the target, covers its resumed root scene and uses `AppLauncher` to open the target. A selection must contain exactly one application and no categories or websites. The user confirms the association in **Open from widget**; editable group names never infer it.

## Shared catalog

`AppLaunchCatalog` in `Nowhere/Models/TicketGroup.swift` is compiled into both the app and widget. It supplies the public identity, display name, aliases and opening routes. `TargetResolver` derives its lookup tables from it; `AppGroupIdentity.applicationNames` derives the editor/widget choices. Adding a target must update this catalog, with regression coverage for the resulting single-app handoff.

Pinterest uses public bundle ID `pinterest`. `com.pinterest` is a persisted legacy alias, normalized on decode and lookup; it is not a separate choice.

## Opening policy

- Universal Links are attempted with `UIApplication.OpenExternalURLOptionsKey.universalLinksOnly`. A missing/unclaimed link returns failure; it must not open Safari or an App Store page.
- Existing custom URL schemes remain fallbacks for their established entries. New entries below use associated HTTPS routes without guessed schemes.
- An AASA rule confirms iOS routing eligibility, not installed-app availability or the app's destination screen. Physical acceptance must record the installed version and actual result separately. A route can stop being claimed when the target app changes.
- Groups with several targets open Nowhere. A changed Family Controls selection clears its saved app association.

## Added routes

Public bundle identities were checked in Apple Lookup on 2026-10-14 (US storefront). The following exact routes were matched to the owning bundle ID in the Apple-hosted AASA file on that date. Each source link includes its allowed paths/components. None of these URLs sends a message, buys an item, redeems a code or names media to start playing.

| App | Public bundle ID | Route | AASA source |
|---|---|---|---|
| Threads | `com.burbn.barcelona` | `https://www.threads.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/www.threads.com) |
| Discord | `com.hammerandchisel.discord` | `https://discord.com/app` | [Association](https://app-site-association.cdn-apple.com/a/v1/discord.com) |
| Twitch | `tv.twitch` | `https://www.twitch.tv/home` | [Association](https://app-site-association.cdn-apple.com/a/v1/www.twitch.tv) |
| Bluesky | `xyz.blueskyweb.app` | `https://bsky.app/` | [Association](https://app-site-association.cdn-apple.com/a/v1/bsky.app) |
| Spotify | `com.spotify.client` | `https://open.spotify.com/home` | [Association](https://app-site-association.cdn-apple.com/a/v1/open.spotify.com) |
| Netflix | `com.netflix.Netflix` | `https://www.netflix.com/browse` | [Association](https://app-site-association.cdn-apple.com/a/v1/www.netflix.com) |
| YouTube Music | `com.google.ios.youtubemusic` | `https://music.youtube.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/music.youtube.com) |
| Temu | `com.einnovation.temu` | `https://www.temu.com/?_p_dp=1` | [Association](https://app-site-association.cdn-apple.com/a/v1/www.temu.com) |
| SHEIN | `zzkko.com.ZZKKO` | `https://api-shein.shein.com/h5/sharejump/appjump` | [Association](https://app-site-association.cdn-apple.com/a/v1/api-shein.shein.com) |
| Etsy | `com.etsy.etsyforios` | `https://www.etsy.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/www.etsy.com) |
| Depop | `com.garageitaly.garage` | `https://www.depop.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/www.depop.com) |
| Vinted | `lt.manodrabuziai.fr` | `https://www.vinted.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/www.vinted.com) |
| StockX | `com.Campless.Campless` | `https://stockx.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/stockx.com) |
| GOAT | `com.airgoat.goat.ios` | `https://www.goat.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/www.goat.com) |
| Duolingo | `com.duolingo.DuolingoMobile` | `https://www.duolingo.com/home` | [Association](https://app-site-association.cdn-apple.com/a/v1/www.duolingo.com) |
| Tinder | `com.cardify.tinder` | `https://go.tinder.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/go.tinder.com) |
| Bumble | `com.moxco.bumble` | `https://bumble.com/nav/` | [Association](https://app-site-association.cdn-apple.com/a/v1/bumble.com) |
| Hinge | `co.hinge.mobile.ios` | `https://hinge.co/app/` | [Association](https://app-site-association.cdn-apple.com/a/v1/hinge.co) |
| Character.AI | `ai.character.app` | `https://character.ai/profile/` | [Association](https://app-site-association.cdn-apple.com/a/v1/character.ai) |
| ChatGPT | `com.openai.chat` | `https://chatgpt.com/open-app` | [Association](https://app-site-association.cdn-apple.com/a/v1/chatgpt.com) |
| Brawl Stars | `com.supercell.laser` | `https://link.brawlstars.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/link.brawlstars.com) |
| Clash Royale | `com.supercell.scroll` | `https://link.clashroyale.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/link.clashroyale.com) |
| Clash of Clans | `com.supercell.magic` | `https://link.clashofclans.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/link.clashofclans.com) |
| Hay Day | `com.supercell.soil` | `https://link.haydaygame.com/` | [Association](https://app-site-association.cdn-apple.com/a/v1/link.haydaygame.com) |

The four Supercell links use the associated root path without invitation/reward parameters. Bumble and Hinge use their associated navigation/app entry prefixes. Character.AI opens the current profile entry. These entries require physical-device screen acceptance when the apps are available; rule matching alone is not evidence of their internal destination.

## Regression checks

`TargetResolverLaunchTests` checks all added routes, shared widget/editor identity, single-app handoff eligibility and Pinterest compatibility. `WidgetTests` checks that groups, categories, websites, missing/corrupt selections and editable names cannot invent a launch target. Physical routing can additionally be exercised with the identical widget URL via `devicectl --payload-url`, while reading the app's `WidgetInteraction` result; this does not simulate the Home Screen widget tap.
