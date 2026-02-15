# Proof / Daylight / Vigil – Strategic Blueprint (Semi-Finished Project)

> This document is the output of a six-agent collaborative session. The agents worked sequentially — each building on and challenging the previous — but operated as a single creative team: sharing instincts, arguing, borrowing metaphors from each other, and converging on one unified vision.

---

## 1. Executive Summary

**What we found**: A SwiftUI iOS app at ~70% completion with a working core loop, a genuinely distinctive design system, and a deep (if scattered) philosophical instinct. The app already knows what it wants to be — a **daily gallery of lived experience** where real life earns the right to digital access. But the language, the naming, and the conceptual framing haven't caught up with what the product already *feels like* when you use it.

**The central insight** (from the team): This is not a screen-time blocker. This is not a step counter. This is an app that asks: *Did you live today? Show me.* And only then opens the door to your phone. The gallery of polaroid cards with hand-scribbled crosses isn't a feature — it's the **soul** of the product. Everything else (steps, sleep, tickets, PayGate) serves that gallery.

**What needs to change**: The name, the vocabulary, and the philosophical framing need to match the product's own instinct — which is already art, not engineering.

**Top 3 app name recommendations**: **Proof**, **Daylight**, **Vigil**

---

## 2. Current State Analysis (Product Agent)

### What exists and works

The mechanical layer is surprisingly complete:
- Daily energy built from **multiple real-life sources**: HealthKit steps, sleep hours, and daily choices across three rooms (body, mind, heart) — capped at 100.
- **Ticket groups** (app bundles) with FamilyControls selection, difficulty levels 1–5, and three access windows (10/30/60 min).
- **PayGate** flow wired end-to-end: deduct experience → write unlock expiry → rebuild ManagedSettings shield → extensions handle expiry even in background.
- **Three extensions** (DeviceActivityMonitor, ShieldAction, ShieldConfiguration) — the hardest iOS engineering in the product, production-grade.
- **Gallery tab** with polaroid-card UI: hand-drawn frames (`frame-1` through `frame-4`), scribbled completion crosses (`cross1` through `cross3`), confirm-to-select, category edit sheets, custom activities.
- **Me tab** with profile, 60-day memory calendar, day-detail sheets.
- **Design system**: 4 themes (Daylight / Night / Minimal / System), 570-line `design.json`, component library. The "printed experience ledger + rebellious marker accents" creative direction is *already* the right aesthetic for this product.
- **Supabase sync** for daily selections, stats, spent, custom activities (with debounce/dedup). Ticket group sync has TODOs.
- **Localization** was EN/RU via inline `loc()` calls — **v1 ships English-only.** All `loc()` wrappers and Russian string branches to be stripped.
- **Tests** covering BudgetEngine, CustomActivity, DailyEnergy, DayBoundary, MinuteCharge.

### What's strong

1. **The gallery is the product** — and nobody else in the screen-time space has anything like it. Polaroid cards with hand-drawn frames and scribbled crosses are emotionally loaded in a way that a progress bar never will be. This is rare.
2. **The three rooms** (body, mind, heart) cover the full spectrum of real life — not just fitness. Dancing it out, following your curiosity, holding someone close, breaking your rules, kissing someone. This is *living*, not *exercising*.
3. **The design system** is coherent and has genuine taste. Anti-gamification, paper-and-ink, yellow marker accents — this signals intentionality.
4. **The Screen Time integration** is a genuine technical moat. FamilyControls + DeviceActivity + ManagedSettings + 3 extensions is months of work that competitors can't shortcut.

### What's weak

| Weakness | What it means |
|----------|---------------|
| **Identity crisis** | The app is called "DOOM CTRL" but feels like a quiet art journal. The name promises aggression; the product delivers contemplation. |
| **Vocabulary scatter** | "Control," "experience," "energy," "balance," "tickets," "shields," "steps" — six words for overlapping concepts. Users encounter a different term every screen. |
| **Steps tunnel-vision** | The balance card says "EXP" and shows step-derived numbers. But the *real* sources of experience are the gallery choices — dancing, museum, curiosity, kissing. Steps are the baseline, not the story. |
| **No post-spend feedback** | After the PayGate, silence. No "you traded 10 experience for 30 min of Instagram." No weekly reflection. No mirror held up to the trade-off. |
| **Gallery underexplored** | The gallery IS the philosophical core, but it's treated as "tab 2." It should be the frame through which everything is understood. |
| **AppModel / Store duplication** | BlockingStore owns ticket groups, AppModel re-exposes everything. Logic drift risk. |
| **UserDefaults key sprawl** | 50+ raw string keys across app + 3 extensions with no shared schema. |
| **Empty Guides tab** | ManualsPage is literally an empty VStack. A missed opportunity — this should be where the philosophy lives. |
| **README contradicts code** | Says "ManagedSettings shield blocking was removed" — it was not. |

---

## 3. Product Direction (Product Agent)

### Refined problem statement

People don't fail at managing screen time because they lack tools. They fail because **restriction without meaning is just punishment**. Every blocker on the market asks "how much do you want to limit?" instead of asking "what did you do today that earns the right to scroll?"

This app inverts the question. It doesn't start with the screen — it starts with life. **Did you walk? Did you sleep? Did you choose curiosity over comfort? Did you hug someone?** Those choices, accumulated, become your daily experience. And experience is what you spend when you want into your apps.

The opportunity: **Be the first app that treats screen time as a consequence of how fully you lived — not a target to restrict.**

### What to keep, what to reframe, what to add

| Decision | Item | Rationale |
|----------|------|-----------|
| **Keep (core)** | Gallery with polaroid cards + crosses | This is the soul. Elevate it from "tab 2" to the conceptual center. |
| **Keep (core)** | Three rooms: body, mind, heart | These cover the full human experience — not just fitness. Body = how you moved. Mind = how you thought and created. Heart = how you felt and connected. This is the differentiator. |
| **Keep (core)** | TicketGroup → PayGate → unlock flow | The mechanical exchange. Works. Ship it. |
| **Keep (core)** | Design system (paper/ink/marker) | Already exactly right. Don't touch. |
| **Keep** | Me tab + history | Self-reflection. The "archive" of past exhibitions. |
| **Keep** | Custom activities | Personalization = ownership. |
| **Reframe** | Balance card | De-emphasize step count. The number represents ALL of life — steps, sleep, AND choices. The label should be "experience," not "EXP." The breakdown chips should read **body / mind / heart** — three rooms of a gallery, not three fitness metrics. |
| **Reframe** | Onboarding | Start with the gallery concept: "Your life is an exhibition. Each day, you choose what goes in." Then permissions, targets. Currently 13 slides — target 7. |
| **Reframe** | Guides tab (empty) | Make this the **philosophy** page. Short, beautiful texts about the ideas behind the app — including "On the three rooms" (body, mind, heart). Curated, not exhaustive. Like gallery wall text. |
| **Add** | Weekly reflection card | "This week, you lived 412 experience. You spent 180 on Instagram and YouTube. Your richest day was Wednesday." This is the mirror. |
| **Add** | Lock Screen widget | Show today's experience. Biggest retention driver available in iOS. |
| **Add** | "Rest day" override | Some days you can't walk. Grant a base 30 experience with no steps. "Some days the exhibition is quiet." |
| **Simplify** | Minute mode | Disable in v1 UI. The access-window model (10/30/60 min) covers 90% of use. Keep code, hide toggle. |
| **Remove** | Legacy per-app settings | Ticket groups supersede. Dead code. |
| **Fix** | SharedKeys.swift | Single enum for all UserDefaults keys, shared across app + extensions. |
| **Fix** | AppModel / BlockingStore boundary | Clear ownership. AppModel delegates, doesn't re-expose. |

### Updated MVP (4-week target)
- Simplified onboarding (7 slides, gallery-concept-first)
- Daily experience → Ticket group PayGate flow (access windows, no minute mode)
- Gallery + Me + Guides (with 3–5 philosophy texts) + Settings
- Weekly reflection card
- Lock Screen widget
- Ticket group Supabase sync
- Rest day override
- Privacy manifest + corrected README

---

## 4. Marketing Strategy (Marketing Agent)

### The real source of value: lived life, not steps

> *Marketing agent to Product*: "The moment we lead with 'steps,' we become Fitbit-for-screen-time. That's a feature, not a product. The real pitch is that this app cares about your WHOLE day — did you dance? did you create something? did you hug someone? Steps are the floor. Choices are the ceiling."

The market for screen-time apps is crowded with restriction tools (Opal, one sec, ScreenZen, Apple's own Screen Time). None of them ask "what did you live today?" They only ask "how much do you want to limit?"

**Positioning**: This is not a screen-time blocker. It's a **daily life exhibition that happens to control your apps.**

**One-line pitch**: *"Prove you lived today — then scroll."*

Alternative pitches to test:
- *"Your real life opens your phone."*
- *"Walk. Sleep. Choose. Then the screen unlocks."*
- *"Everything you do earns screen time. Not just steps."*

### Target audience

| Segment | Why they'll care | Where they are |
|---------|-----------------|----------------|
| **Intentional living** (25–35) | Already thinks about phone usage. Reads Cal Newport, follows digital minimalism accounts. Wants a system, not a blocker. | Reddit (r/digitalminimalism, r/nosurf), Substack, X |
| **Quantified self** (22–35) | Tracks everything. Wants screen time in the same dashboard as steps and sleep. | r/QuantifiedSelf, fitness Twitter, Strava communities |
| **Creative/philosophical** (20–30) | Attracted to the art/gallery metaphor. The polaroid cards, the paper aesthetic. Cares about *why*, not just *how*. | Design Twitter, Are.na, Tumblr revival, art school communities |

### Phased GTM

**Phase 1: Closed Beta (Weeks 1–6)**
- 50 TestFlight users from personal network + targeted Reddit posts
- Test two positioning angles:
  - A: "Your life earns screen time" (broad, all sources)
  - B: "Your day is an exhibition. Screen time is the admission price." (art/gallery angle)
- In-app feedback button + weekly 5-question survey
- Key metric: which angle drives higher D7 retention?

**Phase 2: Landing Page + Open Beta (Weeks 7–10)**
- Single-page site: hero screenshot of the gallery tab + "Prove you lived today"
- 3-step visual: Live → Exhibit → Unlock
- ProductHunt prep (Tuesday launch)
- 10 outreach emails to productivity/design newsletter creators

**Phase 3: Public Launch (Weeks 11–14)**
- App Store optimized for the chosen name
- Free with premium ($3.99/mo): unlimited tickets, weekly insights, widget customization
- Launch week: ProductHunt + Reddit + X + 2–3 podcast appearances

### Key experiments

| Experiment | Tests | Metric |
|-----------|-------|--------|
| Positioning A vs B (Reddit) | "Life earns screen time" vs "Your day is an exhibition" | Click-through → TestFlight signup |
| Onboarding: gallery-first vs permissions-first | Start with "your life is an exhibition" vs start with "allow HealthKit" | Onboarding completion rate |
| Free ticket limit (3 vs 5) | Where to place the premium paywall | Conversion rate at Month 2 |
| Widget impact | Users with widget enabled vs not | D7 retention delta |

---

## 5. Philosophical Direction (Philosopher Agent)

### The gallery as philosophical architecture

> *Philosopher to the team*: "You've built a gallery and called it a blocker. The gallery IS the idea. Let me show you why."

The app already contains a profound philosophical structure — it just hasn't been named. The three rooms (body, mind, heart) aren't random buckets. They map to how philosophy has understood the **good life** for 2,500 years:

| Room | Philosophical lineage | What it covers | Pieces (action phrases) |
|------|-----------------------|----------------|------------------------|
| **my body** | Aristotle's *energeia* — "being at work" — the highest human function is active engagement with the world. | The body in the world: moving, testing limits, taking risks. | dancing it out · eating a real meal · overcoming something hard · taking a real risk · making love · pushing my limits · feeling my strength |
| **my mind** | Hannah Arendt's *work* — the human capacity to create something that outlasts the moment. | The mind creating, observing, earning. | following my curiosity · making money happen · letting my mind wander · creating something new · noticing the invisible · visiting a real place · watching the world closely · earning what I deserve |
| **my heart** | Epicurus's *hedone* — not hedonism, but the cultivation of genuine pleasure as essential to life. | The heart feeling, connecting, rebelling. | embracing the cringe · holding someone close · feeling deeply today · being with my people · crying from joy · feeling in love · kissing someone · choosing myself today · going all out · breaking my rules · guilty pleasures |

Together, they form a complete picture: **body in motion + mind creating + heart feeling.** That's not a feature list. That's a philosophy of what it means to be alive.

> **Note on "my mind" pieces**: "Making money happen" (was *Cash doing*) and "Earning what I deserve" (was *Money*, moved from heart) overlap. Consider merging into a single piece — e.g., keep "making money happen" and drop the other. Flagged for your decision.

### Key philosophical references

**1. John Dewey — "Art as Experience" (1934)**
Dewey's central argument: art is not the object in the museum — it's the *experience* of the viewer. A painting hanging unseen has no art in it. Art happens when a human engages.

→ **Application**: Your daily gallery is art *because you lived it*. The polaroid card for "Dancing" isn't a card — it's proof that you danced. The scribbled cross isn't decoration — it's the artist's mark: *this one is real. This one happened.*

**2. Guy Debord — "The Society of the Spectacle" (1967)**
"All that was once directly lived has become mere representation." Debord described a world where authentic experience is replaced by images of experience. Social media is the purest spectacle ever built.

→ **Application**: This app inverts the spectacle. Before you can enter the world of representations (Instagram, TikTok, YouTube), you must prove you lived directly. The PayGate is a **threshold between the real and the spectacle.** You don't cross it for free.

**3. Walter Benjamin — "The Work of Art in the Age of Mechanical Reproduction" (1935)**
Benjamin argued that the original artwork has an "aura" — a sense of presence in time and space — that copies cannot reproduce. A print seen in a book is not the painting seen in the gallery.

→ **Application**: Your lived day has an aura. Your Instagram feed does not. The hand-drawn frames and scribbled crosses in the gallery are *deliberate imperfection* — they signal authenticity, not polish. They're closer to an artist's proof than a digital render.

**4. Japanese aesthetic: Wabi-sabi (侘寂) and Ichigo Ichie (一期一会)**
Wabi-sabi: beauty in imperfection, transience, and incompleteness. Ichigo ichie: "one time, one meeting" — this moment will never happen again.

→ **Application**: The paper-and-ink design system IS wabi-sabi. The scribbled crosses ARE ichigo ichie — you marked this choice today, and this particular day will never recur. The 60-day memory calendar in the Me tab is a scroll of unrepeatable exhibitions.

**5. Henri Bergson — "Creative Evolution" (1907)**
Bergson distinguished *durée* (lived time — qualitative, felt, irreducible) from *temps* (clock time — quantitative, measured, abstract). Steps and sleep hours are *temps*. But choosing "Curiosity" or "Embrace" or "Rebel" — those are *durée*. They can't be quantified. They can only be *acknowledged*.

→ **Application**: The daily selection cards are the app's mechanism for acknowledging durée. You can't measure how much you loved today. But you can mark that you did.

**6. Milan Kundera — "The Unbearable Lightness of Being" (1984)**
Kundera's tension: if every moment happens only once and is then gone forever, does anything matter? Or does its uniqueness make it infinitely heavy?

→ **Application**: The app resolves this tension. By making daily choices *matter* (they earn experience), it gives *weight* to moments that would otherwise evaporate. Your walk isn't "just a walk" — it's a piece in today's exhibition. It counts.

**7. Marcus Aurelius — Meditations**
"When you arise in the morning, think of what a privilege it is to be alive — to think, to enjoy, to love."

→ **Application**: This could literally be the Guides tab. Not as motivational-poster copy, but as gallery wall text: brief, factual, inviting contemplation. The Stoic idea that the morning itself is the gift — and the app asks: what did you do with it?

### The Guides tab as philosophical gallery wall text

The empty Guides tab is a missed opportunity. It should contain 5–7 short texts (200 words max each) — like the wall text in an art gallery. Not self-help. Not motivation. Observation.

**Example entries:**
1. *"On the spectacle"* — Why scrolling feels like doing something but isn't. (Debord)
2. *"On proof"* — What it means to prove you were alive today. (Benjamin + printmaking)
3. *"On imperfection"* — Why the scribbled cross is more beautiful than a checkmark. (Wabi-sabi)
4. *"On the three rooms"* — body, mind, heart: a complete life in three rooms. (Aristotle + Arendt + Epicurus)
5. *"On the threshold"* — What happens at the PayGate. The moment you decide. (Debord + Bergson)

---

## 6. Communication Strategy (Strategist Agent)

### The user insight

> *Strategist to the team*: "Every screen-time app says 'put down your phone.' Nobody says 'here's why you should.' The insight isn't 'less screen time is better.' The insight is: **you already have a life worth living — the app just helps you see it.**"

**Core insight**: People don't need to be told screens are bad. They already know. What they need is a way to make their real life *visible* — to see proof that they walked, created, felt joy — so that reaching for the phone feels like a conscious trade, not an unconscious reflex.

**The message is not**: "Block your apps." "Limit screen time." "Be disciplined."

**The message IS**: *"Your life is already full. Let's make sure you see it before you scroll."*

### The single distinguished idea

> *Strategist, after listening to the Philosopher*: "The gallery metaphor is everything. The app is a gallery of your day. Each card is a piece. The cross is your signature. And screen time? That's admission to a different gallery — the one you didn't make."

**THE IDEA**: Your life is a daily exhibition. You curate it with every choice. Screen time is what you trade to leave your own gallery and enter someone else's.

This is the one idea that unifies everything:
- **Earning** = adding pieces to your exhibition — body pieces, mind pieces, heart pieces
- **The number** = how rich your exhibition is today
- **The three rooms** = body (how you moved), mind (how you created), heart (how you felt)
- **Spending** = leaving your gallery for the screen
- **History** = your archive of past exhibitions
- **Tickets** = admission passes to specific digital spaces

---

## 7. Creative Direction (Creative Director Agent)

### The core metaphor: Proof

> *Creative Director, after hearing the Strategist and Philosopher*: "An artist's proof — épreuve d'artiste — is the print the artist keeps for themselves. It's not for sale. It's not for the gallery. It's the one that says: 'I made this. It's real.' That's what the daily gallery is. Each card the user marks is their own proof. Proof they lived."

**The metaphor**: Your day produces **proof**. Not data. Not points. Proof.

- Steps are proof you moved through the world.
- Sleep is proof you rested.
- Choosing "Curiosity" is proof you paid attention.
- Choosing "Embrace" is proof you loved.
- The scribbled cross on a card is your **artist's mark** — "this one is real."

**The PayGate reframe**: When you "spend experience," you're not paying a price — you're **trading proof of living for time in the spectacle**. The app makes this trade visible and conscious.

### Vocabulary: one language, one idea

| Concept | THE word | Why | NOT these words |
|---------|---------|-----|-----------------|
| What your life produces | **experience** | Both the number AND the philosophical concept. You have experience because you experienced things. | balance, energy, control, steps, points |
| What you do each day | **pieces** | Gallery language. Each choice is a piece in today's exhibition. | choices, selections, activities, options |
| The app groups | **tickets** | Admission tickets. You buy admission to digital spaces. Gallery/cinema language. | shields, groups, bundles |
| The exchange | **spend** | Clear, honest, no euphemism. You spend experience. | pay, deduct, use, consume, trade |
| The daily total | **today's exhibition** | What you've curated today. | daily energy, balance, daily control |
| History | **archive** | Museum term. Your personal archive. | memories, history, past days |
| The three categories | **rooms**: body, mind, heart | Three rooms of the gallery. Body = the body in the world. Mind = the mind creating. Heart = the heart feeling. Each room's pieces have short action-phrase names (e.g., "dancing it out," "following my curiosity," "holding someone close"). | categories, buckets, sections, move, create, feel |

### Name recommendations

> *Creative Director to the team*: "The name has to FEEL like the product. Not describe the mechanism. Not explain the feature. Feel like the experience of opening the app and seeing your day laid out in framed cards with scribbled crosses."

**Tier 1: Strongest recommendations**

| Name | Why it's right | Emotional register | Risks |
|------|---------------|-------------------|-------|
| **Proof** | An artist's proof. Proof of life. Proof you were here. Short (5 letters), sharp, ancient word, works in every language. "Proof" also means "tested" — you tested yourself today. The scribbled cross on a gallery card IS an artist's proof mark. | Quiet confidence. Not aggressive. Not cute. Matter-of-fact but deep. | "Proof" is used by some proofreading/identity apps. But "Proof — your daily exhibition" is distinctive. SEO: "proof app screen time" is clean. |
| **Daylight** | Already a theme name in the app. The opposite of screen-glow. "Daylight" = real world, visibility, warmth, paper-and-ink. "In the daylight, you lived. In the dark, you scroll." Also: "to bring to daylight" = to make visible, to reveal truth. | Warm, expansive, hopeful. Not aggressive. Feels like morning. | Slightly more generic than Proof. But emotionally warmer. "Daylight: your daily exhibition" works. Domain likely available (daylightapp.com). |
| **Vigil** | "To keep vigil" = to stay awake, to watch, to be present. Latin *vigilia* = wakefulness. A vigil is also an act of care — you keep vigil over something you love. You're keeping vigil over your own attention. | Serious, contemplative, protective. Like a guardian. Not aggressive — caring. | Less immediately descriptive. Requires brand-building. But rewards it: the name deepens with use. "Vigil: your daily exhibition." |

**Tier 2: Worth considering**

| Name | Why | Score |
|------|-----|-------|
| **Verve** | Spirit, energy, vivacity. French origin. "Your daily verve." Musical, alive. | Strong emotional register. Slightly less conceptual depth than Tier 1. |
| **Imprint** | What your day leaves on you. Also a printing term (imprint = publisher's mark). | Beautiful word but 7 letters. Slightly passive. |
| **Folio** | An artist's portfolio. A page. "Your daily folio." | Clean, art-connected, but some overlap with note-taking apps. |
| **Patina** | The beauty accumulated through living. Your life builds patina. | Gorgeous concept. But obscure for many users. Rewards the curious. |
| **Exposure** | Photography: the light that hits the film. Life: being exposed to the world. "Let life in." | Strong dual meaning. But negative associations (data exposure). |

**Top recommendation**: **Proof**. It is the word that unites the artist's mark, the philosophical concept, and the daily mechanic. The gallery card with a scribbled cross is *literally* an artist's proof. The daily experience total is *literally* proof that you lived. And the act of spending experience to unlock an app makes the trade-off *visible* — which is the ultimate proof of conscious choice.

**Runner-up**: **Daylight**. Warmer, more accessible, and already resonant within the app's own design language.

### Visual language (building on existing design system)

The existing design system is *already right*. The Creative Director's role is to name what it's doing and amplify it:

- **Paper + ink = the gallery wall**. Daylight theme is not "light mode" — it's the exhibition space.
- **Yellow marker = the curator's hand**. The accent marks what matters. Sparse, decisive.
- **Scribbled cross = the artist's proof mark**. "This one happened. I was here."
- **Hand-drawn frames = the exhibition frames**. Each card is mounted, presented. Your choices deserve framing.
- **Sticker-style ticket cards = admission passes**. Bright, graphic, stuck onto the minimal surface — like a concert ticket in a journal.

No new visual concepts needed. Just **name what already exists.**

---

## 8. Tone of Voice (Editor Agent)

### Diagnosis: what the current voice gets wrong

> *Editor, after hearing everyone*: "The product has two voices and they don't know each other. The shield screams '⚡ BLOCKED' while the gallery whispers 'my heart.' The name says 'DOOM' while the onboarding says 'Meaning > discipline.' These aren't contrasts — they're contradictions. The user can't trust a brand that doesn't know itself."

The design system's written spec (design.json) actually nails the voice: "observational, not motivational" / "neutral, factual, slightly dry" / "never panic the user." The problem is the *implementation* drifted from this spec.

### The unified voice: gallery wall text

> *Editor to Creative Director*: "Gallery wall text is the best model for this app's voice. In a museum, the text next to a painting is: calm, brief, factual, trusting the viewer to have their own experience. It doesn't say 'WOW, ISN'T THIS AMAZING?' It says: 'Oil on canvas, 1889. The artist painted this during a period of solitude.' And you feel everything."

**Voice traits:**

| Trait | How it sounds | Anti-pattern |
|-------|--------------|--------------|
| **Observational** | "Today: 6,200 steps. 7h sleep. 3 pieces." | "Great job! You're crushing it!" |
| **Respectful** | "You chose this. Change it anytime." | "Don't give up! Stay strong!" |
| **Dry** | Empty state: "Nothing here yet. That's fine." | "Oops! Looks like you haven't started!" |
| **Economical** | "10 min · 4 exp" | "Unlock for 10 minutes at a cost of 4 experience" |
| **Gallery-toned** | "Your archive. 60 days of exhibitions." | "Check out your amazing progress!" |
| **Honest about the trade** | "You're spending 10 experience on YouTube." | "Enjoy your well-deserved break!" |

### Unified vocabulary in practice

**Balance card (top of every screen):**
Current: `EXP` / `85 / 60 / 100` / `Move · Reboot · Joy`
Proposed: `experience` / `85 / 60 / 100` / `body · mind · heart`

**Gallery tab header:**
Current: `My activities` / `My creativity` / `My joys`
Proposed: `my body` / `my mind` / `my heart` — three rooms, two words each.

**PayGate:**
Current: `Spend experience` / `YouTube` / `a bit (10 min) ⚡ 4`
Proposed: `spend experience` / `[icon] YouTube` / `10 min · 4 experience`
Close button: `keep it closed` (not "keep it locked" — "locked" implies punishment; "closed" implies choice)

**Shield (blocked state):**
Current: `⚡ BLOCKED` / `[app] is under control.`
Proposed: `[app] is closed.` / `Open Proof to spend experience.` / `[→ Open]`
No lightning bolt. No "BLOCKED" in caps. The shield is firm but not angry. It's a closed gallery door, not a prison gate.

**Onboarding (revised, 7 slides):**

| Slide | Copy | Type |
|-------|------|------|
| 1 | "Your life is an exhibition. Every day, you decide what goes in." | Text |
| 2 | "How many steps make a good day? [slider] This is your baseline. Not a minimum." | Steps setup |
| 3 | "How much sleep? [slider] Rest is part of the exhibition." | Sleep setup |
| 4 | "Choose up to 4 ways your body lived today." | Body room selection |
| 5 | "Choose up to 4 ways your mind was alive." | Mind room selection |
| 6 | "Choose up to 4 things your heart felt." | Heart room selection |
| 7 | "Almost ready. We need a few permissions to make this work. [HealthKit] [FamilyControls] [Notifications]" | Combined permissions |

**Weekly reflection (new):**
```
This week's exhibition:
412 experience earned. 180 spent.
Most visited room: heart.
Richest day: Wednesday.
Least time on screen: Saturday.
```

**Guides tab (new — philosophy wall texts):**

Example entry — "On proof":
```
In printmaking, the artist pulls a proof
before the final edition.
It's the test. The first real mark on paper.
Not for sale. Not for display.
Just evidence that the work is real.

Every day, this app asks you:
what's your proof?
What did you do that says
"I was here, I was awake, I lived"?

The scribbled cross on a completed card
is your proof mark.
Not a checkmark. Not a gold star.
Just a hand-drawn line that says:
this one counts.
```

Example entry — "On the three rooms":
```
Body. Mind. Heart.

Three rooms in a gallery
that contains one full day of being alive.

Your body — dancing it out,
pushing your limits, taking a real risk.
Aristotle called it energeia:
being at work in the world.

Your mind — following your curiosity,
creating something new, noticing the invisible.
Arendt called it the highest human act.

Your heart — holding someone close,
feeling deeply, breaking your rules.
Epicurus said this is not indulgence,
but the careful cultivation of pleasure.

You don't need all three every day.
But an empty gallery asks a question:
where were you?
```

### Voice guidelines for ongoing development

1. **One concept = one word.** Experience. Pieces. Tickets. Spend. Archive. Never introduce a synonym. Grep the codebase quarterly.
2. **No exclamation marks in UI.** Ever. Notifications can have one, maximum.
3. **Empty states are gallery silence.** Not panic. Template: "[What's absent]. [Neutral observation]. [Action]. Or not."
4. **The number is the loudest thing on screen.** When in doubt, make the experience number bigger and everything else quieter.
5. **Shield copy is the firmest the voice gets.** "[App] is closed. Open [AppName] to spend experience." No shouting. No emojis. No lightning bolts.
6. **Guides tab copy is poetry, not advice.** Short lines. No imperatives. Observations that end with an open question.
7. **English only for v1.** Strip all `loc(appLanguage, ...)` wrappers — use plain English strings directly. Remove Russian string branches and the `appLanguage` toggle. Localization can return post-launch if demand warrants it.

---

## 9. Alignment (All Agents)

> *The team, after six rounds*:

**The vision**: This app is a daily gallery of lived experience. You walk, you sleep, you choose pieces for three rooms (body, mind, heart), and the gallery fills up. The fuller your gallery, the more experience you have. When you want to open Instagram or YouTube, you spend experience — consciously, visibly. The app makes the trade-off real. Not through restriction, but through exhibition.

**The name**: **Proof** (first choice) or **Daylight** (if "Proof" has domain/trademark issues).

**The vocabulary**: experience (the number), pieces (the choices), rooms — body, mind, heart (the three categories), tickets (the app groups), spend (the action), archive (the history).

**The tone**: Gallery wall text. Observational. Brief. Trusting. Dry where appropriate. Never motivational. Never punishing.

**The philosophy**: Debord (the spectacle), Benjamin (the aura of the original), Dewey (art as experience), wabi-sabi (beauty in imperfection). These aren't pretensions — they're the *actual ideas* already embedded in the product. The polaroid frames, the scribbled crosses, the paper-and-ink aesthetic, the three rooms of human flourishing (body / mind / heart). The philosophy was always there. Now it has names.

---

## 10. Action Plan

### Short-term (Weeks 1–4): Ship Beta 1

| Week | Tasks |
|------|-------|
| **1** | Domain check: proofapp.com / getproof.com / daylightapp.com. Reserve name on App Store Connect. Create `SharedKeys.swift` (all UserDefaults keys, shared across targets). Fix README. Add privacy manifest. |
| **2** | Rewrite onboarding to 7 slides (gallery-concept-first). Rename balance card labels: "EXP" → "experience", category chips to "body / mind / heart". Rename gallery tab headers to "my body / my mind / my heart". Add action-phrase names to each piece. Update PayGate copy. Disable minute mode in UI. |
| **3** | Build weekly reflection card (aggregate 7 days, show most visited room: body/mind/heart). Build Lock Screen widget (experience number). Write 3 Guides tab entries ("On proof," "On the three rooms" with body/mind/heart framing, "On the threshold"). Complete ticket group Supabase sync. Add rest day override. |
| **4** | Rename app display name. Update shield copy. QA on device. TestFlight build. Recruit 30–50 beta testers. |

### Medium-term (Months 2–6)

| Month | Focus |
|-------|-------|
| **2** | Beta feedback analysis. Onboarding A/B. Widget polish. Landing page ("Prove you lived today"). |
| **3** | Public App Store launch. ProductHunt. Premium tier (3 free tickets, then $3.99/mo). |
| **4** | Home Screen widgets. Shortcuts integration. 2 more Guides entries. |
| **5** | Re-enable minute mode as opt-in. Apple Watch (experience display). |
| **6** | Social exploration (anonymous weekly exhibition leaderboard). Family sharing. |

### Checkpoints

| When | Question | If no... |
|------|----------|----------|
| Week 6 | D7 retention > 20%? | Core loop needs rework. Investigate: are users curating pieces but not spending? Or not curating at all? |
| Week 4 | Can beta users explain the app in one sentence? | Name/messaging isn't landing. Test Daylight or Vigil. |
| Month 4 | Premium conversion > 2%? | Test lower price, different feature gate, or "patron" model (tip jar). |
| Month 3 | >500 installs from launch? | Pivot from organic to creator partnerships. |

---

*This document was produced by a six-agent team (Product, Marketing, Philosopher, Communication Strategist, Creative Director, Editor) working collaboratively on the actual codebase of a semi-finished SwiftUI iOS app (41 Swift files, 3 extensions, 570-line design system). All recommendations are grounded in what exists, not what's imagined. February 9, 2026.*
