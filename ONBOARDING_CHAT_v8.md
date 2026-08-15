# Nowhere — Chat Onboarding (v8 proposal)

**Status:** Proposal — design review, not implemented
**Version:** v8
**Based on:** v7 (13 slides, shipped — see [ONBOARDING_FLOW.md](ONBOARDING_FLOW.md))
**Prototype:** [`web/prototypes/onboarding-chat.html`](web/prototypes/onboarding-chat.html) (open in a browser, tap the highlighted replies)
**Estimated completion time:** 150–210s (v7: 60–80s) — see [§11 Risks](#11-risks--open-questions)
**Last updated:** July 30, 2026

---

## Table of Contents

1. [Why change the structure](#1-why-change-the-structure)
2. [Structural comparison v7 → v8](#2-structural-comparison-v7--v8)
3. [Act-by-act specification](#3-act-by-act-specification)
4. [Component spec](#4-component-spec)
5. [Personalization — chips replace sliders](#5-personalization--chips-replace-sliders)
6. [Permission priming](#6-permission-priming)
7. [Copy audit against TONE_OF_VOICE](#7-copy-audit-against-tone_of_voice)
8. [What v8 drops from v7](#8-what-v8-drops-from-v7)
9. [Analytics](#9-analytics)
10. [Accessibility & localization impact](#10-accessibility--localization-impact)
11. [Risks & open questions](#11-risks--open-questions)
12. [Implementation plan](#12-implementation-plan)

---

## 1. Why change the structure

v7 works, but its shape fights its own content. Three specific problems:

**The founder monologues.** v7 is 13 full-screen slides of the founder talking. The user's only verb is "Next." The copy is written in first person ("i found that i live one day over and over") but the format gives the user no way to answer. It reads like a letter, not a conversation.

**Targets are set before they mean anything.** Slides 6–7 hand the user two sliders (steps 5k–15k, sleep 6–10h) with no frame of reference. A user who has never counted their steps picks 10,000 because it's the default, not because it fits their life. The number is arrived at by shrug.

**The stakes are asserted, never felt.** v7 says "i live one day over and over" and trusts the user to recognize themselves. There's no moment where the user's own input produces an uncomfortable number.

v8 keeps the entire v7 narrative and mechanic — same aha moment, same economy, same canvas — and changes the **container**: a chat with the founder. The user answers, and their answers do two things: drive the copy (the founder reacts) and set their configuration (chips replace sliders).

### What this buys

| v7 problem | v8 answer |
|---|---|
| User has one verb ("Next") | Every act asks something answerable |
| Targets set blind | Targets inferred from a question about the user's actual life |
| Stakes asserted | Stakes computed from the user's own answer (§3, Act 1) |
| Permission dialogs arrive cold | Priming cards explain the iOS dialog before it appears (§6) |
| 13 discrete screens to maintain | One transcript; beats are data, not view code |

---

## 2. Structural comparison v7 → v8

### Shape

| | v7 | v8 |
|---|---|---|
| **Unit** | Full-screen slide | Chat beat (bubble / card / question) |
| **Count** | 13 slides | 4 acts, ~34 beats |
| **Forward** | Bottom CTA "Next" | Tapping a reply chip in the dock |
| **Back** | Swipe right >60pt | **None** — transcript scrolls up but is immutable (see [§11](#11-risks--open-questions)) |
| **Progress** | 12-segment bar, grouped 6-4-2 | 5 dots + background warmth (`--warm` 0.10 → 0.60) |
| **Pacing control** | App (scroll disabled) | App (typing indicator delays) |
| **Interactive surfaces** | 2 (colorCap, spendDemo) | 5 (stakes, ring, spend, feed grid, + every chip question) |
| **Typography** | `.systemSerif` light, all lines | Chat sans for dialogue, serif for the weighty lines (`.bubble.serif`) |

### Beat mapping

Every v7 slide has a home in v8. Nothing in the narrative is lost except the two rows marked **DROPPED** (see [§8](#8-what-v8-drops-from-v7)).

| v7 slide | Fate in v8 | v8 location |
|---|---|---|
| 0 — Recognition | **Rewritten as dialogue** — founder introduces himself by name first, then tells the loop story | Act 1, beats 1–2 |
| — | **NEW** — phone-hours question + stakes card (years computed from the answer) | Act 1, beats 3–5 |
| 1 — The Turn (NOWHERE → NOW HERE) | **Kept** — same split animation, now inside a bubble | Act 1, beat 8 |
| 2 — Canvas concept | **Kept** — copy compressed to one serif bubble | Act 2, beat 1 |
| 3 — Color cap (5 orbs → 100) | **Kept verbatim** — ring card, same +20 mechanic | Act 2, beat 3 |
| 4 — Spend demo (3 tariffs) | **Kept verbatim** — same 4/10/20 costs | Act 2, beat 5 |
| 5 — The Economy | **Kept** — compressed from 3 lines + icon animation to one serif bubble | Act 2, beat 6 |
| 6 — Steps target (slider) | **Replaced** — 4-chip question infers the target | Act 3, beats 1–2 |
| 7 — Sleep target (slider) | **Replaced** — 4-chip question infers the target | Act 3, beats 3–4 |
| 8 — HealthKit permission | **Kept + primed** — priming card before the system dialog | Act 3, beats 5–7 |
| 9 — Feed selection | **Split** — feed grid stays; notifications become their own explicit question | Act 3, beats 8–10 |
| — | **NEW** — notifications asked explicitly instead of bundled silently | Act 3, beats 11–13 |
| 10 — Identity (Apple Sign In) | **Kept** — same late placement, same skip | Act 3, beats 14–15 |
| 11 — Make It Yours (wallpaper/widgets) | **DROPPED** — must be re-homed | — |
| 12 — Welcome | **Kept** | Act 4 |

### Progress model

v7 fills a 12-segment bar, one segment per slide. v8 has no slide index to key off, so progress is set explicitly at 10 checkpoints:

| Checkpoint | `p` | Dots lit | Meaning |
|---|---|---|---|
| Start | 0.00 | 0 | — |
| After phone-hours answer | 0.08 | 0 | stakes named |
| After "Show me" | 0.30 | 2 | Act 1 done |
| After "I'm in" | 0.50 | 3 | Act 2 done |
| After movement answer | 0.62 | 3 | steps set |
| After sleep answer | 0.72 | 4 | sleep set |
| After Health | 0.80 | 4 | canvas can fill |
| After feed pick | 0.88 | 4 | first block set |
| After notifications | 0.94 | 5 | — |
| After identity | 1.00 | 5 | Act 3 done |

Background warmth is derived: `--warm = 0.10 + p × 0.5`. The screen literally warms from night (`#002646`) toward sunrise (`#E8974E`) as the user progresses — the same `EnergyGradientRenderer` idea as v7, driven by one scalar instead of a slide index.

---

## 3. Act-by-act specification

Copy below is **verbatim from the prototype** so review has something concrete to argue with. It is not tone-approved — see [§7](#7-copy-audit-against-tone_of_voice).

### Act 1 — WHY IT MATTERS

**Goal:** the user arrives at their own number and feels it.
**Progress:** 0 → 0.30

| # | Type | Content |
|---|---|---|
| 1 | bot | "Hey — I'm Kosta. I made Nowhere." |
| 2 | bot, serif | "I was living the same day on repeat — wake, work, scroll, sleep. I stopped being able to tell them apart. And the thing quietly eating them was right here in my hand." |
| 3 | bot | "So — honestly. How many hours a day is your phone for you?" |
| 4 | **question** | chips: `2–3` · `4–5` · `6+` · `Don't make me count 😳` (ghost) |
| 5 | bot, conditional | if "count": "Ha, fair. I'll guess around 5. 🙂" |
| 6 | **stakes card** | counts `~0` → `~N` years, label "years · awake, but not there" |
| 7 | bot, serif | "That's not time you'll feel pass. You're awake for it — just not really there." |
| 8 | bot | "I'm not saying it to shame you. I did the exact same — that's how I even noticed." |
| 9 | bot | "I felt stuck in" |
| 10 | **reveal** | `NOWHERE` → `NOW | HERE` split, gold accent bleeding into the 16px gap |
| 11 | bot, serif | "I can't give those years back. But the ones ahead? You can actually be there for them — notice them, keep them. That's the whole reason this exists." |
| 12 | bot | "Want to see how?" |
| 13 | **question** | chip: `Show me` (solid) |

#### The stakes card

The one genuinely new emotional beat. The user's phone-hours answer maps to a projected lifetime figure:

| Answer | Years shown |
|---|---|
| 2–3 | ~5 |
| 4–5 | ~9 |
| 6+ | ~13 |
| Don't make me count | ~9 (founder guesses 5h aloud first) |

The number counts up at 70ms per year, so 13 years takes ~0.9s of visible climb. Bar underneath fades coral → navy.

> **Unresolved:** these four constants are asserted, not derived. Before this ships, either (a) show the arithmetic in the copy ("5h/day × 50 years ≈ 9 years awake"), or (b) soften to a non-numeric claim. Shipping an unsourced "~13 years" as the emotional centrepiece of onboarding is a credibility risk with exactly the audience most likely to check. See [§11](#11-risks--open-questions).

#### The reveal

Same beat as v7 slide 1, preserved: `NOWHERE` renders as one word, holds 900ms, then a 16px gap opens and `HERE` shifts to gold. In v7 this carries `.heavy` haptic on split and `.success` on the closing line — keep both.

Note the copy order changed. v7: "it felt like being stuck in" → reveal → "so i made this app." v8 moves "I made Nowhere" to beat 1 and replaces the closer with the "years ahead" line. The reveal is no longer the founder's origin beat; it's the pivot from the user's loss to their agency. **This is the right change** — it puts the turn after the user's own number, not after the founder's.

---

### Act 2 — HOW IT WORKS

**Goal:** the aha moment. Unchanged from v7 in substance.
**Progress:** 0.30 → 0.50

| # | Type | Content |
|---|---|---|
| 1 | bot, serif | "Every day becomes a canvas. Your steps and sleep paint the background — the small things you notice add the color." |
| 2 | bot | "A full, lived day is 100 colors. Tap each source 👇" |
| 3 | **ring card** | 5 orbs (steps/sleep/body/mind/heart), +20 each, ring fills to 100 |
| 4 | bot, small | "The canvas is proof you were here today. That's the point — a day you'll actually remember." |
| 5 | bot | "But the apps that pull you away? Opening them spends those colors. Try it 👇" |
| 6 | **spend card** | pool 100, Instagram locked, tariffs 10min/4 · 30min/10 · 1h/20 |
| 7 | bot, serif | "That's Nowhere. Earn color by living, spend it to scroll, and every morning you start clean." |
| 8 | **question** | chips: `I'm in` (solid) · `Ok, set me up` (ghost) |

Both interactive cards are ports of the v7 slides, including the haptic map (`.light` per orb, `.success` at 100, `.medium` on tariff select). The aha lands at ~beat 6 of Act 2 — roughly 60–75s in, versus ~35s in v7. **This is the single biggest regression in v8** and the thing review should push hardest on ([§11](#11-risks--open-questions)).

Act 2 compresses v7's slide 5 (three lines + a 2s earn→spend→reset icon animation) into one serif bubble. The animation is worth keeping in some form — a small inline three-icon strip inside the bubble would cost nothing.

---

### Act 3 — TUNE IT TO YOU

**Goal:** configuration, disguised as conversation.
**Progress:** 0.50 → 1.00

| # | Type | Content |
|---|---|---|
| 1 | bot | "Let's make it yours. On a normal day, how much do you move?" |
| 2 | **question** | `Barely 🛋️` · `Average` · `Pretty active` · `No clue 🤷` (ghost) → sets steps target |
| 3 | bot | "And sleep — what's a good night for you?" |
| 4 | **question** | `6h` · `7h` · `8h` · `What is sleep 🥲` (ghost) → sets sleep target |
| 5 | bot | "To make the canvas real, I read your steps & sleep from Apple Health. It never leaves your phone." |
| 6 | **priming card** | 🍎 "Apple Health — permission" / "The next screen is Apple's. Flip everything on so the canvas can breathe." |
| 7 | **question** | `Connect Health` (solid) · `Later` (ghost) → fires HealthKit |
| 8 | bot, serif | "Now — where does your day usually disappear? Pick one app to close." |
| 9 | **priming card** | 🛡️ "Screen Time — Allow" / "iOS asks to allow Screen Time next. That's what lets me hold the door on an app. Tap Continue → Allow." |
| 10 | **feed grid** | 8 apps, single-select → CTA "Close {App}" · ghost skip "Not now" |
| 11 | bot | "Want a nudge when you've earned enough color to spend?" |
| 12 | **priming card** | 🔔 "Notifications — Allow" / "Just one screen from iOS. Tap Allow so I can tell you when a feed's ready." |
| 13 | **question** | `Yes, nudge me` (solid) · `No thanks` (ghost) |
| 14 | bot | "Last thing — keep your canvas across devices, or stay anonymous for now?" |
| 15 | **question** | ` Sign in with Apple` (solid) · `Stay anonymous` (ghost) |

Ordering matches v7 exactly (targets → Health → feeds → identity), with one deliberate change: **notifications get their own question.** In v7, tapping "Next" past the feed slide with a selection silently fired `requestNotificationPermission()`. The user never agreed to be notified; they agreed to block Instagram. v8 asks. Expect a lower opt-in rate and a better one.

The three priming cards are dashed-border placeholders in the prototype. They need real screenshots of the actual iOS dialogs before this ships ([§6](#6-permission-priming)).

---

### Act 4 — WELCOME

**Progress:** 1.00

| # | Type | Content |
|---|---|---|
| 1 | bot, serif | "That's it. Welcome to Nowhere." |
| 2 | bot, serif | "You're here. Let's make today one you'll remember." |
| 3 | **action** | full-width primary: `Let's go →` → `finishOnboarding()` |

v7's welcome slide personalizes with the signed-in display name ("[Name]" / "you're here."). v8 drops the name. It shouldn't — if the user just signed in two beats ago, using their name here is the cheapest possible payoff.

---

## 4. Component spec

Nine components carry the whole flow. This is the actual deliverable of the restructure: v7 needs bespoke view code per slide type, v8 needs these nine plus a beat script.

### 4.1 Bubble

| Variant | Style |
|---|---|
| **bot** | `rgba(255,255,255,.10)`, 1px stroke `rgba(255,255,255,.12)`, radius 20 / 7 bottom-left, `#F4F1EA`, blur(8px) backdrop |
| **user** | gold gradient `#FFD369 → #FFBF65`, `#1b1b1b` text, weight 500, radius 20 / 7 bottom-right |
| **serif** | bot bubble, serif face, for the weighty narrative lines |
| **small** | no background, 12.5px, italic, `rgba(255,255,255,.6)` — asides and confirmations |

Max width 82%. Entry animation: `translateY(8px) scale(.98) → none`, 320ms `cubic-bezier(.2,.8,.2,1)`.

### 4.2 Typing indicator

Three dots, 1.2s blink loop with 0.2s stagger. Shown before every bot bubble, then replaced.

Delay formula: `min(1600, 600 + textLength × 15)` ms, then 280ms settle.

This is where v8's runtime goes — ~26 bot bubbles × ~1.2s ≈ **31 seconds of pure typing animation** before the user reads a word or taps anything. Tunable, and it must be tuned ([§11](#11-risks--open-questions)).

### 4.3 Dock

Bottom bar, right-aligned wrapped chips, min-height 64px. Chip kinds:

| Kind | Style | Use |
|---|---|---|
| default | gold outline + 10% gold fill | ordinary reply |
| `solid` | gold gradient fill, dark text | the intended path |
| `ghost` | white 55% text, neutral stroke | skip / deflection |
| `btn-primary` | full-width gold | commit actions (Connect Health, Let's go) |

Tapping a chip clears the dock, echoes the chosen label as a user bubble, and resolves the beat. A chip may set `reply: null` to act without echoing.

### 4.4–4.9 Cards

All cards mount as a bot-side bubble (`.card`: `rgba(0,0,0,.28)`, radius 20, blur(10px), max-width 86%) and resolve their beat when their interaction completes.

| Card | Resolves when | Ported from |
|---|---|---|
| **stakes** | after count-up finishes (auto, ~N×70ms + 700ms) | new |
| **ring** | all 5 orbs tapped (+650ms) | v7 slide 3 |
| **spend** | any tariff tapped (+900ms) | v7 slide 4 |
| **feed grid** | "Close {App}" tapped, or "Not now" | v7 slide 9 |
| **priming** | non-interactive, 500ms in / 400ms hold | new |
| **reveal** | 900ms hold + 1000ms split | v7 slide 1 |

---

## 5. Personalization — chips replace sliders

Sliders are replaced by questions about the user's life. The mapping:

### Steps

| Chip | Target | Founder's reply |
|---|---|---|
| Barely 🛋️ | 5,000 | "Got it — starting gentle at 5k. Every step still colors the canvas." |
| Average | 8,000 | "Nice, 8k it is. A solid daily canvas." |
| Pretty active | 10,000 | "Love it — 10k. Your canvas is going to glow. ✨" |
| No clue 🤷 | 8,000 | "All good, I'll set 8k — a normal-ish day. Change it anytime. 🙂" |

### Sleep

| Chip | Target | Founder's reply |
|---|---|---|
| 6h | 6.0 | "Noted. I'll quietly root for a little more." |
| 7h | 7.0 | "7 it is. The dark behind your canvas gets a bit deeper." |
| 8h | 8.0 | "8 — the dream. Literally. 🌙" |
| What is sleep 🥲 | 7.0 | "Oof, I feel that. 😌 I'll set 7 — and we'll work on it together." |

**Trade-off, stated plainly.** v7's slider spans 5,000–15,000 in steps of 500 (21 values). v8 offers three. A user who wants 12,000 cannot express it during onboarding.

That's acceptable **only** because both targets are freely editable in Settings → Limits, and because a number chosen from a menu of three honest descriptions beats a number reached by not touching a slider. The founder's reply explicitly says so ("Change it anytime"). Every reply must keep that escape hatch — it's what makes the coarse mapping fair rather than presumptuous.

Storage is unchanged: `SharedKeys.userStepsTarget`, `SharedKeys.userSleepTarget`.

---

## 6. Permission priming

Three iOS dialogs (HealthKit, Family Controls, Notifications) are now preceded by a priming card that names the dialog, says it's Apple's and not ours, and tells the user which button to press.

| Permission | Card copy | Fires on |
|---|---|---|
| HealthKit | "The next screen is Apple's. Flip everything on so the canvas can breathe." | `Connect Health` chip |
| Family Controls | "iOS asks to allow Screen Time next. That's what lets me hold the door on an app. Tap Continue → Allow." | first app-icon tap in the feed grid |
| Notifications | "Just one screen from iOS. Tap Allow so I can tell you when a feed's ready." | `Yes, nudge me` chip |

Two rules carried over from v7 and non-negotiable:

- **Each permission fires at most once.** v7 guards this with flags (`didTriggerHealthRequest`); the beat script needs the same.
- **Nothing blocks progress.** Denial advances the flow. No guilt copy, no retry loop. The post-onboarding fallbacks in v7 §4.1 (Canvas banner for Health, Feeds empty state) stay as-is.

**Open:** the prototype uses dashed placeholder boxes with emoji. Shipping these needs real cropped screenshots of each iOS dialog, and they'll need re-shooting each iOS version. An illustrated approximation may age better than a screenshot — decide before implementation.

---

## 7. Copy audit against TONE_OF_VOICE

Worth checking carefully, because the naive read ("chat copy breaks our voice rules") is wrong in an interesting way.

### The format is endorsed by the doc

[`docs/marketing/TONE_OF_VOICE.md`](docs/marketing/TONE_OF_VOICE.md), under *Tone by surface → Onboarding*:

> The most personal, narrative voice. First person. Reflective. **Asks questions.**

Its three illustrative examples are conversational turns, one of which is an explicit question with the user's answer implied:

> "Walking adds bright color. I need about 7k steps to feel nice. How about you?"
> "By the way, I'm Konstantin. Who are you?"

That is a chat beat. The doc has been describing v8 all along — **v7 is the surface that under-delivers here**, because it asks "how about you?" and then hands over a slider. So the restructure isn't a deviation from the voice; it's the first format that can actually execute the *"asks questions"* instruction. Note also that the doc's own onboarding examples are Sentence case, not the all-lowercase v7 shipped: rule 1 scopes lowercase to *"UI labels and short phrases"*, not narrative sentences.

### What genuinely does violate the doc

The problem is narrower than "chat register" — it's specific lines, on three named rules:

| Rule | Prototype violation |
|---|---|
| **Writing rule 3 — No exclamation marks** (a global, named rule) | Several bot replies |
| **Core personality — "Warm but never cheery"**, "No forced optimism", cited counter-example "Great job! You're amazing!" | `"Love it — 10k. Your canvas is going to glow. ✨"` · `"8 — the dream. Literally. 🌙"` |
| **Anti-patterns — no celebration language** | Same two lines, plus `"Done. I'll only ping you when it's worth it. 🤙"` |

The emoji are a symptom, not the offence. **There is no global no-emoji rule** — "No emoji" appears only under *Tone by surface → Notifications*, scoped to that surface. So emoji in onboarding is an open question the doc simply doesn't answer, while cheeriness is closed: banned outright.

The distinction matters for the fix. `😳` on the user-side chip "Don't make me count" is the user being wry about themselves — that's the user's voice, and it's fine. `✨` on the founder congratulating you for picking 10k is Nowhere celebrating a goal, which the doc bans in three separate places.

### Recommendation

**Keep the conversational register; strip the cheer.**

1. Remove every exclamation mark (rule 3, non-negotiable)
2. Rewrite the four celebratory replies to be warm-by-honesty, not warm-by-punctuation. `"Love it — 10k. Your canvas is going to glow. ✨"` → `"10k. that's a full canvas most days."`
3. Emoji: allowed on user-side chips, none from the founder. Write this scope into TONE_OF_VOICE so it's a decision, not an oversight
4. Keep Sentence case in dialogue; keep the serif beats (reveal, economy line, welcome) in v7's sparser register

Sequencing matters: the emoji scope and the Sentence-case-in-dialogue allowance go into TONE_OF_VOICE **before** the ~34 beats get written, or the copy drifts to whatever the last person typed.

### Also: the founder's name

The tone doc says "I'm Konstantin." v7 ships "i'm kosta." The prototype says "I'm Kosta." Three spellings of the same person across three artifacts — pick one and fix the other two.

---

## 8. What v8 drops from v7

Four things present in the shipped flow are missing from the prototype. Three are regressions to fix; one is a fair cut.

| Dropped | v7 location | Verdict |
|---|---|---|
| **Wallpaper + widget teaser** — "set your canvas as a wallpaper." / "add widgets — they update on their own." / "if they feel behind, tap refresh. ios thing." | Slide 11 | **Re-home it.** v7 added this slide precisely because users found wallpaper export days later or never. Dropping it re-opens a known problem. Suggest: one bot bubble in Act 4, before "Let's go". |
| **Sleep iOS-lag microcopy** — "sleep data may lag a bit — ios updates it on its own schedule." | Slide 7 | **Restore it.** This exists to prevent a "the app is broken" perception. It costs one `small` bubble after the sleep answer. |
| **"the clock runs only when the screen is on."** | Slide 4 | **Restore it.** This is a factual term of the deal. Omitting it from the spend demo means the first ticket behaves in a way the user wasn't told about. |
| **Personalized name in welcome** | Slide 12 | **Restore it.** Free payoff two beats after sign-in. |
| **Back navigation** (swipe right >60pt) | All slides | **Fair cut** — a chat transcript has no natural "un-say." But a user who fat-fingers `6+` on the phone-hours question has no way back, and that answer drives the stakes card. Minimum: let the last answer be re-tapped, or add a "wait, change that" affordance on the beats that set configuration (phone hours, steps, sleep). |

---

## 9. Analytics

v7's per-slide events don't map to a transcript. Proposed v8 schema, keeping the same spirit (one view event, one completion event, one terminal event):

```
onboarding_beat_viewed
  { beat_id, act, flow_version: "v8" }

onboarding_beat_answered
  { beat_id, act, flow_version: "v8", duration_ms, answer }

onboarding_completed
  { flow: "v8", phone_hours_bucket, projected_years, steps_target, sleep_target,
    selected_feed, selected_apps_count, signed_in, notifications_opted_in,
    skipped_feed_selection, total_duration_ms }
  dedupeKey: "onboarding_completed_v1"
```

`beat_id` must be a stable string (`act1_phone_hours`, `act2_ring`, `act3_sleep`), never an index — beats will be inserted and reordered, and an index-keyed funnel silently rewrites its own history when that happens.

Three new properties worth having: `phone_hours_bucket` and `projected_years` (does the stakes card correlate with completion?), and `notifications_opted_in` (now a real signal, since v8 asks instead of assuming).

**Keep the `dedupeKey` unchanged.** A user who completed v7 must not re-fire completion if they replay under v8.

### What the funnel should answer

1. Does the stakes card increase or decrease Act 1 → Act 2 progression versus v7's slide 0 → 2?
2. Where does the extra ~90s cost users? Expect the drop between Act 1 and the ring card.
3. Does explicit notification consent produce better D7 notification engagement despite a lower opt-in rate?

---

## 10. Accessibility & localization impact

Both get materially harder. Costs, not blockers.

**Localization volume roughly doubles.** v7's slide script is **26** localized strings (`String(localized:)` in `OnboardingModels.swift`), plus ~39 more for view chrome in `OnboardingStoriesView.swift`. v8 has ~34 beats, several with conditional variants (4 steps replies, 4 sleep replies, 2 feed replies, 2 notification replies, 2 identity replies, 1 phone-hours aside) — call it **~60 script strings**, all in `Localizable.xcstrings`. Emoji-in-chips (§7) may not translate: 🛋️ as shorthand for "sedentary" is not universal.

**VoiceOver.** A transcript that grows while the user is in it is a genuine accessibility problem: each arriving bubble should post an announcement, and the dock must not steal focus mid-read. The typing indicator should be `accessibilityHidden`. v7's one-screen-at-a-time model was accidentally accessible; v8 has to earn it.

**Reduce Motion.** The typing delays, bubble entry springs, count-up, and reveal split all need a static path. Under Reduce Motion the honest behaviour is: no typing indicator, no count-up (show the final number), reveal renders pre-split. That also makes the flow much faster, which some users will prefer regardless — consider exposing it.

**Dynamic Type.** 82%-max-width bubbles with 15px text will break at accessibility sizes. Bubbles must grow and wrap; the 4×2 feed grid needs a 2-column fallback.

---

## 11. Risks & open questions

Ranked by how much they should worry us.

### 1. Runtime: 150–210s vs v7's 60–80s

The prototype is **2–3× longer** than the flow it replaces. ~31s of that is typing animation the user cannot skip. Onboarding length correlates with abandonment more reliably than almost anything else we could measure, and this doubles it.

Mitigations, in order of preference:
- Cut Act 1 from 13 beats to ~8. The founder repeats himself: beats 7, 8 and 11 all make the same "I'm not shaming you, I did it too" point.
- Halve the typing formula (`300 + len × 8`, cap 900ms) — saves ~15s and still reads as typing.
- Let a tap skip the current typing indicator. Chat users already expect this.
- Consider whether Act 1 needs to precede the aha at all, or whether the ring card could come first and the stakes card second.

### 2. The aha moment moves from ~35s to ~60–75s

v7 deliberately front-loaded it (v6 → v7 kept it at ~slide 4 for this reason). v8 pushes it behind a full act of narrative. This is a direct regression against a documented design goal. Either shorten Act 1 or move the ring card earlier.

### 3. The years constants are unsourced

`2–3h → ~5 years`, `6+ → ~13 years`. Presented as the emotional centrepiece with a `~` and no arithmetic. See Act 1. Show the math or soften the claim.

### 4. Cheeriness, and two undocumented voice scopes

Narrower than it first looks — the chat format is what TONE_OF_VOICE asks for, and there is no global no-emoji rule. But four replies break the "warm but never cheery" rule and the celebration-language anti-pattern outright, exclamation marks break a named rule, and two questions (emoji scope in onboarding, Sentence case in dialogue) the doc simply doesn't answer. All of it resolvable in [§7](#7-copy-audit-against-tone_of_voice) — and it has to land in TONE_OF_VOICE.md before the beats get written.

### 5. No back navigation

Answers drive both copy and configuration; there's no undo. See [§8](#8-what-v8-drops-from-v7).

### 6. Replay from Settings is unspecified

v7 handles replay explicitly: permission beats detect existing grants and show "already connected", targets pre-fill, feed selection pre-fills. In a transcript, what does a replay look like — does the founder re-tell the whole story to someone who has used the app for a month? Probably not. Needs its own short path, or an explicit decision that replay re-runs verbatim.

### 7. Interruption / backgrounding

A 3-minute flow will get backgrounded mid-way. v7's slide index made resume trivial. v8 needs to decide: persist the transcript and resume in place, or restart the act. Unspecified in the prototype.

### 8. Single-select feed grid

Prototype allows exactly one app. v7's `FamilyActivitySelection` picker allows several. Confirm the narrowing is intentional ("pick one app to close" is a fine onboarding simplification) and that the multi-select path is still reachable from the Feeds tab.

---

## 12. Implementation plan

Deliberately staged so the expensive parts come after the cheap decisions.

### Phase 0 — Decisions (no code)

Blocks everything else:

1. Voice — confirm [§7](#7-copy-audit-against-tone_of_voice): cut the cheer, and write the two missing scopes (emoji in onboarding, Sentence case in dialogue) into TONE_OF_VOICE.md
2. Founder's name — Konstantin / kosta / Kosta; pick one, fix the other two artifacts
3. Runtime budget — agree a target (suggest ≤120s) and cut Act 1 to fit
4. Years constants — show the math or soften
5. Re-home the four dropped items from [§8](#8-what-v8-drops-from-v7)
6. Replay and resume behaviour

### Phase 1 — Beat engine

`StepsTrader/Views/Onboarding/Chat/`:

| File | Responsibility |
|---|---|
| `OnboardingBeat.swift` | beat model — bot / question / card / action; stable `beat_id` |
| `OnboardingScript.swift` | the transcript as data, one array, all copy localized |
| `OnboardingChatView.swift` | scrolling transcript, auto-scroll, VoiceOver announcements |
| `ChatBubble.swift` | four variants from [§4.1](#41-bubble) |
| `TypingIndicator.swift` | Reduce Motion aware |
| `ChatDock.swift` | chip kinds, dock lifecycle |

The script must be pure data. The moment copy lives inside view code, we've rebuilt v7's maintenance problem in a new shape.

### Phase 2 — Cards

Port the three v7 interactive slides first (`ring`, `spend`, `feed grid`) — the mechanics and haptics already exist in `OnboardingStoriesView.swift` and only need re-hosting inside a bubble. Then the new ones (`stakes`, `priming`, `reveal`).

### Phase 3 — Wiring

Reuse v7's plumbing wholesale; none of it should change:
- `SharedKeys.userStepsTarget` / `userSleepTarget`
- `model.ensureHealthAuthorizationAndRefresh()`, `familyControlsService.requestAuthorization()`, `model.requestNotificationPermission()` — each once, none blocking
- `AppleSignInCoordinator`
- `finishOnboarding()` — ticket group creation via `TargetResolver.displayName`, energy recalc, `hasCompletedOnboarding_v1`

### Phase 4 — Analytics, a11y, localization

Schema from [§9](#9-analytics), then the [§10](#10-accessibility--localization-impact) work: VoiceOver, Reduce Motion, Dynamic Type, ~60 strings.

### Phase 5 — Validation before replacing v7

v8 is 2–3× longer than a flow that already works. It does not replace v7 on taste.

- Keep v7 behind a flag; ship v8 to a slice
- Compare: completion rate, time-to-aha, activation (Health granted + target set + onboarding done), feed-selected rate, D7
- v8 replaces v7 only if completion holds and activation improves

`Steps4Tests/OnboardingFlowTests.swift` covers the v7 slide array; it needs a v8 equivalent asserting script integrity (every question reachable, every permission fires once, every beat_id unique).

---

## Appendix — v7 vs v8 at a glance

| | v7 (shipped) | v8 (proposed) |
|---|---|---|
| Structure | 13 slides | 4 acts, ~34 beats |
| Runtime | 60–80s | 150–210s ⚠️ |
| Aha at | ~35s | ~60–75s ⚠️ |
| User verbs | Next, swipe back | 8 questions, 4 interactive cards |
| Targets set by | 2 sliders | 2 chip questions |
| Permission priming | none | 3 cards |
| Notification consent | implicit | explicit |
| Back navigation | swipe | none ⚠️ |
| Localized script strings | 26 | ~60 |
| Voice | strict, but never "asks questions" | matches doc's onboarding brief; cheer must be cut |
| Analytics | `flow_version: v7`, slide-indexed | `flow_version: v8`, beat-keyed |

---

*Review target: agree Phase 0 decisions. Nothing in Phase 1+ should start before then.*
