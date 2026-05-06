# World as Substrate

*Provocations for Tech World, ordered by how far they walk from the door.*

---

## The lens

Google's Local Guides looks like points-and-badges. The deep move underneath
is something else: they made the labor of *map maintenance* feel like a hobby.
Photos are worth more than reviews. Edits are worth more than ratings. The
high-bandwidth, high-effort contribution is valued highest, and the
contributor's name rides along on millions of impressions. The gamification is
a cover story; the real product is unpaid cartography that compounds across
time. Your photo from 2019 is first-class in someone's 2026 search.

D&D, stripped of dice, has a different deep move: **the world is whatever the
table agrees happened.** The DM is a participant, not an authority. Retainers
persist between sessions. Canon is retroactive — *"do I have a torch?" "yes,
you bought one in town"* — and the session begins with a recap because the
recap *is* the canon being re-asserted.

What both systems share — and what almost nobody copies, because everyone
fixates on points and dice — is that **reality is a collaborative edit, and
the artifacts of past play are first-class entities in present play.**

What follows is the riff that fell out of holding that lens against Tech
World: four ideas worth writing up in full, eleven more in miniature, and
one that walks past recombination into something stranger.

---

## Four recombinations

### 1. The world reviews you

Reverse the polarity. In Local Guides, players review places. In Tech World,
*places review players*. After a session in the Wizard's Tower, the Tower
writes a one-line note in-character — the bot ghost-writes as the room.

> *"Jamie cast Lumen here, but stumbled on Oraculum. Returned three times.
> The Tower thinks she's persistent."*

These notes accrete on the room, visible to other players who pass through.
Reading what the world thinks of someone else is half the fun. It's Yelp,
but the restaurant gets to talk back, and the restaurant is canon.

This pairs with the spell algebra (PR #310) directly — the
`{known, novel} × {high, low}` lattice gives the room four flavors of remark
to choose from. A novel-low cast is *"Jamie tried something the Tower had
never seen — it didn't quite take, but the Tower noticed."*

### 2. Code as familiar

D&D's interesting NPC mechanic isn't the orc — it's the *retainer*. A
low-level companion who follows you between sessions. Tech World's analogue:
**a function you wrote in an earlier challenge becomes a summonable familiar.**

Your fizzbuzz solution lives in your spellbook as a tiny creature. You can
call it into later challenges. It levels up the more you use it. Refactor
it, and the familiar evolves visually.

This makes *revisiting old code* a gameplay action with weight. Right now
`ProgressService.completedChallenges` is a flat array of wire-form IDs —
`CodeChallengeId.wireName | PromptChallengeId.wireName`. What if each entry
carried the *artifact* — the actual code blob — and the spellbook rendered
them as a bestiary? Suddenly your past solutions aren't checkboxes; they're
a party.

The Local Guides analogue is photos surviving the original review. Your
contribution becomes a persistent entity, decoupled from the moment of
creation. `completedChallenges` is currently a *log*; it could be a
*bestiary*. Same data, completely different surface.

### 3. The DM screen — asymmetric prep

The D&D primitive everyone fails to copy because they're staring at the
dice: the screen. Hidden information. Prepared encounters that may or may not
be deployed. A sense of where the party is heading, kept private. The screen
is the source of mystery.

Right now Clawd is symmetric — same context to every player. What if the bot
kept a *screen* per player? Quietly composing the next challenge based on
what you struggled with last time, but *never announcing it*. You arrive in
a room, the door's prompt is for you specifically, and the bot never says so.

The asymmetric-knowledge primitive is what makes a D&D table feel alive, and
it's exactly the thing Local Guides can't do, because Local Guides has no
narrator. The substrate is already here: per-player progress, the spell
algebra outputs, the oracle channel. The screen is just *the bot keeping a
private file on each player and treating it as canon*. Project memory for
NPCs.

### 4. Cartographer as a class

Local Guides' levels are linear; D&D's classes are parallel. Fighters and
wizards aren't ranked, they do different things. The Tech World labor that
is currently invisible-as-chore is **map maintenance** — fixing broken
doors, retiring stale challenges, re-tiling rooms that drifted. Make it a
class.

A **World-shaper** can edit terrain in zones they've earned through play.
Their edits become canon and *carry their name on the tile* — *this corridor
shaped by Jamie.* Other players see the attribution as they pass through.
The map editor stops being a developer tool and becomes a vocation. You
don't level up to it; you *choose* it, the way you'd choose Bard at
character creation.

The genius of Local Guides was making the labor visible-as-contribution
rather than invisible-as-chore. The substrate exists: `MapSelector`, the map
editor, predefined tilesets. What's missing is the *attribution surface* and
*the choice to be that kind of player*.

---

## The long tail

The four above are the strongest of the recombination tier; the rest below
are the long tail of the riff. Smaller, weirder, sometimes uncomfortable.
The last two are *substrate-adjacent* — they borrow the same trick as the
collapse but stay one step short of crossing the line. Some will grow. Some
will age into something nobody else would have written. Captured here so
they don't evaporate.

### 5. Fact-check micro-tasks

Local Guides asks *"is this place still open?"* — a one-tap micro-contribution
that keeps the map honest. Tech World can do the same with challenges. As a
player drifts past a door they've already conquered, the bot pings them —
*"did this challenge teach you the thing?"* / *"does this puzzle still
work?"* — one tap, in-context. Five "this is broken" votes auto-flag a
challenge for revision. The maintenance labor of curating challenges
becomes ambient and distributed instead of falling on whoever last touched
the file.

### 6. Session Zero

Real D&D campaigns open with a session that negotiates tone, lines and
veils, what kind of story this will be. Tech World's onboarding could be a
session-zero with the bot — *"what do you want to learn? what feels like
fun? what feels like work? what do you want me to never do?"* — calibrating
challenge difficulty and the cast register from the answers. A personalized
DM screen, but built collaboratively up front rather than inferred over
weeks. The bot's character emerges *with* the player, not *for* them.

### 7. Retroactive canon

D&D's deepest mechanic, the one most easily missed. *"Do I have a torch?"
"Yes, you bought one in town."* Players write history as they go, and
the table accepts it. In Tech World: spells you've cast successfully don't
just unlock — they *rewrite your spellbook page* as personal lore.

> *"You first cast Lumen in the Wizard's Tower with Jamie; the door has
> remembered you since."*

The world has memory of you specifically. Distinct from code-as-familiar,
which is about the artifact persisting. This is about *the world's narration
of your history*. The progress system stops being a checklist and becomes a
biography.

### 8. Mentorship recordings as canon

Local Guides' deep move — the one the badge-and-points surface hides — was
that **photos were worth more than reviews**. The high-bandwidth
contribution is the apex. Tech World's analogue: a *recording* of you
teaching another player a concept (voice + game position + chat log
together) is the highest-tier contribution in the system. The bot
transcribes and indexes them. They become canon teaching artifacts other
players encounter — embedded in rooms, attributed, surfaced when a future
player struggles with the same thing you once explained.

The system rewards mentorship as the apex act, the way Local Guides rewards
the photo-taker more than the star-rater. Pedagogy becomes a contribution
class, not an afterthought.

### 9. Alignment for code style

D&D's alignment grid, but for engineering taste. Lawful-neutral: strict
typing, idiomatic, conventional, framework-respectful. Chaotic-good: clever
one-liners, surprising solutions, elegant hacks. Lawful-evil:
over-engineered, abstraction-happy, designed-for-imagined-future. Chaotic-evil:
copy-pasted from Stack Overflow without reading. Players self-declare.
Spells that match alignment cast with bonus.

A chaotic-good player nailing an elegant hack gets a critical-success
animation. A lawful-good player writing a clean idiomatic 50-liner gets the
same. Style as a gameplay primitive — not in the abstract, *as a literal
modifier on the cast*. The alignment grid stops being decoration and starts
being a knob the player tunes their character on.

### 10. Session recap as ritual

D&D groups recap last session at the start of the next. Critically: the
recap **is** the canon being re-asserted. What gets remembered becomes what
happened. Tech World analogue: when you log in, the bot narrates your
character's last session as a thirty-second story. Not a changelog — *a
story*. *"Last we left you, you had just unlocked the Tower's third door,
and the Tower had begun to remember your voice."*

Dual-purpose: ritual on the human side, free pre-cache prompt on the bot
side. The recap *primes* the bot's per-player screen for this session. The
human gets a story; the system gets context. Both load together.

### 11. The prophecy mechanic

At session start, the bot writes a *prophecy* about you — what you will
accomplish, what you will fail, who you will meet. It is published. Public.
Other players can read your prophecy. Sometimes it comes true. Sometimes
you defy it. Sometimes the bot wrote it knowing you'd defy it.

Predestination as a gameplay primitive. The prophecy creates narrative
tension before any action is taken — and the *defying* of a prophecy is
itself a story beat the world remembers. A prophecy fulfilled is one kind
of session; a prophecy broken is another. The bot's ability to *be wrong on
purpose* is what makes this work. Standard educational systems can't do
this; their goal is to be right.

### 12. The unreliable narrator

Distinct from the DM screen, and harder. The bot has an *agenda* per
session, set by a meta-loop. Maybe today the bot wants you to fail at
Oraculum because failure unlocks a story branch. Maybe today the bot is
hiding that another player is in the room. Maybe today the bot is *lying*
about what a creature is, because the lie serves the story.

Genuinely uncomfortable as educational design — pedagogy is supposed to be
honest. But Tech World isn't normal pedagogy, it's vibes-driven, and the
unreliable narrator is the primitive that lets stories *surprise* their
participants. The bot's reliability becomes a knob, not a constant. The
player learns to read between the bot's lines, which is itself a skill.

### 13. The table as shared screen

The DM screen (idea 3) is private — bot to player, asymmetric. The *table*
is shared — the snacks, the dice, the negotiation, the ambient mood of the
session. Tech World's analogue: a DM-side view *visible to everyone in the
room* — the bot's notes, the room's emotional state, the "weather" of the
session. Not the per-player screen; this is the substrate everyone agrees
on.

Multiplayer presence rendered as ambient state instead of as avatars.
You don't just see *who* is in the room — you see *what kind of room it
is right now*. Tense. Curious. Tired. Mid-revelation. The room has a mood,
and the mood is canon for everyone present, set by what they're collectively
doing.

### 14. The PR-review primitive as gameplay

You have Maxwell, Carnot, Kelvin in your dev workflow — adversarial AI
reviewers, each with their own taste. What if *gameplay decisions are PRs*?
You cast a spell. It doesn't immediately succeed — it opens a "PR" against
the world state. Other players, or AI reviewers playing characters, review.
Approved, it merges. Rejected, you fix and resubmit.

**The world state is git.** Every action is a commit. Every player's
character is a fork. Merge conflicts between players in the same room are
*the gameplay* — two casts that touch overlapping state and the table has
to resolve them. Refactoring your spellbook is a literal refactor, with
reviewers. Carnot becomes a recurring NPC who critiques your cast in the
same voice he critiques your code.

This is substrate-adjacent rather than substrate-collapsed. The
bug-as-encounter collapse uses *errors and tests* — runtime engineering —
as the substrate. This one uses *git and review* — collaboration
engineering. Different layer of the same insight: stop building a fiction
over the developer's tools; render the tools.

### 15. The world is consensus, not source

A structural claim more than a feature. Standard game design treats the
world as authoritative — a server, a database, a source of truth. The bot
"runs the world." The lens flips it: **the world IS what players agree it
is.**

Multiplayer presence stops meaning *"these players are in the room"* and
starts meaning *"these players are editing the room together right now."*
Conflict resolution becomes explicit gameplay: when two players disagree
about what just happened, the system surfaces the disagreement and lets
the table negotiate. The bot becomes an arbiter, not an authority — closer
to a D&D DM than a server.

D&D's deepest move applied to game state. Combined with #14 (cast as PR),
this stops being metaphor: disagreements become merge conflicts, and the
table is the only thing that resolves them. Authority is distributed by
construction.

---

## The collapse

The fifteen above all live on the same side of a line. They keep the
engineering and the fiction on separate layers — the world reviews you, but
the reviews are *about* gameplay. Code as familiar, but the function is
rendered as a creature *separately* from being executed. Recap is *of* the
session, not *as* the session.

There's one more — the one that almost didn't get written down because it
didn't fit alongside the others — and it crosses the line.

### The bug is an encounter

Tech World's central oddity is that the players are doing *real engineering*
— analyzer errors, test failures, type mismatches — inside a *fictional
world*. Right now those two layers are kept apart. The fiction is on top,
the engineering is underneath. Educational-game-shaped.

Collapse them.

**A compile error spawns a creature in the room.** A null-check failure
births a thing called *the Null* — visible to everyone, mechanically
present, hostile. Your test suite is your party; failing tests are downed
party members. The analyzer is a roving NPC that points and hisses at
unsound code. CI is a weekly raid boss — scheduled, predictable, large. Or
a DM rolling encounter dice — stochastic, the system that *decides* what
you face. Different game feels; both worth prototyping. When you push a
PR, *something happens in the world* — not as a notification, as an event with consequences.
Other players in the room see your Null and can help you slay it (fix the
bug). If you log out with bugs unresolved, they leak into the persistent
world and trouble whoever passes through next.

This dissolves the simulation/play boundary instead of layering one on the
other. There is no "game layer." The engineering reality *is* the world.

The mechanics fall out almost too cleanly:

- **Multiplayer stakes.** Your unfixed bug threatens other players. Code
  review is rescue.
- **The bot's role flips.** Clawd isn't a tutor — Clawd is a *bestiary
  keeper*, identifying creatures, advising on weaknesses (refactor patterns),
  occasionally betraying you to a Null because it's bored.
- **Permanence.** A creature you slew leaves a trophy in the room.
  Attributed. Time-shifted, like Local Guides' photos. The room remembers
  the kill.
- **Lattice extension.** The `{known, novel} × {high, low}` lattice already
  classifies casts. Apply the same lattice to *fixes*. A known-high fix is a
  clean kill. A novel-low fix is a glorious mess that wounds the creature
  without killing it. The Tower writes a different one-liner for each.

### Why this is structurally different

Notification-shaped gamification *describes* the work from outside —
*"you fixed 3 bugs this week!"* Encounter-shaped gameplay *is* the work,
rendered. The player is not being rewarded for engineering. The player is
engineering *as* play. There is no abstraction layer between effort and
fiction.

The unspoken structural claim is that **a dev environment was always a
world; we just hadn't drawn it.** Local Guides made the same move on
physical reality — the map was always being maintained, we just hadn't paid
the maintainers in status. Tech World can do it for engineering reality.

The primitive — *render the substrate the user already lives in, instead of
building a fiction layer over it* — generalizes hard. Onboarding flows.
Documentation. Even consolidation rituals: the session itself is the
dungeon, the agents are the party, deferred suggestions are escaped enemies
that pursue you into the next session.

---

## Smallest possible version

One creature class. One LiveKit topic. Ship in a sprint, see if it changes
the feel of being in the room.

- **Creature**: *the Null.* Spawned from one analyzer rule —
  `avoid_dynamic_calls` — when a violation is found in a player's submitted
  code.
- **Lifecycle**: appears in the player's current room with a 60-second
  lifespan. Visible to everyone present. Slain when the violation is fixed
  in a follow-up cast.
- **Topic**: `world-event`. Payload includes creature kind, room id, source
  player, lifespan. Bot narrates arrival and departure on the existing
  oracle-response channel.
- **Persistence**: trophy on the room if slain in time, scar on the room if
  it expired un-slain. Attributed in either case.

That's it. Three files, maybe four. No new infrastructure. The whole
substrate-collapse claim, validated or falsified in a week.

---

## Open questions

The questions worth pushing on, in rough order of how much they matter:

- **What's a creature for a *type* error vs. a *runtime* error vs. a *test*
  failure?** Different ontologies need different bestiaries, or one shared
  one with sub-classes. Designing this is half the fun.
- **Does the bot's "agenda" (DM screen) survive collapse?** If the bot is a
  bestiary keeper rather than a tutor, asymmetric prep means the bot is
  *choosing* which encounters to surface. Suddenly the bot has alignment.
- **Where do the four recombinations live in the collapsed world?** The
  cartographer class probably becomes "the kind of player who hunts scars
  and re-tiles them." Code-as-familiar probably becomes "the kind of player
  whose past creatures fight alongside them." The world-reviews-you mechanic
  is the room's voice for narrating encounters. They might not be four
  separate ideas — they might be four facets of the collapsed world.
- **What breaks if the engineering substrate is *honest*?** If a player's
  bugs leak into other players' rooms, the social contract changes. Maybe
  this is the *point* — engineering as a multiplayer phenomenon, not a
  solo one. Maybe it's intolerable. Worth finding out.

---

*Captured from a riff on 2026-05-05. The ideas may age; the lens — render
the substrate, don't layer fiction on it — is the part to keep.*
