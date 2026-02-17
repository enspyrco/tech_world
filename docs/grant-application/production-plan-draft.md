# Screen Australia – Games: Production Plan

**Project title:** Tech World
**Studio:** Enspyrco Pty Ltd
**Production Plan prepared by:** [Your name]
**Production Plan date:** [DD/MM/2026]

---

## 1) Key Information

| Item | Response |
|---|---|
| **Lead development platform** | Web (browser-based, hosted on Firebase Hosting) |
| **Additional development platform(s)** | macOS, iOS. Android support in codebase but not a release target for this milestone. |
| **Project start date** | July 2024 (current architecture; initial prototyping from June 2023) |
| **Production stage** | Production |
| **Game engine** | Flame 1.x (Flutter game engine) with Flutter SDK |
| **Version control** | Git, hosted on GitHub with branch protection, pull request reviews, and CI/CD (GitHub Actions) |
| **Pipeline overview** | **Engine:** Flutter + Flame (Dart). **Multiplayer & comms:** LiveKit (data channels for positions/chat, WebRTC for video/audio). No separate game server. **AI tutor:** Claude API via Node.js bot service (`@livekit/agents`). **Backend:** Firebase (Auth, Hosting, Cloud Functions). **Hosting:** Firebase Hosting (web), GCP Compute Engine (bot service). **CI/CD:** GitHub Actions running `flutter analyze` and `flutter test` with 45% coverage threshold on every PR; docs-only changes skip CI. **Art:** Pixel art sprites (8-directional animation), background PNGs with wall occlusion. **Code editor:** `code_forge_web` package with `re_highlight` for syntax highlighting. **Map editor:** Custom paint tools with ASCII import/export and live preview. **Voice:** Web Speech API for TTS/STT (web only). |
| **Release languages** | English (primary). No localisation planned for this milestone. The game's core mechanic (writing Dart code) is inherently English-language, so localisation of UI chrome would have limited impact at this stage. |
| **Voiceover** | No recorded voiceover. The AI tutor (Clawd) uses browser text-to-speech (Web Speech API) for spoken responses. Players can use speech-to-text for voice input. No voice actors required. |
| **Number of players** | Multiplayer online. Designed for 2–50 concurrent players per room. Players share a persistent game world and can see, hear, and collaborate with nearby players in real time. 6 maps with runtime switching. |
| **Game genre(s)** | Indie, Puzzle, Education, Multiplayer, Casual |
| **List of game modes** | **Exploration mode:** Free movement through the game world (6 maps, runtime switching), proximity-based video chat with other players, chat with AI tutor via text or voice. **Challenge mode:** 23 coding challenges across 3 difficulty tiers at terminal stations — write real Dart code, submit for AI review. **Map editor mode:** Paint custom maps with barriers, spawn points, and terminals on a 50x50 grid with live preview. (Single unified experience, not separate selectable modes.) |
| **Live Operations** | No traditional live ops (no seasonal content, battle passes, or live events). Post-release content updates planned (new challenges, maps) but these are standard patches, not live service operations. Server infrastructure (LiveKit, Firebase) requires ongoing maintenance. |
| **Online Social Features** | Yes. **In-game text chat** visible to all players in the room. **Proximity-based video/audio chat** via WebRTC — when two players are within 3 grid squares, their live video appears as circular bubbles in the game world. **AI tutor chat** — shared conversation with Clawd (Claude-powered bot) visible to all participants. No integration with external social/streaming platforms at this stage. |
| **Team Size** | [X — confirm exact number. Aimed at 1–3 core members per FAQs guidance. Ensure this matches SmartyGrants form and budget.] |

---

## 2) Promotional Activities Schedule

| Activity | Key Dates | Team Member(s) Responsible | Description of Activity |
|---|---|---|---|
| Gameplay capture & trailer assets | Apr 2026 | [Name] | Record polished gameplay footage for promotional use — multiplayer sessions, challenge solving, video chat, AI tutor interaction. Build a library of screenshots and short clips. |
| Steam page creation | May 2026 | [Name] | Create Steam store page with trailer, screenshots, description, and genre tags. Begin collecting wishlists. Position as "multiplayer coding adventure" in Indie/Puzzle/Education categories. |
| Dev log series | May–Sep 2026 | [Name] | Monthly dev log posts on Steam and social media documenting development progress, technical insights, and community feedback. Build audience and demonstrate momentum. |
| Social media presence | May–Oct 2026 | [Name] | Regular posts on X/Twitter, Reddit (r/indiegaming, r/gamedev, r/learnprogramming), and relevant Discord communities. Short gameplay clips, GIFs, and progress updates. |
| Create announcement trailer | Aug 2026 | [Name] | 60-second trailer showing the core gameplay loop — exploring, solving challenges, collaborating with other players via video, chatting with Clawd. Focus on what makes the experience unique. |
| PAX Aus announcement | Aug 2026 | [Name] | Announce PAX Aus presence via social channels and Steam dev log. |
| Press kit preparation | Sep 2026 | [Name] | Prepare downloadable press kit: high-res screenshots, trailer, logo, one-sheet, key art, studio bio, contact info. |
| GCAP attendance | Early Oct 2026 | [Name] | Attend Game Connect Asia Pacific (developer conference, same week as PAX). Network with publishers, media, and other Australian developers. |
| PAX Aus demo | Oct 9–11, 2026 | [Name] | Playable demo on the show floor. Players experience the full loop: enter the world, meet other players, solve coding challenges, interact with Clawd. Collect player feedback and email signups. |
| Post-PAX recap | Oct 2026 | [Name] | Dev log covering PAX experience, player feedback, media coverage, and next steps. |

---

## 3) Due Diligence

### a) Risk Assessment and Mitigation Strategies

| Risk | Likelihood | Mitigation Strategy |
|---|---|---|
| **LiveKit service disruption** — multiplayer and video chat depend on LiveKit infrastructure | Low | LiveKit is open-source and can be self-hosted. Currently on LiveKit Cloud; migration to self-hosted instance on OCI/GCP is documented and can be executed within 1 week if needed. No vendor lock-in. |
| **AI API cost escalation** — Clawd uses Claude API, costs could increase with player volume | Medium | Currently using Claude 3.5 Haiku (cost-effective model). Responses are shared across all players in a room (not per-player). Can implement rate limiting, response caching, or switch to smaller models if costs exceed budget. Bot architecture is model-agnostic. |
| **PAX Aus booth availability** — exhibitor spots may sell out or be unavailable | Medium | Submit PAX exhibitor application as early as possible (applications typically open mid-year). If booth unavailable, alternative: attend as visitors with portable demo laptops for informal showcasing, or target GCAP developer showcase instead. Also exploring other Australian indie events (Freeplay, AVCON). |
| **Team capacity constraints** — small team with ambitious milestone | Medium | Scope is deliberately conservative: remaining work is content and polish, not R&D. All technically complex features (multiplayer sync, video rendering, AI integration, cross-platform) are already shipped. Milestone tasks have buffer time built in. Can cut lower-priority features (LSP integration, achievements) without affecting core demo quality. |
| **Cross-platform compatibility issues** — web is primary but macOS/iOS also supported | Low | CI/CD pipeline runs analysis and tests on every PR. Web is the lead platform and primary assessor/PAX experience. macOS and iOS are secondary and can be deprioritised if issues arise without affecting the milestone. |
| **Prototype instability during 12-week assessment** — assessors need reliable access | Low | Web build auto-deploys to Firebase Hosting (Google infrastructure, 99.95% SLA). LiveKit room and bot service on GCP Compute Engine with PM2 process management. Monitoring alerts in place. Will conduct stability testing before submission and set up uptime monitoring for the assessment period. |
| **Player safety in social features** — video chat and text chat carry moderation risk | Medium | See Community Safety Plan in section 3c. Proximity-gated video (must be within 3 squares), room-based sessions (not open matchmaking), and AI tutor is the only non-human participant. No anonymous access — Firebase Auth required. |
| **Content scope creep** — pressure to add more features beyond milestone | Low | Milestone is clearly scoped: 20 challenges, progression system, AI tutoring enhancements, sound design, 2 new maps, onboarding tutorial, and PAX demo. Features are prioritised and lower-priority items (LSP, achievements) are explicitly marked as stretch goals that can be cut. |

### b) Live Operations

N/A — Tech World does not feature live operations. Content updates (new challenges, maps) will be deployed as standard application updates via Firebase Hosting. No seasonal content, battle passes, or live service mechanics.

### c) Social Features — Community Safety Plan

Tech World includes real-time text chat, proximity-based video/audio chat, and an AI tutor conversation. Our community safety approach:

**Access control:** All players must authenticate via Firebase Auth (email/password, Google, or Apple Sign-In). No anonymous access. This provides identity accountability and the ability to ban accounts.

**Proximity-gated video:** Video and audio streams only activate when two players are within 3 grid squares of each other. Players can move away to end a video connection at any time. Camera and microphone can be toggled off independently.

**Room-based sessions:** Players join rooms based on the current map. Rooms are not open matchmaking — players share a room URL or join the default room. This naturally limits exposure to known groups or small player counts.

**AI tutor moderation:** Clawd (the AI tutor) is powered by Claude, which has built-in content safety filters. Player messages to Clawd are visible to all participants in the room, providing social accountability.

**Reporting and moderation:** For the PAX demo milestone, moderation will be handled by the development team directly (small, known player base). Before any public release, we will implement: a report/block function, server-side chat logging for review, and a code of conduct. These are scoped as post-milestone work.

**Minors:** The game does not specifically target minors, but coding challenges are suitable for all ages. Video chat features will include clear consent prompts. Privacy policy (see 3d) will address data handling for users under 18.

### d) Privacy Policy

Tech World collects the following player data:
- **Authentication data:** Email address and display name via Firebase Auth (Google/Apple SSO or email/password). Stored and managed by Firebase, subject to Google's privacy policies.
- **Position data:** Player coordinates broadcast via LiveKit data channels. Ephemeral — not stored after session ends.
- **Chat messages:** Text messages sent in-room. Currently ephemeral (not persisted). If chat logging is added for moderation, a retention policy will be established.
- **Video/audio streams:** Processed by LiveKit. Not recorded or stored by Tech World.

No analytics or tracking SDKs are currently integrated. If analytics are added (e.g. for playtesting data), players will be informed and consent obtained.

A formal privacy policy will be published to the Firebase Hosting domain before any public release. For the PAX demo, a privacy notice will be displayed at the demo station.

[Link to privacy policy — to be created before public release]

---

## 4) Milestones – Game Development

| Milestone Name | Start Date | End Date | Key Tasks | Team Member(s) Responsible | Acceptance Criteria |
|---|---|---|---|---|---|
| **Close of Contracting** | [Expected ~Jun 2026] | [~Jun 2026] | Sign PGA, provide solicitor letter, send NFSA Deed | [Name] | PGA fully executed. Solicitor letter and NFSA Deed submitted. 80% payment received. |
| **M1: Game Loop & Persistence** | Apr 2026 | Jun 2026 | Progression system (challenge completion tracking, scores, stars). Challenge persistence (save/resume via Firebase). Enhanced Clawd tutoring (structured hints, grading rubric, difficulty-aware feedback). "I'm stuck" button with guided hints. | [Name] | Players can complete challenges, see their progress saved across sessions, and receive structured feedback from Clawd. All 23 existing challenges have completion tracking. Progression state persists in Firebase. |
| **M2: Sound Design** | May 2026 | Jun 2026 | Ambient music, interaction SFX (movement, terminal open, challenge submit, chat receive), chat notification sounds. Volume/mute UI control. | [Name] | Game has ambient audio and SFX for key interactions. Audio can be muted via UI control. Sound enhances game feel without being intrusive. |
| **M3: Onboarding & Rewards** | Jul 2026 | Aug 2026 | Onboarding tutorial (guided first-time experience). Points and rewards system (badges, achievements for milestones). Challenge difficulty balancing based on playtesting. | [Name] | New player can complete onboarding without external instruction. Players earn points/badges for completed challenges. Difficulty curve validated through at least 5 playtest sessions. |
| **M4: Polish & Accessibility** | Aug 2026 | Sep 2026 | UI/UX polish pass (menus, transitions). Keyboard-only navigation. Configurable text sizes. Color-blind-friendly palette. Performance optimisation and cross-platform testing. Screen Australia logo integration. | [Name] | Game passes accessibility checklist (keyboard nav, text sizing, colour contrast). Runs at stable 60fps on target hardware. SA logo displayed per Credits Policy. |
| **M5: PAX Aus Preparation** | Sep 2026 | Oct 2026 | PAX demo build (curated experience for show floor). Demo station setup documentation. Collect gameplay footage for post-event marketing. Prepare feedback collection mechanism. | [Name] | Standalone demo build tested on PAX hardware. Demo runs reliably for 3-day event without intervention. Setup can be completed by non-developer in under 10 minutes. |
| **M6: PAX Aus Demo (Event)** | Oct 9, 2026 | Oct 11, 2026 | Exhibit at PAX Aus. Collect player feedback. Network at GCAP. | [Name] | Demo exhibited at PAX Aus for all 3 days. Player feedback collected (minimum 50 responses). |
| **Delivery Date** | Nov 2026 | Nov 2026 | Final Cost Report. Acquittal report on SmartyGrants. Second solicitor opinion. Delivery materials per PGA. | [Name] | All delivery materials approved by Screen Australia. Final 20% payment received. |

**Buffer:** Each milestone includes approximately 2 weeks of buffer time within its date range. M1–M2 overlap intentionally (sound design is parallelisable with game loop work). Lower-priority features (LSP integration, procedural map generation, map sharing) are explicitly excluded from milestones and will only be pursued if the team is ahead of schedule. The content foundation — 23 challenges across 3 tiers, 6 maps with runtime switching, map editor, voice services, wall occlusion — is already shipped, significantly de-risking the timeline.

---

## 5) Project Timeline

|  | 2026 | | | | | | | | | | |
|---|---|---|---|---|---|---|---|---|---|---|---|
|  | **A** | **M** | **J** | **J** | **A** | **S** | **O** | **N** | **D** | | |
| **Funding Milestones** | | | ▼ Close of Contract | | | | | ▼ Delivery | | | |
| | | | | | | | | | | | |
| **Key Tasks** | **Start** | **End** | **Status** | | | | | | | | |
| Progression system | Apr | Jun | Planned | ████ | ████ | ████ | | | | | |
| Challenge persistence | Apr | May | Planned | ████ | ████ | | | | | | |
| Enhanced Clawd tutoring | Apr | Jun | Planned | ████ | ████ | ████ | | | | | |
| "I'm stuck" button | Jun | Jun | Planned | | | ████ | | | | | |
| Sound design | May | Jun | Planned | | ████ | ████ | | | | | |
| Onboarding tutorial | Jul | Aug | Planned | | | | ████ | ████ | | | |
| Points & rewards | Jul | Aug | Planned | | | | ████ | ████ | | | |
| Playtesting & balancing | Jul | Sep | Planned | | | | ████ | ████ | ████ | | |
| UI/UX polish | Aug | Sep | Planned | | | | | ████ | ████ | | |
| Accessibility features | Aug | Sep | Planned | | | | | ████ | ████ | | |
| Performance optimisation | Sep | Sep | Planned | | | | | | ████ | | |
| PAX demo build | Sep | Oct | Planned | | | | | | ████ | ████ | |
| **Steam page & trailer** | May | May | Planned | | ████ | | | | | | |
| **Dev logs** | May | Oct | Planned | | ████ | ████ | ████ | ████ | ████ | ████ | |
| **PAX Aus** | Oct 9–11 | | Planned | | | | | | | ████ | |
| Final cost report & acquittal | Oct | Nov | Planned | | | | | | | ████ | ████ |

> Note: This timeline will be recreated in the .docx template's table format with proper Gantt-style shading. The above is a text approximation for drafting purposes.
