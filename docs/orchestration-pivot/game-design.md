# Tech World: The Orchestration Game — Game Design Document

**Version:** 0.2 (Draft)
**Date:** February 2026
**Author:** Adventures in Tech meetup

---

## Vision

Tech World pivots from "learn to code" to **"learn to orchestrate AI agents"** — the defining technical skill of 2026 and beyond.

Writing code teaches you to give precise instructions to a deterministic system. Orchestrating agents teaches you to **define goals, constraints, and communication patterns for non-deterministic collaborators**. It's closer to management than engineering, and it's what every developer will need to understand as AI agents become the primary way software gets built and operated.

The game world stays the same — a multiplayer 2D space where players explore, collaborate via proximity video chat, and interact with stations. But the stations no longer ask you to write FizzBuzz. They ask you to **orchestrate AI agents that solve real problems** — first visually, then in code.

### The Learning Arc: Blueprint → Code

The game has two interaction modes that mirror how the real industry works:

- **Blueprint Mode** (Tier 1-2) — A visual pipeline builder. Drag agents, draw connections, write system prompts. Teaches orchestration *concepts* with low barrier to entry.
- **Code Mode** (Tier 3-4) — A Dart code editor with LSP. Write real orchestration code — retry policies, dynamic routing, error handling, custom merge logic. The visual builder can't express this; code can.

Players graduate from dragging nodes to writing the actual orchestration logic. This mirrors the professional trajectory: Zapier starts visual, power users demand code. AWS Step Functions have both a visual editor and CDK definitions. The game teaches both sides.

---

## Core Loop

```
Explore world → Find orchestration station → Read the scenario →
Build a solution (blueprint or code) → Run it against test cases →
Score → Compare with other players → Iterate or move on
```

### What Players Actually Do

1. **Walk to a station** (same as current terminal interaction)
2. **Read a scenario** — e.g. "A user wants to plan a road trip. You have a maps agent, a weather agent, a booking agent, and a budget agent."
3. **Open the panel** — Blueprint Mode (visual) for Tier 1-2, Code Mode (Dart editor) for Tier 3-4
4. **Build the solution**:
   - *Blueprint Mode:* drag agents from a palette, draw connections, write system prompts, set conditions
   - *Code Mode:* write Dart orchestration code using a provided SDK/API, with full LSP support (completion, hover, signatures)
5. **Run the pipeline** — the game executes it against test inputs and scores the result
6. **See the leaderboard** — other players solving the same challenge are ranked by quality, cost, and speed

---

## Two Modes, One Panel

The station panel adapts based on the scenario's tier. Both modes share the same scenario header, budget display, scoring, and results view — only the middle "solution area" changes.

### Blueprint Mode (Tier 1-2)

A visual pipeline builder for learning orchestration concepts.

```
┌─────────────────────────────────────────────────┐
│  Scenario: Plan a road trip          [Blueprint] │
│  Budget: 50,000 tokens  │  Test cases: 3         │
├────────────┬────────────────────────────────────┤
│            │                                      │
│  Agent     │         Pipeline Canvas              │
│  Palette   │                                      │
│            │   ┌─────┐    ┌─────┐    ┌─────┐    │
│  ┌──────┐  │   │Maps │───→│Route│───→│Book │    │
│  │Router│  │   │Agent│    │Plan │    │Agent│    │
│  ├──────┤  │   └─────┘    └──┬──┘    └─────┘    │
│  │Maps  │  │                 │                    │
│  ├──────┤  │            ┌────▼────┐              │
│  │Budget│  │            │Weather  │              │
│  ├──────┤  │            │Agent    │              │
│  └──────┘  │            └─────────┘              │
│            │                                      │
├────────────┴────────────────────────────────────┤
│  [Run Pipeline]  [Reset]         Score: --       │
│  Token usage: --/50,000          Quality: --     │
└─────────────────────────────────────────────────┘
```

**Agent Palette:** Pre-built agents the player can drag onto the canvas. Each scenario provides a specific set. Agents have:

- **Name** — what it does (e.g. "Maps Agent", "Budget Agent")
- **Capabilities** — what it can actually handle
- **Cost** — token cost per invocation
- **Reliability** — how often it succeeds (some agents are cheap but flaky)
- **Latency** — how long it takes

**Connections:** Players draw connections between agents to define data flow:

- **Sequential** — output of one feeds into the next
- **Parallel** — multiple agents run simultaneously, results merged
- **Conditional** — route to different agents based on output (if/else)
- **Retry** — loop back on failure with a fallback

**System Prompts:** Each agent node can be expanded to edit its system prompt. This is where the skill lives — the same agent with different prompts produces wildly different results.

### Code Mode (Tier 3-4)

A Dart code editor with full LSP support (reuses existing `CodeEditorPanel` + LSP server). Players write real orchestration code against a provided SDK.

```
┌─────────────────────────────────────────────────┐
│  Scenario: The Resilient Pipeline        [Code]  │
│  Budget: 30,000 tokens  │  Test cases: 3         │
├─────────────────────────────────────────────────┤
│  import 'package:tech_world/orchestration.dart'; │
│                                                   │
│  Future<PipelineResult> runPipeline(              │
│    String userQuery,                              │
│    Agent primarySearch,                           │
│    Agent fallbackSearch,                          │
│    Agent summarizer,                              │
│  ) async {                                        │
│    // Your orchestration code here                │
│    final searchResult = await primarySearch       │
│        .run(userQuery)                            │
│        .catchError((_) =>                         │
│            fallbackSearch.run(userQuery));         │
│                                                   │
│    return summarizer.run(searchResult.output);    │
│  }                                                │
│                                                   │
├─────────────────────────────────────────────────┤
│  [Run Pipeline]  [Reset]         Score: --       │
│  Token usage: --/30,000          Quality: --     │
└─────────────────────────────────────────────────┘
```

**What Code Mode enables that Blueprint Mode can't:**

- Retry policies with exponential backoff and custom conditions
- Dynamic agent selection based on runtime data
- Complex error handling (try/catch/finally across agent chains)
- Custom output merging and transformation logic
- Stateful pipelines that accumulate context across steps
- Recursive agent invocation (agent A calls agent B which may call agent A again)

**The SDK** (`package:tech_world/orchestration.dart`) provides:

- `Agent` — base class with `run()`, `runWithRetry()`, `runParallel()`
- `Pipeline` — builder pattern for constructing agent graphs
- `Router` — conditional dispatch based on input classification
- `Budget` — token tracking and enforcement
- `AgentResult` — structured output with token usage and timing

### Constraints & Budget (Both Modes)

Every scenario has:

- **Token budget** — spend wisely (cheap agents vs. expensive ones)
- **Time budget** — parallel execution matters
- **Quality threshold** — minimum acceptable output quality
- **Reliability target** — must work on X% of test cases

---

## Challenges (Scenarios)

### Tier 1: Single Agent — Blueprint Mode (Tutorial)

Learn the basics — one agent, one task, focus on writing good system prompts. Visual pipeline builder.

| # | Scenario | Agents Available | Key Lesson |
|---|----------|-----------------|------------|
| 1 | **Hello Agent** — Get an agent to introduce itself to a user | 1 (Chat Agent) | System prompts shape behavior |
| 2 | **The Summarizer** — Summarize a news article to exactly 3 bullet points | 1 (Text Agent) | Precision in instructions |
| 3 | **The Translator** — Translate a paragraph while preserving tone | 1 (Language Agent) | Quality vs. literal accuracy |
| 4 | **The Classifier** — Sort customer emails into categories | 1 (Analysis Agent) | Structured output formats |
| 5 | **The Extractor** — Pull structured data from messy text | 1 (Parse Agent) | Handling ambiguity |

### Tier 2: Multi-Agent Pipelines — Blueprint Mode

Wire multiple agents together visually. Order matters. Data flow matters.

| # | Scenario | Agents Available | Key Lesson |
|---|----------|-----------------|------------|
| 6 | **Research & Report** — Research a topic and write a summary | 2 (Search, Writer) | Sequential pipelines |
| 7 | **The Fact Checker** — Write an article then verify its claims | 2 (Writer, Verifier) | Self-checking loops |
| 8 | **Trip Planner** — Plan a day trip with weather and route | 3 (Maps, Weather, Planner) | Parallel data gathering |
| 9 | **The Debater** — Two agents argue a topic, a third judges | 3 (Pro, Con, Judge) | Agent-to-agent communication |
| 10 | **Customer Support** — Route inquiries to the right specialist | 4 (Router, Billing, Tech, Escalation) | Conditional routing |
| 11 | **Data Pipeline** — Clean, transform, validate, and load data | 4 (Cleaner, Transformer, Validator, Loader) | Error handling in chains |
| 12 | **The Editor** — Write, review, revise, publish | 3 (Writer, Critic, Editor) | Iterative refinement loops |

### Tier 3: Complex Orchestration — Code Mode

Real-world complexity in Dart code — unreliable agents, budget pressure, competing objectives. The visual builder can't express retry policies, dynamic routing, or custom error handling. Code can.

| # | Scenario | Agents Available | Key Lesson |
|---|----------|-----------------|------------|
| 13 | **The Unreliable API** — Write retry logic for agents that sometimes fail | 3 (Primary, Fallback, Monitor) | `try/catch`, `runWithRetry()`, fallback chains |
| 14 | **Budget Crunch** — Solve a complex task with a tight token budget | 5 (various, different costs) | Cost-aware agent selection, `Budget` tracking |
| 15 | **The Race** — Get an answer as fast as possible using parallel agents | 4 (Fast-cheap, Slow-good, etc.) | `Future.wait()`, `Future.any()`, parallel patterns |
| 16 | **Conflicting Advice** — Merge contradictory expert recommendations | 4 (Expert A, B, C, Synthesizer) | Custom merge logic, weighted consensus |
| 17 | **The Cascade** — Contain failures before they propagate through the chain | 5 (chain of dependent agents) | Circuit breakers, graceful degradation |
| 18 | **Dynamic Dispatch** — Route wildly varying requests to the best pipeline | 6 (Router + 5 specialists) | `Router` class, classification, adaptive dispatch |

### Tier 4: Adversarial & Creative — Code Mode (Unlockable)

These push into genuinely novel territory. All Code Mode — players need full programmatic control.

| # | Scenario | Agents Available | Key Lesson |
|---|----------|-----------------|------------|
| 19 | **The Negotiation** — Two agent teams negotiate a deal on your behalf | 4 (2 per side) | Multi-agent game theory |
| 20 | **Build an Agent** — Design a new agent's system prompt, then test it against scenarios | 1 (meta-agent) | Meta-orchestration |
| 21 | **The Audit** — Given someone else's pipeline, find the flaw | Broken pipeline | Debugging orchestration |
| 22 | **Agent vs. Human** — Your pipeline competes against a human-written solution | Variable | When to use agents vs. code |
| 23 | **The Orchestra** — Coordinate 8+ agents in a complex workflow with dependencies | 8+ | Everything at once |

---

## Scoring

Each challenge run produces a score across four dimensions:

| Dimension | What it measures | How |
|-----------|-----------------|-----|
| **Quality** | Did the output meet the scenario's requirements? | AI-evaluated against rubric (Clawd judges) |
| **Efficiency** | How many tokens were consumed? | Actual token count vs. budget |
| **Reliability** | Did it work across all test cases? | % of test cases passed |
| **Speed** | How long did the pipeline take to execute? | Wall clock time (parallel execution helps) |

**Composite score** = weighted combination. Different challenges weight dimensions differently (a "Budget Crunch" challenge weights efficiency heavily; a "Quality Report" challenge weights quality).

### Leaderboard

Per-challenge leaderboard visible at each station. Shows:
- Top 5 scores from all players
- Your best score
- Your most recent attempt
- (Optional) Inspect another player's pipeline design if they've made it public

---

## Clawd's New Role

Clawd evolves from "code tutor" to **orchestration advisor**:

- **Hint system** — "Have you considered running those agents in parallel?" (Blueprint Mode) or "Your retry logic doesn't handle the case where both agents fail" (Code Mode)
- **Pipeline review** — Submit a blueprint or code for Clawd's feedback before running it
- **Explain failures** — When a pipeline fails, Clawd explains what went wrong and suggests fixes
- **Code review** (Code Mode) — Clawd reviews orchestration code for patterns, anti-patterns, and optimization opportunities
- **Meta-discussions** — Ask Clawd about orchestration patterns, when to use agents vs. code, cost optimization strategies, the tradeoffs between visual and programmatic orchestration

Clawd still lives in the chat panel. The chat panel and orchestration panel can be shown simultaneously (chat on the left, orchestration on the right) or toggled.

---

## Multiplayer Dynamics

### Collaborative

- Players near the same station see each other's scores
- Proximity video chat lets you discuss strategies in real time
- A player can share their pipeline design with nearby players
- Group challenges (future): multiple players each control different agents in the same pipeline

### Competitive

- Per-station leaderboards
- Global orchestration score (sum of best scores across all challenges)
- Speed runs — complete all Tier 1 challenges as fast as possible
- Weekly featured challenge with community leaderboard

---

## Progression System

### Orchestration Rank

Players earn XP from completing challenges. Rank reflects overall orchestration skill:

| Rank | Title | XP Required | Unlocks |
|------|-------|-------------|---------|
| 1 | Dispatcher | 0 | Tier 1 challenges |
| 2 | Coordinator | 100 | Tier 2 challenges |
| 3 | Architect | 500 | Tier 3 challenges |
| 4 | Conductor | 1500 | Tier 4 challenges |
| 5 | Maestro | 5000 | Community challenge creation |

### XP Awards

- Complete a challenge: 10–50 XP (scales with tier)
- Beat the efficiency target: +10 XP
- Perfect reliability (100% test cases): +10 XP
- Beat another player's score: +5 XP
- First completion of a challenge (server-wide): +25 XP

### Unlockables

- New agent types in the palette (cosmetic variants with different personalities)
- Custom pipeline themes (visual styles for the node editor)
- Station skins (how your completed stations look to other players)

---

## Maps & Stations

The existing 6 maps are retained but re-themed:

| Current Map | New Theme | Stations |
|-------------|-----------|----------|
| The L-Room | **The Hub** — central meeting space | 2 Tier 1 stations |
| The Library | **The Academy** — structured learning | 4 stations (mixed tiers) |
| The Workshop | **The Lab** — experimental space | 2 Tier 3 stations |
| Open Arena | **The Arena** — competitive space | 0 (PvP challenge area) |
| Four Corners | **The Corners** — team zones | 4 stations (one per team) |
| Simple Maze | **The Gauntlet** — speed run course | 6 stations in sequence |

New maps to build:

| Map | Theme | Stations | Purpose |
|-----|-------|----------|---------|
| **The Server Room** | Rows of blinking server racks | 8 | All Tier 4 challenges |
| **The Garden** | Nature-themed relaxation space | 2 | Tutorial / onboarding |

---

## Technical Implications

### What Changes

| Component | Current | After Pivot |
|-----------|---------|-------------|
| `editor/` | Code editor + 23 Dart challenges | Extends to also host orchestration scenarios |
| `Challenge` model | title, description, starterCode, difficulty | `Scenario`: title, description, mode (blueprint/code), agents, testCases, budget, starterCode (code mode), scoring weights |
| Terminal interaction | Always opens code editor | Opens Blueprint Mode or Code Mode based on scenario tier |
| Clawd's system prompt | Code tutor persona | Orchestration advisor persona |
| `ProgressService` | Tracks completed challenges | Tracks scores, XP, rank |
| LSP server | Dart code completion for coding challenges | Dart code completion for orchestration code (Tier 3-4) — **retained** |

### What Stays the Same

- Flame game engine, maps, movement, pathfinding
- LiveKit for multiplayer, video, data channels
- Firebase Auth, Firestore, Cloud Functions
- Map editor (fully retained — community map creation)
- Proximity detection, video bubbles
- Chat service (Clawd chat)
- Service locator architecture
- `CodeEditorPanel` — reused for Code Mode (Tier 3-4) with new starter code
- LSP server infrastructure — reused for Code Mode
- All deployment infrastructure (LiveKit Cloud, GCP, Firebase Hosting)

### New Components Needed

| Component | Description | Mode |
|-----------|-------------|------|
| `OrchestrationPanel` | Wrapper that selects Blueprint or Code mode based on scenario | Both |
| `BlueprintCanvas` | Visual pipeline builder (drag agents, draw connections) | Blueprint |
| `AgentNode` | Draggable agent component with system prompt editor | Blueprint |
| `AgentPalette` | Sidebar with available agents for the scenario | Blueprint |
| `PipelineRunner` | Executes a pipeline against test cases (calls Claude API) | Both |
| `Scenario` model | Extends `Challenge` — scenario text, agents, test cases, budget | Both |
| `ScoreService` | Replaces simple `ProgressService` — multi-dimensional scoring + XP + rank | Both |
| `LeaderboardService` | Firestore-backed per-challenge leaderboards | Both |
| `orchestration.dart` SDK | Dart library with `Agent`, `Pipeline`, `Router`, `Budget` classes | Code |

### Reused Components

| Component | Original Use | New Use |
|-----------|-------------|---------|
| `CodeEditorPanel` | Dart coding challenges | Tier 3-4 orchestration code (different starter code + SDK imports) |
| `CodeForgeWeb` | Code editor widget | Same — writes Dart orchestration code |
| LSP server (`lsp.adventures-in-tech.world`) | Dart language server for challenges | Dart language server for orchestration SDK |
| `lsp_config.dart` | LSP connection config | Same — unchanged |

---

## Pipeline Execution (How It Actually Works)

When a player hits "Run Pipeline", the game:

1. **Serializes the pipeline** — agent nodes, connections, system prompts, conditions → JSON
2. **Sends to execution backend** — Cloud Function or bot service
3. **Backend walks the pipeline graph** — for each agent node, makes a Claude API call with the configured system prompt and input data
4. **Handles parallelism** — parallel branches execute concurrently via `Promise.all`
5. **Handles conditions** — evaluates conditional routing based on previous agent output
6. **Tracks token usage** — sums tokens across all API calls
7. **Evaluates quality** — final output scored against rubric by a judge model
8. **Returns results** — score breakdown sent back to client

### Cost Control

Real API calls cost real money. Mitigation:

- **Token budgets per challenge** — hard cap prevents runaway costs
- **Cached test cases** — common inputs pre-evaluated, only novel pipelines hit the API
- **Simulated mode** — for Tier 1, simulate agent behavior locally (no API call) to teach concepts without cost
- **Rate limiting** — max N pipeline runs per player per hour
- **Model selection** — use Haiku for most agent simulations, Sonnet for judge evaluations

---

## Open Questions

1. **Blueprint builder UI complexity** — The blueprint canvas only needs to handle Tier 1-2 (max ~4 agents, sequential + parallel). Start with a simplified linear/branching builder? Or build the full graph editor knowing it'll be used for visualization in Code Mode too?
2. **Real API calls vs. simulation** — Should early tiers simulate agent behavior (cheaper, deterministic) or always use real API calls (authentic but expensive and non-deterministic)?
3. **Mobile support** — Blueprint Mode works poorly on phones. Code Mode is even harder. Accept desktop-first or design mobile alternatives (e.g. Code Mode could use a simplified block-based interface on mobile)?
4. **Community challenges** — Should players be able to create and share their own orchestration scenarios? This adds huge replayability but needs moderation.
5. **The orchestration SDK scope** — How much of a real orchestration framework do we build for Code Mode? Minimal (just `Agent.run()` and `Budget`) or comprehensive (full retry policies, routers, circuit breakers, observability)? More SDK = more to maintain but richer challenges.
6. **Blueprint → Code bridge** — Should players be able to export a Tier 2 blueprint as Dart code to see what it looks like? This would be a powerful teaching tool but adds implementation complexity.

---

## Phased Rollout

### Phase 1: Foundation (4 weeks)

- `Scenario` model and 5 Tier 1 challenges (single-agent, simulated)
- Blueprint Mode: basic orchestration panel (single agent + system prompt editor)
- Clawd as orchestration advisor (new system prompt)
- Scoring (quality only, AI-evaluated)
- Retain all existing infrastructure (including LSP server)

### Phase 2: Pipelines + Code Mode (4 weeks)

- Blueprint Mode: multi-agent pipeline builder (sequential + parallel)
- 7 Tier 2 challenges (Blueprint Mode)
- **Code Mode**: orchestration SDK (`orchestration.dart`), reuse `CodeEditorPanel` + LSP
- **2 Tier 3 challenges** (Code Mode, simpler ones to validate the SDK)
- Real API execution via Cloud Function
- Token budget tracking
- Per-station leaderboards

### Phase 3: Full Complexity (4 weeks)

- 4 remaining Tier 3 challenges (Code Mode — retry, circuit breakers, dynamic dispatch)
- Full 4-dimension scoring
- Progression system (XP, ranks, unlockables)
- Map re-theming
- Optional: Blueprint → Code export (teach the bridge)

### Phase 4: Community (4 weeks)

- 5 Tier 4 challenges (Code Mode — adversarial, creative)
- Community challenge creation (Maestro rank)
- Pipeline/code sharing and inspection
- Group challenges (multiplayer orchestration)
- New maps (Server Room, Garden)
