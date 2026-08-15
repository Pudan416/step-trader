# Onboarding Competitive Review — Wellness & Activity Apps

Source: Mobbin (iOS), reviewed 2026-08-03. Benchmarked against StepsTrader's current v8 flow
(`StepsTrader/Views/Onboarding/OnboardingModels.swift`).

---

## 1. What the best flows actually do

Across 15+ flows I looked at, the ones that read as "best in class" share a five-beat structure.
Almost nobody nails all five; the strongest (Liven, stoic., Life Reset) hit four.

| Beat | Purpose | Who does it best |
|---|---|---|
| **1. Hook** | One screen that states the promise before asking anything | Life Reset, pliability |
| **2. Interrogation** | 6–20 personalization questions, one per screen, with a progress bar | Liven, Ten Percent Happier, Centr |
| **3. Mirror** | Play the answers back as an insight the user didn't write themselves | Life Reset, Liven |
| **4. Commitment** | Make the user do something that costs them a little | Liven, Finch |
| **5. Ask** | Permissions / account / paywall — always *after* value is felt | stoic., Calm, Centr |

---

## 2. Flow-by-flow notes

### Liven — [Setting up personalized program](https://mobbin.com/flows/5695ec7e-a531-4d04-8381-746e3591db36) (23 screens)

The most complete flow in the set. Three things worth stealing:

- **Answer-reactive reassurance.** Pick "Almost always" on *"It's difficult for me to express emotions"* and an inline
  yellow card appears: "You're not alone — many people grow up learning to hold back emotions…" It responds to the
  *specific answer*, not the question. This turns a survey into a conversation and is cheap to implement (one
  reassurance string per option).
- **Credibility screen mid-flow.** A screen listing Harvard / Oxford / Cambridge under "developed using evidence-based
  psychological practices." Placed after the user has already invested ~10 answers, so it justifies the effort rather
  than making a cold claim.
- **The signature contract.** "Alex Smith, let's make a contract" — four checked commitments, then a finger-signature
  field. Note the footnote: *"Your signature will not be recorded."* That line is what makes it feel like a ritual
  instead of a data grab. Highest-leverage single screen I saw.

Weak spots: 23 screens is long, gender is asked with only Male/Female, and account creation is a raw
email/username/password form when Sign in with Apple would do.

### Life Reset — [Setting up profile](https://mobbin.com/flows/e91bc9a4-db92-449a-8de2-2d5e81381f6b) (12 screens)

- Opens with an explicit contract about *effort*: "Answer all questions honestly… We will use the answers to design a
  tailor-made life reset program for you." Sets expectations for a long flow before the user is annoyed by it.
- Uses confidence sliders ("How confident are you that you can stick with a daily routine for 7 days?") with the
  subtitle "Be honest — there's no wrong answer." Sliders extract intensity that multiple-choice can't.
- **The "WE SEE YOU" mirror screen** is the standout: a full page of prose derived from the answers, with sections
  "Based on your answers," "Here's what most people don't realize," and then concrete first actions. It reads as
  diagnosis, not as a summary of what you clicked.
- Real user stories with photos, names, ages, cities and a dated day-by-day timeline. Far more persuasive than a star
  rating.

### stoic. — [Onboarding](https://mobbin.com/flows/0c54c507-3659-4b57-a758-adaa44ec3aeb) (13 screens)

Best-executed *ask* sequence of anything I reviewed:

- **Pre-permission priming.** Before the iOS notification dialog, it shows the actual mock notification
  ("Let's start your day 🌞") and three reminder-time pickers under "Healthy habits form through consistency… You're
  most likely to form a healthy habit with 3 daily notifications." The user has already configured *what* the
  notifications are before iOS asks *whether*. There's even a pointing-hand emoji aimed at Allow.
- **Fake-but-honest plan generation.** "We need a few seconds to prepare stoic for you…" with three checklist items
  animating in, plus social proof in the same breath: "Yesterday 35908 people said stoic helped them feel better."
- **Trial timeline.** "how your free trial works" as a vertical timeline: Install → Today: Instant Access →
  Day 5: Trial Reminder ("Cancel anytime in just 15 seconds") → Day 7: Trial Ends on 19 January. Naming the exact date
  and the cancel effort is the trust move.
- Every question screen has "Skip" and "Your selections won't limit access to any features."

Centr ([Onboarding](https://mobbin.com/flows/848ee3f1-7bc7-403d-a2ff-f58b178fadfe)) runs the same Day 0 / Day 5 / Day 7
timeline pattern inside the plan-selection screen itself.

### Finch — [Setting up goals](https://mobbin.com/flows/19212698-61fe-43ca-9144-60c9e73bbcd2) (6 screens)

The shortest good flow. It works because the mascot does the asking — "Lee is curious about how she can grow with you"
— which reframes a data-collection form as getting to know a character. Ends on **"Sam Lee's starter plan"**: six
absurdly easy goals (Get out of bed, Brush teeth, Drink water) under "Try these easy goals with Lee!" The first-session
success is guaranteed by design.

### GO Club — [Onboarding](https://mobbin.com/flows/8c85874d-0226-48fc-bb4b-ea078f839080) (13 screens)

The closest direct competitor — steps + rewards + Apple Health. Its HealthKit priming screen is the model:
the two app icons joined by a link glyph, "link to Apple Health," a one-line benefit, then a padlocked block:
*"Your health data is never stored or shared with third parties. It remains private and is used only to enhance your
experience."* Privacy reassurance is co-located with the ask, not buried in a policy link.

Its home screen then immediately shows "Today's Goal — Moderate Walk, 7,500 steps" — the number the user just chose,
rendered as a plan.

### Alan — [Setting up step tracking](https://mobbin.com/flows/bb717234-ff12-49c0-bf61-0325825dd83d) (8 screens)

Worth noting for the *recovery* case, which most apps ignore: when HealthKit access lapses it shows an in-feed card
"We lost track of your steps… Restore access" and a second card "Tracked your activities elsewhere? Import them from
Apple Health to earn berries." Denial and revocation are treated as normal states with a path back, not dead ends.

### Google Fit — [Onboarding](https://mobbin.com/flows/c60bcb1c-d50a-4ec2-aab6-d2485d568236) (13 screens)

Textbook restraint on permissions: two separate screens (Apple Health, then notifications), each with a
**"Not now"** button given equal visual weight to the accept button. Notification priming shows a grey notification
mock. Boring, but the double-opt-in pattern is why their prompt acceptance survives.

### Ten Percent Happier — [Onboarding](https://mobbin.com/flows/204daba0-f0f7-4e6c-819b-d50e83e69d79) (43 screens)

Longest flow in the set. Two details survive the bloat: **"Prefer not to answer"** sits directly above the Continue
button on the age screen (an escape hatch that doesn't break the flow), and the account screen is titled
**"Let's save your preferences."** — account creation framed as protecting work already done rather than as a gate.

### Calm — [Onboarding](https://mobbin.com/flows/38549b00-2fe8-4fd1-914b-13c4905db245) (10 screens)

Opens with a full-screen "take a deep breath" — a zero-input value delivery before any question. Paywall is headed
"Your plan is ready. Unlock Calm for free," and carries a **"Remind me 2 days before renewal"** toggle. Offering to
warn you before charging you is a strong trust signal that costs conversions almost nothing (and Calm has to say
"Enable notifications in Settings" to honor it, which is exactly the kind of dependency worth designing around).

Also asks "How did you hear about Calm?" — attribution data collected as a question, post-install.

### pliability — [Onboarding](https://mobbin.com/flows/8e997db2-fa64-42a0-a86d-3ad07e9df1ce) / [Customizing an experience](https://mobbin.com/flows/55148cf9-a50f-41d4-b9b0-e8e836ca850d)

Only flow that delivers the core action *during* onboarding: "Take a moment to reset — this quick 5-minute session
will get you moving and feeling better," with Start Session / **Not Now**. Then: "Way to go, Alex! You just completed
your first session ✓ — Let's set you up for what's next." Activation is complete before the flow ends.

Also runs a "Start your Mobility Journey" checklist as a persistent post-onboarding surface — deferring the optional
setup instead of cramming it in.

### Evernote — [Onboarding](https://mobbin.com/flows/4f4d734f-364e-4506-917e-6a5a17fbadff)

The cynical version, useful as a "don't": a fake "Personalizing your experience — 40%" progress ring whose only job is
to build anticipation for the paywall (button: "Discover your plan"). No personalization is visible afterward.
The technique only earns its keep if the plan that follows is genuinely different per user — stoic. and Life Reset earn
it; Evernote doesn't.

### Fitbit — [Onboarding](https://mobbin.com/flows/83080a39-a578-4767-b12e-f799ef73ce72)

Mostly a cautionary tale — account reconciliation ("Looks like you're new to Fitbit"), a profile form (weight/height/
sex) with a greyed-out Save button, and a wall-of-text research-consent screen before any value. The one good detail:
each field explains *why* it's needed ("Fitbit uses sex to calculate metrics like calories burned"). Ships a
zero-state home screen full of "No data," which is the worst possible first impression for a tracking app.

---

## 3. Read on StepsTrader's v8 flow

Current sequence (13 slides): cold open → the app → canvas/sleep goal → canvas/steps goal → day-end → balance →
body-mind-heart → color cap → **HealthKit** → **Screen Time app pick** → **notifications** → **Apple sign-in** → welcome.

**What's already ahead of the field.** The first-person authored voice ("i live mostly online. working. scrolling.
staring at a screen. probably just like you.") does in two lines what Liven spends a credibility screen on — nobody
else in the set has a human behind it. The canvas metaphor teaches the mechanic *by having the user set the values that
drive it*, which is better than the standard question-then-explain split. `skipToSetup()` respects returning/impatient
users. Slide-level analytics with duration and `action_taken` is more instrumentation than most of these apps appear
to have.

**The structural problem: four asks in a row, no payoff between them.** Slides 9–12 are HealthKit → Screen Time
(FamilyControls) → notifications → Sign in with Apple. That is four system dialogs back to back, and the Screen Time
prompt is the scariest permission on iOS. Every app above interleaves value between asks; pliability delivers a whole
session mid-flow. Compounding it, the flow ends on `welcomeV8` — the mirror/plan-reveal moment that Life Reset and
stoic. use to *earn* the asks sits after them instead of before.

**Six concrete changes, ranked by expected impact:**

1. **Move a personalized reveal in front of the permission block.** You already have everything needed — sleep goal,
   step goal, day-end time, body/mind/heart weighting, color cap. Render it as "your canvas" with the user's own
   numbers before slide 9. This is the Life Reset "WE SEE YOU" screen, and unlike Life Reset's, yours would be
   genuinely computed.
2. **Prime the Screen Time ask harder, and consider deferring it.** It's the highest-anxiety permission in the flow and
   currently sits third of four. Either move it after first value (a "spend colors" moment on the home screen), or give
   it a GO Club-style privacy block: what iOS's FamilyControls actually exposes to you, and what it doesn't.
3. **Show the notification before asking for notifications.** Copy stoic.: render the actual unlock notification as a
   mock, let the user pick the time, *then* trigger the system prompt. Your justification ("they're needed to unlock
   the apps") is already stronger than most — pair it with the artifact.
4. **Reframe the sign-in slide.** "btw, my name is kosta. and who are you?" is the best-written line in the flow, but
   it asks for identity without naming a benefit at the moment of ask. Ten Percent Happier's "Let's save your
   preferences." is the pattern — the microcopy about syncing should be the headline, with the personal line as the
   setup.
5. **Add a commitment beat.** Liven's contract is the single highest-leverage screen I saw, and it maps cleanly onto
   your color-currency framing: "from today, i'm trading screen time for real life" with the user's chosen step and
   sleep targets listed, and a signature field that explicitly isn't recorded.
6. **Design the denial paths.** HealthKit denied, Screen Time denied, notifications denied — copy Alan's in-feed
   "Restore access" cards rather than letting the user land on an empty canvas. Fitbit's zero-state home is what
   happens if you don't.

**Two things to explicitly not copy:** Evernote's fake progress ring (you'd be spending trust you have and they don't),
and Ten Percent Happier's 43-screen length. Your 13 slides carry more meaning per screen than most of these carry in
20.

**One open question:** `PaywallView` / `PayGateView` aren't in the onboarding slide sequence. If monetization happens
post-onboarding, the stoic./Centr trial-timeline screen (Day 0 → Day 5 reminder → Day 7 charge, with the literal date)
is the pattern to reach for whenever it does appear.
