# Screen Australia – Games: Strategic Outcomes

**Project title:** Tech World
**Studio:** Enspyrco Pty Ltd
**Strategic Outcomes prepared by:** [Your name]
**Strategic Outcomes date:** [DD/MM/2026]

---

## 1) Where you are now

### What is the current state of your project? What work on the project has already been done?

Tech World is a multiplayer 2D game in production, built with Flutter and the Flame engine. Players explore a shared virtual world, solve real coding challenges at terminal stations, collaborate via proximity-based video chat, and receive guidance from an AI companion called Clawd.

The project has been in active development since July 2024. The current prototype is fully playable on web (the lead platform), with additional support for macOS and iOS. It is deployed to Firebase Hosting with automated CI/CD via GitHub Actions.

**What has been built:**

- **Multiplayer game world:** Real-time player synchronisation via LiveKit data channels. Animated 8-directional player sprites with tap-to-move pathfinding (Jump Point Search) around barriers. 4 playable maps with grid-based navigation and customisable layouts.
- **Proximity-based video chat:** When two players walk within 3 grid squares of each other, their live video feeds appear as circular bubbles inside the game world. Uses zero-copy FFI frame capture on macOS and GPU-efficient ImageBitmap rendering on web. Camera and microphone controls.
- **AI tutor (Clawd):** A bot powered by the Claude API that joins the game room as a live participant. Players can ask questions, submit code for review, and receive structured feedback. Supports text-to-speech (Clawd speaks responses aloud) and speech-to-text (players can speak instead of typing).
- **In-game code editor:** Terminal stations placed on maps that players interact with to open a code editor panel. Dart syntax highlighting, 3 starter coding challenges (Hello Dart, Sum a List, FizzBuzz), and AI-powered code review on submission.
- **Authentication & infrastructure:** Firebase Auth (email/password, Google, Apple Sign-In). LiveKit token generation via Firebase Cloud Function. Automated deployment to Firebase Hosting on merge to main. Loading screen with progress stages.

**Development metrics:** 85+ pull requests merged. ~10,000 lines of production Dart code. ~5,800 lines of tests across 34 test files. CI pipeline enforces static analysis and test coverage on every PR.

### What are the current strengths of the project? What are the current challenges or weaknesses?

**Strengths:**

- **The hard technical problems are solved.** Real-time multiplayer synchronisation, in-engine video rendering via WebRTC, and AI bot integration as a live participant are all shipped and working across platforms. These were the highest-risk, highest-complexity challenges, and they are behind us.
- **Unique genre intersection.** No existing game combines real coding challenges as the core gameplay mechanic with live multiplayer video presence and an AI tutor companion. Tech World sits at an unoccupied intersection of Zachtronics-style coding puzzles, social virtual worlds, and AI-assisted learning.
- **Production-grade engineering practices.** Git-based version control with branch protection. Automated CI/CD with analysis and test coverage enforcement. Clean, well-documented codebase. This is not a prototype held together with tape — it is a production codebase ready to scale.
- **Open-source technology stack.** Flutter, Flame, and LiveKit are all open-source. No dependency on proprietary engines or platforms that could introduce licensing risk or vendor lock-in.
- **Web-first accessibility.** Players need only a modern browser — no downloads, no expensive hardware, no app store approval. This dramatically lowers the barrier to entry for both players and event demos.

**Challenges / weaknesses:**

- **Content volume.** The prototype has 3 coding challenges. A compelling demo needs 20+ across multiple difficulty tiers. Creating well-designed challenges with balanced difficulty and quality AI feedback is the primary content production task.
- **Progression and retention.** There is no progression system yet — no completion tracking, no scores, no sense of journey. Players can solve challenges but have no reason to come back. This is the most important game design gap.
- **Audio.** The game is currently silent. Sound design (ambient music, interaction SFX, feedback sounds) is essential to game feel and is entirely missing.
- **Onboarding.** A new player dropped into the world has no guidance on what to do or where to go. A tutorial or guided first experience is needed.
- **Visual polish.** The UI is functional but not polished. Menus, transitions, and responsive layout need a refinement pass.

These weaknesses are all **content and polish** problems — they are well-understood, plannable work. None require technical R&D or carry significant execution risk.

### Who is on the team? What appropriate experience do they have to execute your plans?

[Name, Role — Lead Developer & Creative Director]
[Brief bio: relevant experience in software development, game development, Flutter/Dart expertise, etc. Highlight shipped products, professional experience, years of experience.]

[Name, Role — if applicable]
[Brief bio]

[Note: Keep this section factual and concise. The Trends Report notes that team size should match budget and SmartyGrants form. If the team is 1–2 people, that's fine for this funding level — own it and demonstrate that the remaining work is within capacity.]

### Why do you, as a gamemaker, want to make this game? Why is this project important to you? How will it expand, deepen, or diversify your creative practice?

[This section should be deeply personal and authentic. Do NOT use AI-generated language here — assessors can tell. Write this yourself. Some angles to consider:]

[The gap you see: coding is one of the most creative and empowering skills a person can learn, but most people's first experience of it is lonely — a tutorial, a blank screen, silence. Tech World is built on the conviction that coding should feel social, playful, and human.]

[Your creative practice: this project pushes your practice into new territory — game design, real-time multiplayer systems, AI integration, and the intersection of education and entertainment. It represents a deliberate move from [previous work] into interactive entertainment.]

[The transition: Enspyrco started as a vehicle for community-driven development. This grant represents the transition to a focused studio with a commercial product. The creative ambition has outgrown the community context, and Tech World deserves dedicated resources to reach its potential.]

### Diversity, equity, and inclusion plan

**Current state of the team:**
[Describe the team's composition honestly. Note any relevant diversity dimensions — gender, cultural background, disability, age, geographic location, etc. If the team is not diverse, acknowledge this directly rather than leaving it unaddressed.]

**Current state of the project:**
Tech World is designed to make coding accessible to people who might not see themselves as "coders." The game wraps coding in a social, game-like experience that removes the intimidation of a blank IDE. Key accessibility features already built:
- Voice input (speech-to-text) and voice output (text-to-speech) for players who prefer not to type
- Web-first design — no expensive hardware, downloads, or app store accounts required
- Shared AI tutor visible to all players — no one has to ask for help privately

**Plans to develop in these areas:**
- **Accessibility features (budgeted, M4 — Aug–Sep 2026):** Keyboard-only navigation, configurable text sizes, color-blind-friendly UI palette. Budget allocation: included in developer time and contractor/specialist line item (accessibility audit).
- **Playtesting diversity:** Recruit playtesters across age groups, coding experience levels, and backgrounds. Collect demographic data (with consent) alongside gameplay feedback to identify barriers.
- **Challenge design inclusivity:** Ensure coding challenges don't assume prior knowledge beyond what's taught in-game. Avoid cultural references that exclude non-English-speaking backgrounds (code is in English/Dart, but narrative framing should be universal).

**Measurable progress indicators (for acquittal reporting):**
- Accessibility audit completed and findings addressed (Y/N, with report)
- Number of playtest participants and demographic breakdown
- Percentage of accessibility checklist items implemented (keyboard nav, text sizing, colour contrast)
- Player feedback scores on "ease of getting started" across different experience levels

---

## 2) Where you want to be

### What are your studio goals?

Enspyrco's goal is to become a sustainable Australian independent game studio that creates games where coding is the core mechanic. Tech World is the studio's debut title and the foundation for this vision.

**Short-term (12 months):** Deliver a polished, playable demo of Tech World at PAX Aus October 2026. Use the event to validate the concept with a broad audience, build a wishlist base, and establish the studio's presence in the Australian games community.

**Medium-term (2–3 years):** Release Tech World on Steam as an Early Access title. Grow the player community. Expand the game with additional content (more challenges, maps, game modes). Generate revenue through premium sales (no microtransactions, no pay-to-win).

**Long-term:** Establish Enspyrco as a recognised studio in the "coding games" genre. Explore additional titles that use real programming as a gameplay mechanic. Contribute to the Australian games industry by demonstrating that Flutter/Flame is a viable game engine and that open-source toolchains can produce competitive indie titles.

### What significant milestone are you currently working towards for the game?

**Playable public demo at PAX Aus 2026 (October 9–11, Melbourne Convention Centre)** with:
- 20 coding challenges across beginner, intermediate, and advanced difficulty tiers
- A progression system tracking challenge completion, scores, and player journey
- Enhanced AI tutoring with structured hints, graded feedback, and code review
- Sound design (ambient music, interaction SFX, notification sounds)
- 2 new themed maps
- Onboarding tutorial for new players
- Accessibility features (keyboard navigation, text sizing, colour contrast)

This aligns with Screen Australia's supported milestone: *"Completion of a demo to present at a physical event."*

### Why are you working towards this milestone? How will you measure whether you have achieved it? How will this milestone further your studio goals?

**Why PAX Aus:** PAX Australia is the largest gaming event in the southern hemisphere. It provides direct player feedback, media coverage, publisher visibility, and community validation — all of which are essential for an indie studio's first public showing. GCAP (Game Connect Asia Pacific), held the same week, provides access to the Australian developer and publisher network.

**How we will measure success:**
- Demo exhibited for all 3 days of PAX Aus (Oct 9–11, 2026)
- Minimum 50 player feedback responses collected at the event
- Steam page live with wishlist collection active
- Post-event media coverage or social media engagement metrics
- Qualitative: players can pick up the game, complete at least one challenge, and have a positive experience without developer assistance

**How this furthers studio goals:** A successful PAX demo validates the concept with real players, generates a wishlist base for an Early Access launch, and establishes Enspyrco in the Australian games community. It provides the evidence needed to pursue further funding, publisher interest, or self-funded development toward release.

---

## 3) How this funding and project will help you get there

### How do you plan to address the project's challenges or weaknesses you have identified?

| Weakness | Plan | Timeline |
|---|---|---|
| **Content volume** (3 challenges → 20) | Design and implement 17 new challenges across 3 difficulty tiers. Each challenge includes: problem description, starter code, AI review rubric, structured hints. | Apr–Aug 2026 |
| **Progression system** | Build challenge completion tracking, scoring, and a visual progress indicator. Persist state via Firebase so players can return and continue. | Apr–Jun 2026 |
| **Audio** | Commission ambient music tracks and interaction SFX from an Australian sound designer. Integrate with Flame audio system. Player-controllable volume/mute. | May–Jun 2026 |
| **Onboarding** | Guided first-time experience: walk player through movement, terminal interaction, challenge solving, and chat. Triggered on first login, skippable for returning players. | Jul–Aug 2026 |
| **Visual polish** | UI/UX refinement pass: improved menus, transitions, responsive layout for different screen sizes. Consistent visual language across all screens. | Aug–Sep 2026 |

### Why is Screen Australia funding necessary to help you achieve your goal?

Without funding, Tech World remains a spare-time project with no fixed timeline. The technical foundation is strong, but the content, polish, and event presence required to reach PAX Aus in October 2026 cannot be achieved on evenings and weekends alone.

Screen Australia funding enables:
- **Dedicated development time** — the lead developer can commit focused hours to the project rather than fitting it around other work. Developer wages represent 60% of the budget.
- **Professional art and sound** — commissioned audio and visual assets from Australian creatives, elevating the game from functional prototype to polished demo.
- **PAX Aus presence** — exhibitor booth, travel, accommodation, and signage. Without funding, attending PAX as an exhibitor is not financially viable.
- **Specialist input** — UX review, accessibility audit, and structured playtesting with external participants.

The grant transforms a strong prototype into a demo-ready product with a fixed, achievable deadline.

### What are your plans for next steps following completion of the grant period, and the completion of the project?

**After the grant period (post-PAX, late 2026–2027):**
- Analyse PAX player feedback and iterate on the game based on findings
- Expand content: additional challenges, maps, and game modes informed by player data
- Pursue Early Access release on Steam (target: mid-2027)
- Explore further funding: state screen agency grants (e.g. Film Victoria), publisher interest generated at PAX/GCAP, or self-funding from early sales

**After the project (post-release):**
- Ongoing content updates (new challenges, community-requested features)
- Explore additional platforms if demand warrants (mobile, console)
- Build toward a sustainable studio: revenue from sales funds ongoing development
- Contribute to the Australian game dev community: open-source components of the engine/framework where possible, share learnings at events and in developer communities

---

## 4a) Commercial Strategy

### Monetisation

Tech World will be a **premium title** — a one-time purchase with no microtransactions, loot boxes, subscriptions, or pay-to-win mechanics. Estimated pricing: **$15–$25 AUD**, informed by comparable indie titles in the puzzle/education genre.

All game content (challenges, maps, AI tutor access) is included in the base purchase. Future content updates will be free for existing owners. This aligns with player expectations in the indie puzzle space.

**Cost structure and sustainability:**

Tech World has ongoing server costs (multiplayer infrastructure, AI tutor API) that a typical single-player indie game does not. We have designed the architecture specifically to minimise these:

| Cost | Approach | Estimated monthly cost |
|---|---|---|
| **Multiplayer infrastructure (LiveKit)** | Self-hosted on Oracle Cloud Infrastructure (OCI) Always-Free tier: 4 ARM OCPUs, 24GB RAM — sufficient for ~50 concurrent players. LiveKit is open-source with no licensing fees. | **$0** |
| **AI tutor (Claude API)** | Uses Claude 3.5 Haiku (~$0.002 per interaction). Shared chat model means one AI response serves all players in a room, so costs scale per-message not per-player. | **$20–200** (scales with usage) |
| **Hosting & auth (Firebase)** | Web app on Firebase Hosting free tier. Firebase Auth free tier covers thousands of users. Cloud Functions free tier for token generation. | **$0–20** |
| **Total running costs** | | **~$20–220/month** at 100–500 daily active users |

At $20 AUD per copy ($14 net after Steam's 30% cut), the game reaches **operational break-even at approximately 7–15 sales per month** — a very low threshold for sustainability.

**Additional cost management strategies:**
- Shared chat architecture already reduces API calls (one response visible to all players in a room, not per-player)
- Response caching for frequently asked questions
- Tiered AI access: basic code validation handled client-side, Claude reserved for nuanced feedback and conversation
- Free web demo with limited AI interactions; full AI tutor access in the Steam purchase
- If player volume exceeds OCI free tier capacity, revenue from sales funds infrastructure scaling (LiveKit self-hosting costs ~$20–50/month on a paid VPS at the next tier)

### Audience

**Primary audience:** Adults (18–35) who are curious about coding but find traditional learning methods (tutorials, bootcamps, MOOCs) isolating or intimidating. They enjoy indie games, puzzle games, and social gaming experiences. They are not necessarily "gamers" in the traditional sense — they might play Wordle, Stardew Valley, or Among Us, but are drawn to games that feel meaningful rather than purely competitive.

**Secondary audience:** Existing programmers (hobbyist or professional) who enjoy coding puzzles as entertainment. Fans of Zachtronics games (TIS-100, Shenzhen I/O, Opus Magnum), Screeps, or Bitburner who want a more social, collaborative experience.

**Tertiary audience:** Educators and coding community organisers looking for engaging group activities. While Tech World is NOT an educational platform (it is a consumer game), its multiplayer coding mechanics make it naturally suitable for meetups, classrooms, and workshops.

**Player psychographics (Bartle taxonomy):** Tech World appeals primarily to **Explorers** (curiosity-driven, enjoy discovering mechanics and solutions) and **Socialisers** (play for the social interaction, collaboration, and shared experience). The game's design — open world exploration, proximity-based social features, cooperative problem-solving — is built around these motivations.

**How we plan to reach them:**
- **Steam** as the primary storefront and discovery platform (tags: Indie, Puzzle, Education, Multiplayer, Programming)
- **Developer communities:** Reddit (r/learnprogramming, r/indiegaming, r/gamedev), Hacker News, dev-focused Discord servers, coding meetup networks
- **Content creators:** Reach out to YouTube/Twitch creators who cover indie puzzle games, coding content, or "cozy" multiplayer games
- **Events:** PAX Aus (consumer), GCAP (industry), Freeplay (Melbourne indie festival)
- **Web build as a free demo:** The web-first architecture means we can offer a free browser demo with limited challenges, with the full game on Steam. This dramatically lowers the try-before-you-buy barrier.

### Positioning

Tech World occupies a unique position at the intersection of three established genres:

| Comparable | What they do well | What Tech World adds |
|---|---|---|
| **Zachtronics** (TIS-100, Opus Magnum, Shenzhen I/O) | Proved that real coding/logic puzzles make compelling, critically acclaimed indie games. Dedicated fanbase. | Multiplayer. Social presence. AI tutor. These are single-player experiences — Tech World makes coding puzzles social. |
| **CodeCombat / Codecademy / freeCodeCamp** | Coding education with gamified elements. Large user bases. | It's actually a *game*. Not a gamified tutorial — a world you explore with other people, where coding is the mechanic, not the curriculum. |
| **Among Us / Rec Room / VRChat** | Social multiplayer experiences with casual mechanics. Massive audiences. | Structured gameplay. Coding challenges give the social experience a purpose beyond hanging out. Progression and mastery. |

**Differentiation statement:** Tech World is the first multiplayer game where writing real code is the core gameplay mechanic AND players share social presence through live video. No existing title combines all three elements.

### Publishing & Investment

We are not currently seeking a publisher. The scope of Tech World (indie, niche genre, small team) is well-suited to self-publishing on Steam. The web-first architecture also enables direct distribution via the studio's own hosting.

If publisher interest arises from PAX Aus or GCAP networking, we would consider partnerships that offer **marketing and distribution support** without requiring IP assignment. Per Screen Australia's Terms of Trade, we intend to retain full IP ownership.

We are open to further grant funding from state screen agencies (e.g. Film Victoria, Create NSW) to support post-demo development toward Early Access release.

### Promotional and discoverability strategy

Our promotional strategy is phased to match the development timeline:

**Phase 1 — Build foundations (May–Jul 2026):**
- Create Steam store page with trailer, screenshots, and genre tags
- Begin wishlist collection
- Establish social media presence (X/Twitter, Reddit, relevant Discord communities)
- Start monthly dev log series on Steam and social media

**Phase 2 — Build momentum (Aug–Sep 2026):**
- Release announcement trailer (60 seconds, focused on the unique multiplayer coding experience)
- Announce PAX Aus presence
- Reach out to indie game content creators for coverage
- Prepare and distribute press kit
- Post gameplay GIFs and short clips regularly on social channels

**Phase 3 — PAX and beyond (Oct 2026+):**
- PAX Aus demo — direct player engagement, feedback collection, email signups
- GCAP networking — industry and publisher connections
- Post-PAX content: recap dev log, player testimonial clips, event footage
- Submit to Australian indie game showcases (Freeplay Awards, AGDAs if eligible)

**Budget allocation:** $4,000 (4% of grant) allocated to marketing — trailer production, social media promotion, press kit design, and PAX-related promotional materials. The majority of promotional work (dev logs, social media, community engagement) is handled by the team directly.

**Scope and viability:** This strategy is deliberately modest. We are not planning paid advertising campaigns or influencer sponsorships at this stage. Our audience discovery relies on organic channels (Steam discovery, Reddit, dev communities, events) that are well-suited to a niche indie title. A larger marketing push would be appropriate closer to Early Access launch, funded by early sales revenue or additional grants.

---

## 4b) Cultural Strategy

### Awards / Showcases

We plan to submit Tech World to the following awards and showcases, selected for their relevance to Australian indie games and the coding/education intersection:

| Award / Showcase | Why | Target Date |
|---|---|---|
| **Freeplay Awards** (Melbourne) | Australia's longest-running indie games festival. Celebrates experimental and culturally significant Australian games. Tech World's unique mechanic (real coding as gameplay) aligns with Freeplay's focus on games that push boundaries. | 2027 submission (post-PAX) |
| **Australian Game Developer Awards (AGDAs)** | The premier Australian game industry awards. Categories include Excellence in Gameplay, Excellence in Design, and Best Indie Game. Strong visibility within the Australian industry. | 2027 submission |
| **IGF (Independent Games Festival)** | The most prestigious international indie award. Categories include the Nuovo Award (experimental/innovative games) and Excellence in Design. Tech World's genre-defying combination of coding, multiplayer video, and AI tutoring is a strong fit for Nuovo. | Jan 2027 submission (GDC Mar 2027) |
| **Day of the Devs** | Curated indie showcase focused on unique and visually distinctive games. High media visibility. | 2027 (if accepted) |
| **IndieCade** | International indie festival celebrating innovation. Known for highlighting games that blur the line between art, education, and entertainment. | 2027 submission |
| **SXSW Gaming Awards** | Broad audience, strong media presence, categories for innovation and indie games. | 2027 submission |

Submission timing: Most award submissions require a playable build, which the PAX Aus demo (October 2026) will provide. The post-PAX period (November 2026 – January 2027) is the natural window for preparing award submissions.

### Who is your intended audience? How do you plan to reach them?

Beyond the commercial audience described in 4a, Tech World has cultural reach into communities that don't typically engage with traditional games:

- **Coding education communities:** Coding bootcamps, university CS departments, and self-taught developer networks. These communities value tools that make learning social and engaging. Tech World isn't a learning tool — it's a game — but its mechanics naturally serve this audience.
- **Australian indie game community:** Developers, critics, and players who follow the Australian indie scene through Freeplay, GCAP, ACMI, and local meetups. Tech World contributes a new genre to the Australian games landscape.
- **Creative technology audiences:** People interested in the intersection of art, technology, and play. Festivals like Freeplay, IndieCade, and A MAZE. attract this audience.

We reach them through: event presence (PAX, GCAP, Freeplay), award submissions, dev community engagement (talks, dev logs, open-source contributions), and the free web demo as a zero-barrier entry point.

### Cultural institutions

| Institution | Plan | Rationale |
|---|---|---|
| **ACMI (Australian Centre for the Moving Image)** | Approach for potential exhibition or event inclusion. ACMI has a history of showcasing Australian games and interactive media. | Melbourne-based, directly relevant to Australian game culture. Has hosted game exhibitions and interactive installations. |
| **Freeplay** | Submit for festival showcase and awards. Attend and present if accepted. | Australia's most important indie games festival. Celebrates games as culture. |
| **Museum of Applied Arts and Sciences (Powerhouse)** | Exploratory approach for their digital/interactive programs. | Sydney-based, has featured interactive and educational technology exhibitions. |
| **State Library of Victoria** | Exploratory approach for their digital learning and community programs. | Hosts coding workshops and digital literacy events — Tech World could feature as a live, social coding experience. |

These are exploratory goals, not confirmed partnerships. We would approach institutions after the PAX demo provides a polished, publicly validated build.

### Why is this project timely and relevant to your creative practice?

[This section should be written personally — see notes in section 1. Some angles:]

[The convergence of three technologies — real-time multiplayer (LiveKit/WebRTC), large language models (Claude), and cross-platform game engines (Flutter/Flame) — makes Tech World possible now in a way it wasn't two years ago. The AI tutor isn't a gimmick; it's a genuine creative partner that responds intelligently to player-written code. This is a new creative frontier for game design.]

[As a developer, this project represents a deliberate creative expansion from software engineering into game design, interactive storytelling, and player experience design. It's a bridge between two practices.]

### Why is it timely and relevant for your team to be making this project now?

The timing is driven by three converging factors:

**1. Technology readiness.** The tools required to build Tech World — real-time multiplayer via WebRTC (LiveKit), AI-powered game characters via large language models (Claude API), and cross-platform game development via Flutter/Flame — have all matured to production quality within the last 18 months. Two years ago, building an AI tutor that gives meaningful code feedback in real time was not economically feasible. Today, models like Claude 3.5 Haiku deliver high-quality responses at ~$0.002 per interaction. The cost curve has made AI-native game design viable for indie studios.

**2. Cultural moment for coding.** Public interest in coding literacy is at an all-time high, driven by the visibility of AI tools (ChatGPT, Copilot, Claude) and the growing recognition that understanding code is a form of creative and economic empowerment. Yet the dominant entry points — tutorials, bootcamps, MOOCs — remain isolating and drop-off rates are high. There is a clear gap for a social, game-based approach that makes coding feel playful rather than academic.

**3. Australian indie games momentum.** The Australian indie scene is thriving — Untitled Goose Game, Hollow Knight, Cult of the Lamb, and others have demonstrated that Australian studios can produce globally competitive titles. Screen Australia's investment in the Games Production Fund reflects this momentum. Tech World contributes something new to the landscape: an open-source technology stack (Flutter/Flame instead of Unity/Unreal) and a genre (multiplayer coding) that no Australian studio has explored. This is a chance to expand what "Australian indie game" means.
