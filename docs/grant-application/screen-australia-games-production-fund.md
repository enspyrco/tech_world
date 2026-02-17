# Screen Australia Games Production Fund — Application Plan

**Applicant:** Enspyrco Pty Ltd
**Project:** Tech World
**Grant Amount Requested:** Up to $100,000
**Round Deadline:** 5pm AEDT Thursday, March 5, 2026 (~2.5 weeks)
**Decision:** ~12 weeks after deadline (early June 2026)
**Approval Rate:** ~18% of eligible applications (August 2025 round)
**Guidelines Version:** Issued 03/10/2023, Updated 14/11/2025

---

## Table of Contents

1. [Grant Overview](#1-grant-overview)
2. [Eligibility Assessment](#2-eligibility-assessment)
3. [Current State of Tech World](#3-current-state-of-tech-world)
4. [What's Missing — Development Roadmap](#4-whats-missing--development-roadmap)
5. [Milestone & Budget Plan](#5-milestone--budget-plan)
6. [Application Materials Checklist](#6-application-materials-checklist)
7. [Assessment Criteria Strategy](#7-assessment-criteria-strategy)
8. [Tips for a Compelling Application](#8-tips-for-a-compelling-application)
9. [Pitch Video Script (3 Minutes)](#9-pitch-video-script-3-minutes)
10. [Application Timeline (Now → March 5)](#10-application-timeline-now--march-5)
- [Appendix A: If Successful — Contracting Requirements](#appendix-a-if-successful--contracting-requirements)
- [Appendix B: Useful Links](#appendix-b-useful-links)

---

## 1. Grant Overview

Screen Australia's Games Production Fund provides **non-repayable grants of up to $100,000** to Australian independent game studios with early-stage prototypes. The fund supports development to a significant project milestone. The program runs from FY 2023/24 through FY 2026/27.

### Key Terms
- Grants are **non-repayable** (no equity, no repayment, no IP stake)
- At least **90% must be spent on Australian development expenditure**
- Acceptable uses: staff wages, software, creative licensing, business operations (accounting, legal, storefront fees, hardware), marketing (especially for release-targeting projects)
- Developer wages should represent a **"large portion"** of the requested funding (per FAQs)
- Projects must have budgets **under $500,000** at time of application
- One application per company per round (across both Games Production Fund and Emerging Gamemakers Fund)
- After **two unsuccessful applications**, a project is no longer eligible for the fund (but the company can apply with a different project)
- Unsuccessful applicants may re-submit **once** with meaningful updates; can also schedule a 15-minute feedback call

### Payment Structure
- **80%** paid on signing the Project Grant Agreement (PGA)
- **20%** paid on Screen Australia's approval of Final Cost Report and Delivery Materials
- Payment conditions include: solicitor confirmation letter (IP clearance), signed NFSA Deed

### Competition Context (August 2025 Trends Report)
- 61 eligible GPF applications, 131 EGF applications = 192 total
- **Only 18% approval rate** — the fund is highly competitive
- Over 56% of applicants were repeat applicants (quality increasing each round)
- ~75% of applications targeted vertical slice, demo, or Early Access milestones
- Multiplayer games have seen a "significant uptick" — almost 1/3 of applications now feature multiplayer
- Trend toward open-source solutions over proprietary software (positive for our Flutter/Flame stack)

### Assessment Criteria (4 pillars — exact wording from guidelines)
1. **Creative Merit**
   - The level of originality and the quality of execution of the game and how compelling the overall experience is, as communicated through the prototype and application documents
   - The ability of the game to effectively meet the studio's strategic outcomes
2. **Viability**
   - The scope of the project and how viable and realistic it is
   - How timely and relevant the project is to industry and the studio's strategic outcomes
   - How realistic the budget and production plan are, whether workers are **fairly compensated**
   - Whether the proposed team has the appropriate experience to execute their plans
3. **Impact**
   - The extent to which funding will positively affect the studio's proposed trajectory
   - The commercial and/or cultural benefits the project provides to the Australian games landscape, and contribution to its quality and reputation
4. **Equity, Diversity, Inclusion & Accessibility**
   - Where diverse groups are portrayed, whether there is appropriate representation in the creative team or meaningful collaboration/consultation
   - Whether there is engagement with an audience that is typically underserved
   - The alignment of the application with the diversity, equity and inclusion aims of the grant

### Supported Milestones
- Game completion or release
- Early Access release
- **Demo completion for events** ← our target
- Vertical slice of global competitive quality
- Prototype advancement toward awards/festivals/gallery/museum exhibits
- **Any other goal, as defined by the applicant**

---

## 2. Eligibility Assessment

| Requirement | Status | Notes |
|---|---|---|
| Registered Australian company (private, not sole trader or public) | YES | Enspyrco Pty Ltd |
| Not majority owned/controlled by overseas company | YES | Australian-owned |
| Playable prototype | YES | Fully functional multiplayer prototype |
| Clear, well-scoped milestone actively being worked towards | YES | PAX Aus demo Oct 2026 |
| Pre-production or production stage | YES | In production since mid-2024 |
| Australian creative control (citizens/PR) | CONFIRM | Key creatives must be AU citizens/PR |
| Predominantly developed in Australia | CONFIRM | |
| Not previously funded by GPF or Games: Expansion Pack | YES | First application |
| Not applying to EGF in same round | YES | Only applying to GPF |
| Digital game platform | YES | Web, macOS, iOS, Android |
| Original IP (not licensed third-party IP) | YES | Original IP owned by company |
| Not housed in third-party platform (Roblox, UEFN, etc.) | YES | Standalone web app |
| No enrolled students on team (games/games-adjacent field) | CONFIRM | Meetup group, not university project |
| Not led by or reliant on full-time students | CONFIRM | |
| Not a B2B/training product | YES | Consumer-facing game — frame as game, NOT educational platform |
| No gambling/pay-to-win/play-to-earn mechanics | YES | |
| No content that would prevent Australian classification | YES | |
| Meets Terms of Trade | YES | Company applicant, original IP |

### Eligibility Risk: "Learning Project" Warning
> The Trends Report specifically warns: *"A small number of applications had a history of being learning projects whose scope has evolved to an unviable level. It is rare for games that first evolved as learning projects to be viable in other contexts, especially commercial ones."*

**This directly applies to Tech World** — it started as a meetup learning project. The application must clearly frame it as having **evolved beyond** that origin. Emphasise: the meetup was the incubator, but the game has outgrown it. The technical foundation is production-quality (CI/CD, test coverage, cross-platform). Position the grant as the transition from community project to commercial studio.

### IP Ownership
> The Trends Report notes many applicants had unclear IP ownership, causing contracting complications. Ensure **Enspyrco Pty Ltd** clearly owns all IP. Any contributor work should have appropriate contractor/assignment agreements in place. Legal advice recommended.

### Action Items
- [ ] Confirm all key creatives are Australian citizens or permanent residents
- [ ] Confirm no team members are currently enrolled students in games-adjacent fields
- [ ] Confirm no team members juggling multiple active game projects (Trends Report flags this as a concern)
- [ ] Review full Terms of Trade document (especially clause 2.2 for company eligibility, clause 4.7.a for fair compensation)
- [ ] Ensure Enspyrco Pty Ltd has formal IP ownership — get legal advice, prepare contractor agreements if needed
- [ ] Review Screen Australia's Guiding Principles on generative AI use

---

## 3. Current State of Tech World

### Project Summary
Tech World is a multiplayer 2D game built with Flutter and the Flame engine. Players explore a shared virtual world, collaborate at coding terminal stations, chat with an AI companion (Clawd), and see each other via proximity-based video chat. It's a social coding adventure — think Stardew Valley meets Zachtronics, where the puzzles are real code.

### Technical Stats
- **First commit:** June 2023 (current architecture since July 2024)
- **Active development:** 85+ PRs merged
- **Codebase:** ~10,000 lines of production Dart code
- **Tests:** ~5,800 lines across 34 test files
- **CI/CD:** Automated analysis, testing (45% coverage threshold), and deployment to Firebase Hosting
- **Platforms:** Web (primary), macOS, iOS, Android

### Features — COMPLETE

#### Core Game World
- 2D game world rendered with Flame engine
- Tap-to-move with animated 8-directional player sprites
- Jump Point Search pathfinding around barriers
- 4 predefined maps with customizable layouts (Open Arena, L-Room, Four Corners, Simple Maze)
- Grid-based coordinate system with mini-grid navigation
- Terminal station components placed on maps (green ">_" icons)

#### Multiplayer
- Real-time multiplayer via LiveKit data channels
- All players visible in shared game world with animated sprites
- Position broadcasting and synchronization
- Room-based sessions (map ID = room name)

#### Proximity-Based Video Chat
- Video feeds rendered as circular bubbles in the game world
- Chebyshev distance proximity detection (3-grid-square threshold)
- Zero-copy FFI frame capture on macOS, GPU-efficient ImageBitmap on web
- Custom fragment shader for visual effects (glow, animation)
- Camera and microphone controls

#### AI Tutor — Clawd
- AI bot ("bot-claude") joins LiveKit room as a participant
- Powered by Claude 3.5 Haiku for fast, cost-effective responses
- Shared chat visible to all participants
- Text-to-speech: Clawd speaks responses via browser speechSynthesis API
- Speech-to-text: voice input via browser SpeechRecognition API
- Bot character rendered as a sprite in the game world

#### In-Game Code Editor
- Terminal stations on maps that players can interact with (proximity-gated, 2 grid squares)
- Code editor panel (replaces chat sidebar) using code_forge_web
- Dart syntax highlighting via re_highlight
- 3 starter coding challenges: Hello Dart, Sum a List, FizzBuzz
- Submit code to Clawd for AI-powered review

#### Authentication & Infrastructure
- Firebase Auth (email/password, Google Sign-In, Apple Sign-In)
- LiveKit token generation via Firebase Cloud Function
- Auto-deploy to Firebase Hosting on merge to main
- Loading screen with progress stages
- Auth menu with sign-out

### Features — NOT YET IMPLEMENTED

| Feature | Priority | Complexity |
|---|---|---|
| Progression system (track completion, scoring) | HIGH | Medium |
| Challenge persistence (save progress) | HIGH | Medium |
| Sound effects & music | HIGH | Medium |
| More coding challenges (target: 20+) | HIGH | Low per challenge |
| Challenge difficulty tiers | HIGH | Low |
| Enhanced Clawd tutoring (hints, grading, feedback) | HIGH | Medium |
| More maps / themed areas | MEDIUM | Low |
| LSP integration for code editor | MEDIUM | High |
| Leaderboards & achievements | MEDIUM | Medium |
| Social features (friends, DMs) | LOW | High |
| Code execution sandbox | LOW | High |
| Mobile video support | LOW | Medium |
| Matchmaking | LOW | High |

---

## 4. What's Missing — Development Roadmap

### Phase 1: Pre-Application Polish (Now → March 5, 2026)
Focus: Make the prototype demo-ready for assessors.

| Task | Due | Est. Days |
|---|---|---|
| Fix any bugs in current prototype | Feb 17 | 2 |
| Test prototype on fresh machine (assessor experience) | Feb 18 | 1 |
| Record 30-second gameplay footage | Feb 20 | 1 |
| Write Production Plan (7 pages, use SA template) | Feb 22 | 3 |
| Write Strategic Outcomes (6 pages, use SA template) | Feb 24 | 2 |
| Complete Finance Plan & Budget (SA template) | Feb 25 | 2 |
| Record 3-minute pitch video | Feb 27 | 2 |
| Prepare Prototype Details document | Feb 28 | 1 |
| Compile team CVs | Mar 1 | 1 |
| Final review and submit on SmartyGrants | Mar 3–4 | 2 |

### Phase 2: Core Game Loop (April–June 2026, funded)
Focus: Transform prototype into a complete game loop with progression.

| Task | Target | Est. Weeks |
|---|---|---|
| Progression system (challenge completion tracking, scores, stars) | Apr 2026 | 2 |
| Challenge persistence (save/resume via Firebase) | Apr 2026 | 2 |
| 10 additional coding challenges across 3 difficulty tiers | May 2026 | 3 |
| Enhanced Clawd tutoring (structured hints, code review feedback, grading rubric) | May 2026 | 3 |
| Sound design (ambient music, interaction SFX, chat notification sounds) | Jun 2026 | 2 |
| 2 new themed maps (Library, Workshop) | Jun 2026 | 1 |

### Phase 3: Polish & Event Prep (July–September 2026, funded)
Focus: Polish for PAX Aus demo.

| Task | Target | Est. Weeks |
|---|---|---|
| 10 more coding challenges (20 total) | Jul 2026 | 2 |
| Achievement system (badges for milestones) | Jul 2026 | 2 |
| Onboarding tutorial (guided first experience) | Aug 2026 | 2 |
| UI/UX polish pass (menus, transitions, responsive design) | Aug 2026 | 2 |
| LSP integration for real-time code diagnostics | Aug–Sep 2026 | 3 |
| Performance optimization and cross-platform testing | Sep 2026 | 2 |
| PAX Aus demo build preparation | Sep 2026 | 1 |

### Phase 4: PAX Aus Demo (October 2026)
- **PAX Aus: October 9–11, 2026** (Melbourne Convention Centre)
- **GCAP: Early October 2026** (developer conference, same week)
- Playable demo on show floor
- Networking with publishers, media, players

---

## 5. Milestone & Budget Plan

### Proposed Milestone
> **Playable public demo at PAX Aus 2026 (October 9–11) with 20 coding challenges, progression system, AI tutoring, and multiplayer video chat.**

This aligns with Screen Australia's supported milestone: *"Demo completion for events."*

### Budget Breakdown (Indicative — final version must use SA .xlsx template)

| Category | Amount | % | Notes |
|---|---|---|---|
| **Developer salary** | $60,000 | 60% | Lead developer, 6 months part-time or 3 months full-time. Must meet minimum industry rates |
| **Art & sound design** | $12,000 | 12% | Commissioned pixel art, ambient music, SFX |
| **Infrastructure** | $5,000 | 5% | LiveKit hosting, GCP compute, Firebase |
| **Event costs (PAX Aus)** | $8,000 | 8% | PAX exhibitor booth, travel, accommodation, signage |
| **Contractor/specialist** | $8,000 | 8% | UX review, accessibility audit, playtesting. All contractors must be fairly compensated |
| **Software & tools** | $3,000 | 3% | Licenses, analytics, monitoring |
| **Marketing** | $4,000 | 4% | Trailer production, social media, press kit. Must be backed by a marketing strategy |
| **Total** | **$100,000** | **100%** | |

> Note: 90%+ is Australian expenditure as required.

### Total Project Budget (Finance Plan must capture ALL sources)

The Finance Plan & Budget spreadsheet must present a **complete picture** of the project's finances, not just the SA grant. Per the Trends Report, competitive applications include other income streams.

| Source | Amount | Type | Notes |
|---|---|---|---|
| Screen Australia GPF | $100,000 | Cash (requested) | The grant |
| Founder in-kind | $50,000–$80,000 | In-kind | Prior development time — give appropriate valuation |
| Existing infrastructure | $5,000–$10,000 | In-kind | Firebase, GCP, LiveKit already operational |
| Meetup community | $5,000–$10,000 | In-kind | Playtesting, feedback, community support |
| **Total project budget** | **~$170,000–$200,000** | | Must be under $500,000 |

> **Trends Report warning:** *"Many supplied Finance Plans and Budgets failed to include a comprehensive account of the funding and financing sources."* Include ALL sources. Where in-kind work has been done, value it appropriately. Do not include "pending" items unless they'll be confirmed within 1–2 months.

> **Other funding:** Having state screen agency funding or other confirmed funding is competitive (~30% of applicants in the August 2025 round had confirmed funding from other screen agencies). Consider applying to state-level funding as well (e.g. Film Victoria, Create NSW). You can apply for both simultaneously.

---

## 6. Application Materials Checklist

| Material | Format | Status | Notes |
|---|---|---|---|
| **Pitch video** | MP4 or WMV, H.264, 720p, <200MB, max 3 min. **Must be downloadable** (no YouTube/Vimeo links) | TO DO | See script in Section 9 |
| **Playable prototype** | Tested, functional build. **Must work for 12 weeks** (entire assessment period) | READY | Web build on Firebase Hosting |
| **30-sec gameplay footage** | Downloadable video | TO DO | Screen record of gameplay |
| **Prototype Details doc** | PDF/doc (no template — use format that best communicates) | TO DO | Hardware reqs, step-by-step setup, controls, intended experience |
| **Production Plan** | Max 7 pages, **must use SA template** (.docx downloaded) | TO DO | Production timeline, milestone descriptions, acceptance criteria |
| **Strategic Outcomes** | Max 6 pages, **must use SA template** (.docx downloaded) | TO DO | Significant milestone, steps to achieve it, how SA funding helps |
| **Finance Plan & Budget** | **Must use SA spreadsheet template** (.xlsx downloaded) | TO DO | Must include ALL funding sources (SA grant + in-kind + any other) |
| **Team CVs** | PDF | TO DO | All key team members — ensure names match across all documents |
| **Letters of support** | PDF (optional but competitive) | TO DO | From peers, industry leaders, clients |
| **Letters of commitment** | PDF (optional but competitive) | TO DO | From team members confirming their commitment to the project |
| **Risk analysis** | Can be within Production Plan | TO DO | Thorough risk identification + mitigation plans |
| **Marketing plan** | Can be within Strategic Outcomes | TO DO | Competitor analysis, target audience, player psychographics |
| **Accessibility plan** | Can be within Strategic Outcomes | TO DO | Scoped, budgeted, realistic (not an overly ambitious wishlist) |
| **First Nations content** | Statement + consent + consultation | N/A | Only if depicting First Nations content |

> **IMPORTANT (from Trends Report):** Ensure all team members listed in the application also appear in the budget. Ensure the timeline is consistent across ALL documents. Ensure Finance Plan captures all funding sources including in-kind contributions. Use the **current templates** — deviating from templates is flagged as uncompetitive.

> **IMPORTANT (from Guidelines):** If submitting materials via cloud storage (Google Drive, Dropbox), ensure all materials are present, functional, and accessible before the round closes AND throughout the 12-week assessment period. Materials added/edited after the round closes will not be considered.

### Prototype Details Document (Contents)
- **Platform:** Web (Chrome/Edge recommended), also available on macOS
- **URL:** [Firebase Hosting URL]
- **Hardware:** Any modern computer with webcam and microphone
- **Setup:** Open URL, sign in with email/password or Google
- **Controls:** Click/tap to move, click terminals to open code editor, type in chat panel
- **Experience:** You'll enter a shared multiplayer world. Walk to green terminal stations to open coding challenges. Chat with Clawd (the AI tutor) in the side panel. If another player is nearby, you'll see their video feed as a bubble.

> **Prototype Tip (from Trends Report):** *"Bespoke, smaller, well curated and prepared prototypes were more effective than prototypes that were simply the latest work-in-progress build of a game."* Consider building a curated demo experience for assessors rather than just pointing them at the live app.

---

## 7. Assessment Criteria Strategy

### 1. Creative Merit — "Why is this game special?"

**Key argument:** Tech World is the first multiplayer game where coding IS the core gameplay mechanic AND players are socially present with live video. No existing game combines:
- Real coding challenges (not drag-and-drop) as gameplay
- AI tutoring companion that responds intelligently to code
- Live video chat creating genuine social presence in a game world
- Collaborative learning through play

**Comparisons to draw:**
- **Zachtronics** (TIS-100, Opus Magnum) — proved coding puzzles can be beloved indie games, but these are single-player
- **Stardew Valley** — cozy multiplayer world with progression, but no educational mechanic
- **CodeCombat / Codecademy** — coding education, but not a game with social presence
- **Rec Room / VRChat** — social virtual worlds, but no structured gameplay or learning

**Tech World is at the intersection of all four.** No one has done this before.

### 2. Viability — "Can you actually build this?"

**Key argument:** The hardest technical challenges are already solved.

What we've already built (the stuff that's genuinely difficult):
- Real-time multiplayer synchronization via LiveKit
- Zero-copy video rendering inside a game engine (FFI on native, GPU-efficient on web)
- AI bot integration as a live participant in the game world
- Cross-platform support (web, macOS, iOS)
- Automated CI/CD pipeline with test coverage enforcement

What remains is **content and polish** — adding more challenges, progression tracking, sound, and UI refinement. This is straightforward execution, not speculative R&D.

**Development velocity evidence:**
- 30+ PRs merged in the last 3 weeks (Jan 29 – Feb 6, 2026)
- Went from basic movement to full video chat + AI tutor + code editor in ~2 weeks
- 85+ PRs total, clean git history, comprehensive test coverage

**Fair compensation (required by Terms of Trade clause 4.7.a):**
- Budget must show all team members paid at minimum industry rates
- Where in-kind/sweat equity work has been done, give it an appropriate valuation in the Finance Plan
- The Trends Report flags teams with "relatively large team sizes without providing evidence of fair compensation" as uncompetitive

**Risk Analysis (Trends Report says competitive apps include this):**
Include a thorough risk analysis and mitigation plan. Key risks to address:
- Technical: LiveKit dependency, cross-platform compatibility, scaling to 50+ users
- Content: challenge quality, AI tutor accuracy, playtesting feedback loops
- Timeline: PAX Aus deadline is fixed — include explicit buffer time in milestones
- Team: capacity concerns if members are on multiple projects
- Market: discoverability in a crowded indie space

### 3. Impact — "What does the $100k change?"

**Without funding:**
- Tech World remains a meetup project, developed in spare time
- Slow progress, no event presence, no public release timeline

**With funding:**
- Dedicated development time → PAX Aus demo in October 2026
- Professional art and sound → polished game feel
- Event presence → visibility in Australian games community
- Pathway to Early Access release → sustainable studio

**Broader contribution to Australian games landscape:**
- Demonstrates Flutter/Flame as a viable game engine (expanding Australian game dev beyond Unity/Unreal)
- Creates an open-source multiplayer game framework that other Australian developers can learn from
- Builds community around coding-as-gameplay, a genre with massive global potential
- From a meetup group to a studio — shows grassroots game development is viable in Australia
- Aligns with the trend toward open-source tools noted in Trends Report

**Marketing & Discoverability Strategy (Trends Report says this is critical):**
> *"Had a strong understanding of the importance of marketing, promotion, and discoverability"* and *"included a marketing plan that covered a competitor analysis, target audience, and/or player psychographic profiles"* were listed as traits of the most competitive applications.

Must include:
- **Target audience:** Who specifically plays this game? (Not "everyone who codes" — define a niche)
- **Competitor analysis:** How does Tech World compare to Zachtronics, CodeCombat, Screeps, etc.?
- **Player psychographics:** What motivates our players? (Social connection + mastery + creativity)
- **Discoverability plan:** How will players find us? (PAX, indie showcases, dev communities, coding bootcamps)
- **Marketing timeline:** When do we start building audience? (Steam page, social media, dev logs)

### 4. Equity, Diversity, Inclusion & Accessibility

> **Critical (from Trends Report):** *"Did not consider accessibility or diversity at all"* was listed as a trait of the **least competitive** applications. EDIA is one of four assessment criteria and **must** be addressed. However, *"Many applications indicated accessibility measures but did not substantiate or provide a plan or documentation"* — so don't just list aspirations, **scope and budget them**.

**Key argument:**
- Tech World is inherently inclusive — it's designed to make coding accessible and social
- The game targets people who might not see themselves as "coders" — by embedding coding in a social, game-like experience
- Voice input (STT) and voice output (TTS) support players who prefer not to type
- Web-first design means no expensive hardware or downloads required
- The meetup community includes diverse skill levels, backgrounds, and ages
- [Add specific team diversity information here]

**Planned accessibility features for PAX demo (must be scoped, budgeted, and in timeline):**
- Keyboard-only navigation option
- Screen reader compatibility for chat and code editor
- Configurable text sizes
- Color-blind-friendly UI palette

**Must include in application:**
- Specific budget line items for accessibility work
- Timeline allocation for accessibility implementation
- Consideration of accessibility audit (included in contractor/specialist budget)

---

## 8. Tips for a Compelling Application

### DO (incorporating Trends Report insights)
- **Show, don't tell** — The prototype IS the strongest argument. Make sure it works flawlessly for assessors.
- **Be specific about the milestone** — "Playable demo at PAX Aus October 2026 with 20 challenges and progression system" beats "continue developing the game."
- **Show development velocity** — 85 PRs, 10k lines of code, working multiplayer + video + AI in a few months. This team ships.
- **Frame it as a game first** — Coding is the *mechanic*, not the *purpose*. Players will come for the fun, the social experience, the satisfaction of solving puzzles. The learning is a bonus.
- **Name your differentiators** — No other game combines real coding + multiplayer video + AI tutor. Be explicit about this.
- **Be honest about what's built vs. planned** — Assessors respect transparency over overpromising.
- **Include realistic milestones with explicit buffer time** — Compressed timelines are flagged as uncompetitive.
- **Include a marketing plan** — Competitor analysis, target audience, player psychographics. Justify every marketing dollar.
- **Include risk analysis with mitigation** — Technical, timeline, team capacity, market risks.
- **Get letters of support** — From peers, industry leaders, meetup members. Letters of commitment from team members.
- **Ensure consistency across ALL documents** — Team members in application = team members in budget = team members in CVs.
- **Value in-kind work appropriately** — Sweat equity needs a dollar value in the Finance Plan.
- **Address ALL four assessment criteria** — Don't skip EDIA.
- **Scope accessibility realistically** — A focused, budgeted plan beats an aspirational wishlist.
- **Proofread everything** — Give yourself adequate time. Last-minute applications are rarely competitive.

### DON'T
- Don't call it an "educational platform" or "learning tool" — sounds B2B, which is ineligible
- Don't undersell the prototype — you have a working multiplayer game with video chat and AI, not a proof of concept
- Don't pad the budget — $100k should clearly map to specific deliverables
- Don't claim you'll build everything — scope the milestone to what's achievable in 6–8 months
- Don't forget the 30-second gameplay video — this is the first thing assessors see, make it exciting
- **Don't use obviously AI-generated language** — The Trends Report warns that assessors can tell, and AI-written text "may not be an appropriate tool in crafting a competitive application for cultural funding." Write authentically.
- **Don't lean into the "learning project" origin** — Frame the meetup as an incubator, not the identity of the project
- **Don't list release platforms you can't deliver on** — Each platform becomes a contractual obligation. Start with web.
- **Don't deviate from the provided templates** — Use them exactly as given
- **Don't submit materials via unstable cloud links** — They must work for 12 weeks
- **Don't use "playtesting" and "QA testing" interchangeably** — They are different processes with different goals

### Pitch Video Tips (from FAQs and Trends Report)
- **Format:** MP4 or WMV, H.264 codec, 720p resolution, under 200MB, max 3 minutes
- **Must be downloadable** — No YouTube or Vimeo links
- **First 30 seconds:** Hook them. Show gameplay, not a talking head.
- **Spend ~1 minute or less on the game itself** — Also cover the team, why you're making this, and how the grant helps.
- **Middle 90 seconds:** Show the prototype, explain the vision, introduce the team.
- **Last 60 seconds:** The milestone, the plan, why this matters to Australian games.
- Show your face — assessors fund people, not just projects
- Keep energy up, be genuine, show passion
- **Address the assessment criteria** in the video — competitive videos do this
- **Don't speculate about design possibilities** — Uncompetitive videos spend too long on hypotheticals
- **Plan and rehearse** — Unplanned, unrehearsed videos are flagged as uncompetitive

---

## 9. Pitch Video Script (3 Minutes)

### [0:00–0:30] HOOK — Gameplay Montage

*[Screen recording: Player moving through the game world, walking up to a terminal, opening the code editor, typing code, submitting to Clawd, receiving feedback. Cut to: two players near each other with video bubbles. Cut to: chat panel with Clawd responding.]*

**VOICEOVER:**
"What if learning to code felt like playing a game with friends? Not a gamified tutorial — an actual multiplayer game where writing code is how you play."

### [0:30–1:00] THE GAME — What Tech World Is

*[Show the prototype — walk through key features while narrating.]*

**ON CAMERA (or voiceover with gameplay):**
"This is Tech World — a multiplayer game where players explore a shared world, solve coding challenges at terminal stations, and get real-time help from an AI companion called Clawd.

When you walk near another player, their live video appears as a bubble in the game world. You can talk, collaborate on challenges, or just hang out. It's the social experience of a coding meetup, inside a game.

Clawd — our AI tutor powered by Claude — is a character in the world. You can ask questions, submit your code for review, or even talk to it using your voice."

### [1:00–1:30] WHAT'S BUILT — The Prototype

*[Quick technical montage: multiplayer sync, video bubbles rendering, code editor, chat with AI responses]*

**ON CAMERA:**
"We already have a working prototype. Real-time multiplayer with position sync. Proximity-based video chat rendered inside the game engine. An AI tutor that joins the room as a live participant. And an in-game code editor with syntax highlighting and AI-powered code review.

This isn't a mockup — the hard technical challenges are solved. We've built the engine. Now we need to build the game."

### [1:30–2:15] THE PLAN — What $100k Buys

*[Show roadmap graphic or whiteboard]*

**ON CAMERA:**
"With Screen Australia's support, we'll take this prototype to a polished, playable demo at PAX Aus in October 2026.

Here's what that looks like:

**Phase 1** — April to June: Build the core game loop. A progression system that tracks your coding journey. Twenty coding challenges across beginner, intermediate, and advanced tiers. Enhanced AI tutoring with structured hints and feedback. Sound design to bring the world to life.

**Phase 2** — July to September: Polish for PAX. An onboarding tutorial. Achievement badges. New themed maps. Performance optimization across platforms.

**October: PAX Aus.** A playable demo on the show floor. Players pick up a laptop, walk into Tech World, and start coding together.

The budget is straightforward: 60% developer time, 12% art and sound, 8% PAX costs, and the rest on infrastructure, tools, and marketing."

### [2:15–2:45] WHY THIS MATTERS — Impact

**ON CAMERA:**
"There is no multiplayer game where coding is the core mechanic AND players are socially present with live video. Zachtronics proved coding puzzles make great games — but those are single-player. We're taking that concept multiplayer and social.

Tech World grew out of the 'Adventures In' meetup — a community of developers who learn together. This grant would take us from a community project to a real studio with a real product. It's a chance to show that grassroots Australian game development works."

### [2:45–3:00] CLOSE — The Ask

**ON CAMERA:**
"We're Enspyrco. We've built the prototype. The technical risks are behind us. We're asking for $100,000 to take Tech World from prototype to PAX Aus.

Thank you."

*[End card: Tech World logo, Enspyrco, website/contact]*

---

## 10. Application Timeline (Now → March 5)

### Week 1: February 15–21
- [x] **Feb 15:** Download SA templates (Production Plan .docx, Strategic Outcomes .docx, Finance Plan .xlsx)
- [x] **Feb 15:** Download Guidelines PDF, FAQs, Trends Report for reference
- [ ] **Feb 15:** Register/log in to SmartyGrants platform
- [ ] **Feb 16:** Bug-fix pass on prototype — ensure it's rock-solid for assessors
- [ ] **Feb 16:** Review Terms of Trade document, Screen Australia AI Guiding Principles
- [ ] **Feb 17:** Test prototype on a fresh machine/browser (simulate assessor experience)
- [ ] **Feb 17:** Confirm IP ownership is with Enspyrco Pty Ltd; seek legal advice if needed
- [ ] **Feb 18:** Prepare Prototype Details document (hardware reqs, setup instructions, controls)
- [ ] **Feb 18:** Consider building a curated "assessor demo" version of prototype
- [ ] **Feb 19:** Record 30-second gameplay footage video
- [ ] **Feb 20–21:** Draft Production Plan (7 pages, using SA template)

### Week 2: February 22–28
- [ ] **Feb 22–23:** Finalize Production Plan (include risk analysis, timeline with buffer, acceptance criteria)
- [ ] **Feb 24–25:** Write Strategic Outcomes document (6 pages, include marketing plan, accessibility plan)
- [ ] **Feb 25–26:** Complete Finance Plan & Budget spreadsheet (ALL funding sources, in-kind valuations)
- [ ] **Feb 26:** Gather letters of support from industry peers / meetup community
- [ ] **Feb 26:** Get letters of commitment from team members
- [ ] **Feb 27:** Record 3-minute pitch video (MP4, H.264, 720p, <200MB — plan, rehearse, allow re-takes)
- [ ] **Feb 28:** Compile team CVs

### Week 3: March 1–5
- [ ] **Mar 1:** Full application review — read through everything fresh
- [ ] **Mar 1:** Cross-check consistency: team members appear in application, budget, AND CVs; timeline consistent across all docs
- [ ] **Mar 2:** Have someone external review the application (fresh eyes)
- [ ] **Mar 3:** Incorporate feedback, finalize all documents
- [ ] **Mar 3:** Verify all cloud-hosted materials (prototype URL, any Drive/Dropbox links) are accessible and will remain so for 12 weeks
- [ ] **Mar 4:** Upload everything to SmartyGrants — test all downloads/links
- [ ] **Mar 5 (before 5pm AEDT):** Final submission — do NOT leave this to the last minute

### Critical Path Items
1. **SmartyGrants templates** — downloaded ✅ — use these exactly, don't deviate
2. **Prototype stability** — assessors WILL play it, it MUST work first try AND remain accessible for 12 weeks
3. **Pitch video** — highest-impact material, often the first thing assessors look at. Plan, rehearse, produce.
4. **Budget** — must be realistic, itemized, include ALL funding sources, and show fair compensation
5. **IP ownership** — must be clear and with the company before contracting
6. **Marketing plan** — competitive applications include competitor analysis, target audience, psychographics
7. **Consistency** — every document must tell the same story with the same numbers and names

---

## Appendix A: If Successful — Contracting Requirements

If funded, Screen Australia will send a Project Grant Agreement (PGA). Key requirements:
- **80% payment** on signing PGA, subject to:
  - Solicitor confirmation letter (brief letter confirming IP clearance advice — SA provides template)
  - Signed NFSA (National Film and Sound Archive) Deed sent to NFSA (SA provides template)
- **20% payment** on completion, subject to:
  - Second solicitor opinion (confirming all rights to deliver/exploit the game)
  - Approved Acquittal Report on SmartyGrants
  - Approved Cost Report in Finance Plan & Budget spreadsheet
- Must include **Screen Australia logo** in the game (per Credits Policy)
- Screen Australia does **not** take IP ownership, but requires written consent if you want to assign IP to a third party
- PGA General Terms are generally non-negotiable (per Terms of Trade)

## Appendix B: Useful Links

- [Games Production Fund guidelines](https://www.screenaustralia.gov.au/funding-and-support/online/games/games-production-fund)
- [SmartyGrants application portal](https://screenaustraliafunding.smartygrants.com.au/)
- [Screen Australia Terms of Trade](https://www.screenaustralia.gov.au/screen-australia/about-us/doing-business-with-us/terms-of-trade)
- [Screen Australia Credits Policy](https://www.screenaustralia.gov.au/screen-australia/about-us/doing-business-with-us/credits-policy)
- [Screen Australia Corporate Plan](https://www.screenaustralia.gov.au/screen-australia/about-us/corporate-documents/corporate-plan) (understand SA's values and objectives)
- [2024–2025 Games funding approvals](https://www.screenaustralia.gov.au/funding-and-support/online/funding-approvals/2024-2025-games-production) (see what got funded)
- [PAX Aus 2026](https://aus.paxsite.com/)
- [GCAP (Game Connect Asia Pacific)](https://gcap.com.au/)
- Screen Australia Games team: **1800 507 901** or email: games@screenaustralia.gov.au

### Downloaded Templates (in `docs/grant-application/templates/`)
- `Guidelines-Games-Production-Fund.pdf` — Full program guidelines (issued 03/10/2023, updated 14/11/2025)
- `Games-Production-Fund-FAQs.docx` — Frequently asked questions (updated 10 July 2025)
- `GPF-Trends-Report-(Feb-2025).pdf` — Trends report from August 2025 round
- `Game-Production-Fund-Template-Production-Plan-3-10-2023-issued.docx` — Production Plan template (7 pages max)
- `Games-Production-Fund-Template-Strategic-Outcomes.docx` — Strategic Outcomes template (6 pages max)
- `Games-Production-Fund-Template-Finance-Plan-and-Budget.xlsx` — Finance Plan & Budget spreadsheet
