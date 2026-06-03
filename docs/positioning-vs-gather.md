# Positioning: Tech World vs Gather Town

*Captured 2026-05-17. Feature audit + the principle that fell out.*

This is the *scaffolding* that led to [`the-substrate-has-a-body.md`](the-substrate-has-a-body.md). The murals doc has the deeper move; this doc preserves the analysis that got us there.

---

## What Gather has (that AITW is missing)

Source: Gather's published Features collection (8 articles) + training-knowledge for the broader product surface circa 2022-2024. **Verify the spicier claims against Gather's current product before quoting externally.**

**Social presence:**
- Spatial proximity video/audio for groups >2 (Tech World does proximity, but bubbles are the entire UI)
- Walled tiles / private spaces for impromptu side conversations
- Spotlight tiles — broadcast one speaker to entire room
- Status indicators (🟢 Available / Busy / DND) on every avatar
- Ghost mode (walk through other players)
- Wave / follow

**Authoring & objects:**
- Object embedding with rich types at specific tiles (text/image/video/link/iframe)
- Build mode with furniture catalog
- Custom avatars + outfit editor (Gather's wardrobe is deep; AITW has 3 predefined)
- Locked rooms with passwords

**Productivity layer (Gather's centre of mass):**
- Calendar/recurring meeting integration
- Meeting recording with AI notes
- Whiteboards (Eraser.io integration)
- 9 embedded mini-games (Codewords, Werewolf, Tetris, etc.)
- Coworking sessions
- Guest management (invite links, capacity, kick/mute/ban)

**Quality of life:**
- Mini mode (compact UI)
- Color mode (dark/light)
- Audio settings with noise suppression
- Mobile app that doesn't suck

## What AITW has (that Gather is missing)

The asymmetry is sharper here because Tech World is building toward a *specific thesis* that Gather doesn't share. **Gather is "Zoom for offices that looks like Pokemon." AITW is "D&D table where the dice are real engineering."**

- **AI participant who joins the room as an avatar** (Clawd, Dreamfinder) — speaks, listens, sees the map. Gather has no equivalent. Their AI is in the meeting-recap layer, not the spatial layer.
- **Code editor + prompt-challenge panels in-game** with first-class progress tracking.
- **Voice-cast spellbook** — speech-command spells with `{known, novel} × {high, low}` confidence lattice.
- **Player-owned rooms with full map editor + tile painting.** Gather has Mapmaker but it's admin-only; AITW lets any player be a world-shaper.
- **Cross-repo bot dispatch infrastructure** — bot auto-joins via LiveKit token-based dispatch.
- **Event-sink + AV diagnostics observability** (shipped 2026-05-16/17 spiral). Gather's troubleshooting is "refresh the page."
- **Open-source, self-hostable.** Gather is SaaS-only. For a meetup group, school, or community wanting persistence and control, this is the line.

## The wow candidates (initial three)

Before the murals doc opened the genre claim, three differentiators were proposed:

### Structural: "The bug is an encounter"

The move Gather **literally cannot make**, because Gather isn't connected to anyone's engineering substrate. AITW is.

> A compile error spawns a creature in the room. A null-check failure births a thing called *the Null* — visible to everyone, mechanically present, hostile. Your test suite is your party; failing tests are downed party members. Other players see your Null and can help you slay it (fix the bug). If you log out with bugs unresolved, they leak into the persistent world.

Smallest possible version (per `world-as-substrate.md` §The collapse): one creature class (the Null), one analyzer rule (`avoid_dynamic_calls`), 60-second lifespan, persistent trophy/scar on the room. Three files. Ships in a sprint.

The differentiator isn't "more fun than Gather." It's that **it changes what genre of thing AITW is.** Every other code-learning platform layers gamification on top of the IDE. AITW *renders the IDE* — engineering is the world, not a notification about it.

### Tactical: "The world reviews you"

Cheap to build, screenshot-shareable. After a session in a room, the bot ghost-writes a one-line in-character note from the room about that player:

> *"Jamie cast Lumen here, but stumbled on Oraculum. Returned three times. The Tower thinks she's persistent."*

Gather's rooms are silent. AITW's rooms have opinions. *It's Yelp where the restaurant gets to talk back, and the restaurant is canon.*

This is the **front door**. Bug-as-encounter is the deep moat; room-reviews-you is what gets posted to Twitter.

### Retention: "Code as familiar"

Your past solutions become summonable creatures in your spellbook bestiary. `ProgressService.completedChallenges` is currently a log of wire-form IDs; it could be a *bestiary*. The same data, completely different surface. Makes revisiting old code a gameplay action with weight. Engineers come back to see their *party* grow.

## The positioning principle

The principle that fell out of the analysis — load-bearing for any future feature decision:

> **Tech World should refuse to ship a whiteboard, a meeting recording, a calendar integration. Tech World should ship hard: anything that collapses the engineering layer into the fiction layer.**

Every feature evaluation goes through that filter. *"Is this a productivity tool with a spatial skin"* → reject. *"Is this a rendering of an engineering reality that no other tool acknowledges has a body"* → ship.

Gather has 5 years of office-productivity polish. Tech World will lose that fight. But Gather can't build bug-as-encounter (or the corridor model in [`the-substrate-has-a-body.md`](the-substrate-has-a-body.md)) without becoming a different product, because their users are office workers not engineers, and their substrate is calendars not commits.

**The thing AITW should refuse:** features that would require it to compete on Gather's playing field. Whiteboard. Calendar invites. Meeting recordings. Embedded mini-games. These are all *Gather strengths* and *AITW weaknesses* and chasing them is the kind of cargo-cult feature-checklist work that loses both fights — you become a worse Gather.

**The thing AITW should ship:** features Gather literally cannot copy without becoming a different product. The bug as a creature. The corridor as a walkable engineering identity. The hive's chord. Agents as residents. The Library of First Commits. These all require the AITW substrate (engineering reality) — Gather has no path to them.

## What this means in practice

For any incoming feature proposal, ask:
1. *Does Gather already have a polished version of this?* → suspicious. Likely the wrong fight.
2. *Could Gather ship this in a sprint by adding an iframe?* → almost certainly wrong fight.
3. *Does this require us to render some part of the engineering substrate that nobody else renders?* → likely right fight.
4. *If we don't ship this, will another product render the substrate before us?* → urgent, right fight.

The principle is not "never copy good Gather features." It's "never let Gather's roadmap be our roadmap." The substrate is our thesis. Their thesis is spatial Zoom. Different products.

## Related

- [`the-substrate-has-a-body.md`](the-substrate-has-a-body.md) — the genre claim and ten murals that fall out of taking the principle seriously
- [`world-as-substrate.md`](world-as-substrate.md) — the lens (Local Guides + D&D) that generates the substrate move in the first place
