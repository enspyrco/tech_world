# Tech World Orchestration Pivot — Technical Architecture

**Version:** 0.2 (Draft)
**Date:** February 2026

---

## Guiding Principle

Maximize reuse of existing infrastructure. The game world, multiplayer, and social features are already built. The pivot **extends** the existing editor subsystem rather than replacing it — the code editor and LSP server are reused for Code Mode (Tier 3-4), while Blueprint Mode (Tier 1-2) adds a new visual pipeline builder alongside.

---

## What Changes

```
RETAINED (reused for Code Mode)      ADDED
────────────────────────────         ────────────────────────────────
lib/editor/                          lib/orchestration/
  code_editor_panel.dart ──────────→   (reused for Tier 3-4 Code Mode)
  lsp_config.dart ─────────────────→   (unchanged)
  challenge.dart ──────────────────→   scenario.dart (extends Challenge)
  predefined_challenges.dart ──────→   predefined_scenarios.dart (replaces)

                                     lib/orchestration/blueprint/
                                       blueprint_canvas.dart
                                       agent_node.dart
                                       agent_palette.dart
                                       prompt_editor.dart

                                     lib/orchestration/
                                       orchestration_panel.dart (mode switch)
                                       pipeline_model.dart
                                       pipeline_runner.dart
                                       orchestration_sdk.dart (Code Mode SDK)

LSP server (GCP) ──────────────────→ Retained for Code Mode
  lsp-ws-proxy                         (orchestration SDK needs completions)
  dart language-server
  nginx config

                                     Pipeline execution endpoint
                                       Cloud Function or bot extension
                                       Claude API calls

ProgressService                      ScoreService + LeaderboardService
  Set<String> completedChallenges      Multi-dimensional scores
  Firestore arrayUnion                 Firestore subcollections
```

---

## New Data Models

### `Scenario` (replaces `Challenge`)

```dart
enum ScenarioMode { blueprint, code }

class Scenario {
  final String id;
  final String title;
  final String description;      // The situation the player must solve
  final int tier;                 // 1-4
  final ScenarioMode mode;       // blueprint (Tier 1-2) or code (Tier 3-4)
  final List<AgentDef> agents;   // Available agents for this scenario
  final List<TestCase> testCases;
  final Budget budget;
  final ScoringWeights weights;
  final String? starterCode;     // Code Mode only — Dart starter template
  final String? sdkImports;      // Code Mode only — which SDK classes to import
}

class AgentDef {
  final String id;
  final String name;
  final String description;      // What this agent can do
  final List<String> capabilities;
  final int costPerCall;         // Token cost
  final double reliability;      // 0.0 to 1.0
  final Duration latency;        // Simulated execution time
}

class TestCase {
  final String id;
  final String input;            // User request to the pipeline
  final String rubric;           // How to evaluate the output (for judge)
  final Map<String, dynamic> context; // Additional data agents can access
}

class Budget {
  final int maxTokens;
  final Duration maxTime;
}

class ScoringWeights {
  final double quality;     // 0.0 to 1.0, must sum to 1.0
  final double efficiency;
  final double reliability;
  final double speed;
}
```

### `Pipeline` (the player's solution)

```dart
class Pipeline {
  final String id;
  final String scenarioId;
  final List<PipelineNode> nodes;
  final List<PipelineEdge> edges;
}

class PipelineNode {
  final String id;
  final String agentId;          // References AgentDef.id
  final String systemPrompt;     // Player-written
  final Offset position;         // Position on canvas
  final NodeType type;           // agent, condition, merge, input, output
}

class PipelineEdge {
  final String sourceNodeId;
  final String targetNodeId;
  final String? condition;       // For conditional routing
}

enum NodeType { agent, condition, merge, input, output }
```

### `PipelineResult` (execution output)

```dart
class PipelineResult {
  final String pipelineId;
  final String scenarioId;
  final int tokensUsed;
  final Duration executionTime;
  final double qualityScore;     // 0.0 to 1.0 (judge-evaluated)
  final int testCasesPassed;
  final int testCasesTotal;
  final Map<String, AgentTrace> agentTraces; // Per-node execution logs
  final double compositeScore;   // Weighted combination
}

class AgentTrace {
  final String nodeId;
  final String input;
  final String output;
  final int tokensUsed;
  final Duration duration;
  final bool succeeded;
  final String? error;
}
```

### `PlayerProgress` (replaces simple Set<String>)

```dart
class PlayerProgress {
  final String odUserId;
  final int xp;
  final OrchestrationRank rank;
  final Map<String, BestScore> bestScores; // scenarioId -> best score
  final Set<String> completedScenarios;
}

enum OrchestrationRank {
  dispatcher,   // 0 XP
  coordinator,  // 100 XP
  architect,    // 500 XP
  conductor,    // 1500 XP
  maestro,      // 5000 XP
}
```

---

## Firestore Schema Changes

### Current

```
users/{uid}
  displayName, avatarId, completedChallenges[]
```

### After Pivot

```
users/{uid}
  displayName, avatarId, xp, rank

users/{uid}/scores/{scenarioId}
  bestComposite, bestQuality, bestEfficiency, bestReliability, bestSpeed
  attempts, lastAttempt, bestPipeline (JSON)

users/{uid}/pipelines/{pipelineId}
  scenarioId, nodes[], edges[], createdAt, shared (bool)

leaderboards/{scenarioId}/entries/{odUserId}
  displayName, bestComposite, bestPipeline, updatedAt
```

---

## Pipeline Execution Architecture

### Option A: Cloud Function (Recommended for Phase 1-2)

```
Flutter Client                    Firebase Cloud Function
─────────────                     ──────────────────────
OrchestrationPanel                executePipeline()
  │                                 │
  ├─ serialize Pipeline to JSON     ├─ validate pipeline + budget
  ├─ call Cloud Function ──────────→├─ topological sort nodes
  │                                 ├─ walk graph:
  │                                 │   for each node:
  │                                 │     ├─ resolve inputs from edges
  │                                 │     ├─ call Claude API (Haiku)
  │                                 │     ├─ track tokens
  │                                 │     └─ store output
  │                                 ├─ evaluate quality (Sonnet judge)
  │                                 ├─ compute composite score
  ├─ receive PipelineResult ◄───────├─ return PipelineResult
  └─ display scores                 └─ write to Firestore
```

**Pros:** Simple, stateless, scales automatically, existing Firebase setup.
**Cons:** 60-second Cloud Function timeout limits complex pipelines.

### Option B: Bot Service Extension (Phase 3+)

Extend the existing `tech_world_bot` Node.js service:

```
Flutter Client                    Bot Service (GCP Compute Engine)
─────────────                     ──────────────────────────────
OrchestrationPanel                New endpoint: /execute-pipeline
  │                                 │
  ├─ send via LiveKit data ────────→├─ same graph-walking logic
  │   channel (topic: pipeline)     ├─ no timeout constraint
  │                                 ├─ can stream progress updates
  ├─ receive progress updates ◄─────├─ send node-by-node results
  ├─ receive final result ◄─────────├─ return PipelineResult
  └─ display scores                 └─ write to Firestore
```

**Pros:** No timeout limit, real-time progress streaming, reuses LiveKit data channels.
**Cons:** More complex, single point of failure (one GCP instance).

### Recommendation

Start with **Option A** (Cloud Functions) for Tier 1-2 scenarios (simple, fast pipelines). Migrate to **Option B** for Tier 3-4 when pipelines get complex and need progress streaming.

---

## Simulated Mode (Tier 1)

For tutorial challenges, avoid real API calls entirely:

```dart
class SimulatedAgent {
  final AgentDef definition;
  final Map<String, String> cannedResponses; // input pattern -> output

  /// Returns a simulated response based on system prompt quality.
  /// Evaluates the player's system prompt against a rubric
  /// to determine which canned response tier to return.
  SimulatedResult execute(String input, String systemPrompt);
}
```

The simulation evaluates the **player's system prompt** against a rubric:
- Good prompt → high-quality canned response
- Mediocre prompt → mediocre response
- Bad prompt → bad response

This teaches prompt engineering without API costs. The player still learns the core skill. One real API call (to Haiku) evaluates the system prompt quality.

---

## UI Architecture

### OrchestrationPanel Widget Tree

The `OrchestrationPanel` is a wrapper that switches between Blueprint and Code mode based on `scenario.mode`. Both modes share the header, control bar, and results panel.

```
OrchestrationPanel (StatefulWidget)
├── ScenarioHeader
│   ├── scenario title + description
│   ├── mode indicator [Blueprint] or [Code]
│   ├── budget display (tokens remaining, time)
│   └── test case count
├── SolutionArea (switches on scenario.mode)
│   ├── [Blueprint Mode] Row
│   │   ├── AgentPalette (draggable agent cards)
│   │   │   └── AgentCard × N (per scenario)
│   │   └── BlueprintCanvas (InteractiveViewer + CustomPainter)
│   │       ├── PipelineNode × N (positioned, draggable)
│   │       │   └── NodeConfigDialog (system prompt editor)
│   │       └── PipelineEdge × N (painted connections)
│   └── [Code Mode] CodeEditorPanel  ← reused from lib/editor/
│       └── CodeForgeWeb (with LSP, orchestration SDK completions)
├── ControlBar
│   ├── Run button
│   ├── Reset button
│   └── Score display (4 dimensions)
└── ResultsPanel (expandable)
    ├── AgentTrace per node (collapsible)
    └── Test case results
```

### Responsive Layout

The orchestration panel needs more space than the code editor.

| Breakpoint | Layout |
|------------|--------|
| >= 1200px | Full pipeline canvas (600px) + agent palette sidebar |
| >= 800px | Compact canvas (480px) + collapsible palette |
| < 800px | Stacked: palette on top, canvas below (scroll) |

### Side Panel Priority Update

```
Current:  map editor > code editor > chat panel
After:    map editor > orchestration panel > chat panel
```

Chat and orchestration can optionally display side by side on wide screens (>= 1400px), since players may want to ask Clawd for help while building a pipeline.

---

## Service Changes

### New Services

```dart
/// Replaces ProgressService
class ScoreService {
  /// Firestore-backed score tracking with local cache
  Future<void> recordResult(String scenarioId, PipelineResult result);
  Stream<PlayerProgress> progressStream(String userId);
  int get currentXp;
  OrchestrationRank get currentRank;
  bool isScenarioUnlocked(String scenarioId);
}

/// Per-challenge leaderboards
class LeaderboardService {
  Stream<List<LeaderboardEntry>> leaderboard(String scenarioId, {int limit = 10});
  Future<void> submitScore(String scenarioId, double composite, Pipeline pipeline);
}

/// Executes pipelines against test cases
class PipelineExecutionService {
  /// Phase 1-2: calls Cloud Function
  /// Phase 3+: sends via LiveKit data channel to bot
  Future<PipelineResult> execute(Pipeline pipeline, Scenario scenario);
  Stream<NodeProgress>? progressStream; // Phase 3+ only
}
```

### Modified Services

```dart
// ChatService — Clawd's system prompt changes
// No structural changes, just prompt content:
// "You are an orchestration advisor..." instead of "You are a coding tutor..."

// LiveKitService — add data channel topic for pipeline execution (Phase 3)
// New topic: 'pipeline' for sending pipelines to bot
// New topic: 'pipeline-result' for receiving results
```

### Retained Services

```
LSP server infrastructure (GCP) — retained for Code Mode (Tier 3-4)
  lsp-ws-proxy → dart language-server (unchanged)
  LSP workspace updated: add orchestration SDK to pubspec.yaml
  lsp_config.dart — unchanged

CodeEditorPanel — retained, reused in Code Mode
  StarterCode comes from Scenario.starterCode instead of Challenge.starterCode
```

### Locator Registration

```dart
// In _onAuthStateChanged (sign-in):
Locator.add<ScoreService>(ScoreService(userId: user.uid));
Locator.add<LeaderboardService>(LeaderboardService());
Locator.add<PipelineExecutionService>(PipelineExecutionService());

// In _onAuthStateChanged (sign-out):
locate<ScoreService>().dispose();
Locator.remove<ScoreService>();
// etc.
```

---

## Migration Path

### Phase 1: Extend, Don't Replace

`lib/editor/` stays intact. `lib/orchestration/` is added alongside it. The `OrchestrationPanel` wraps both modes:

```dart
// lib/orchestration/orchestration_panel.dart
class OrchestrationPanel extends StatelessWidget {
  final Scenario scenario;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ScenarioHeader(scenario: scenario),
      Expanded(child: switch (scenario.mode) {
        ScenarioMode.blueprint => BlueprintCanvas(scenario: scenario),
        ScenarioMode.code => CodeEditorPanel(
          challenge: scenario.toChallenge(), // adapter
          onSubmit: _handleCodeSubmit,
        ),
      }),
      ControlBar(onRun: _runPipeline),
    ]);
  }
}
```

Terminal tap in `TechWorld` opens `OrchestrationPanel` instead of `CodeEditorPanel` directly. The panel delegates to `CodeEditorPanel` internally for Code Mode — no breaking changes.

### Phase 2: Remove Legacy Challenges

Once orchestration scenarios fully replace coding challenges:
- Remove `lib/editor/predefined_challenges.dart`
- Remove `lib/editor/challenge.dart` (or keep as base class if `Scenario` extends it)
- Keep `lib/editor/code_editor_panel.dart` — it's now a dependency of Code Mode
- Keep `lib/editor/lsp_config.dart` — unchanged

### Data Migration

```dart
// One-time migration for existing users:
// completedChallenges[] → completedScenarios[] (fresh start for new system)
// No score migration needed (new scoring dimensions)
// XP starts at 0 for everyone
```

### LSP Workspace Update

The LSP server's workspace needs the orchestration SDK available for code completion:

```bash
# On GCP instance: update /opt/lsp-workspace/pubspec.yaml
# Add orchestration SDK as a path dependency or publish to pub.dev
gcloud compute ssh tech-world-bot --zone=us-central1-a \
  --command="cd /opt/lsp-workspace && echo 'Update pubspec with orchestration SDK'"
```

---

## Orchestration SDK (Code Mode)

The SDK is a Dart library that players `import` in Code Mode challenges. It provides the building blocks for writing orchestration logic. The SDK runs client-side for type checking and LSP completion, but actual agent execution happens server-side.

### `lib/orchestration/sdk/orchestration.dart`

```dart
/// Core agent abstraction. Players receive pre-configured instances.
abstract class Agent {
  String get name;
  String get description;
  int get costPerCall;

  /// Run the agent with input text. Returns structured result.
  Future<AgentResult> run(String input, {String? systemPrompt});

  /// Run with automatic retry on failure.
  Future<AgentResult> runWithRetry(
    String input, {
    int maxAttempts = 3,
    Duration backoff = const Duration(seconds: 1),
    bool Function(AgentResult)? shouldRetry,
  });
}

/// Result from a single agent invocation.
class AgentResult {
  final String output;
  final int tokensUsed;
  final Duration duration;
  final bool succeeded;
  final String? error;
}

/// Run multiple agents in parallel, collect all results.
Future<List<AgentResult>> runParallel(
  List<(Agent, String)> tasks, // (agent, input) pairs
);

/// Run multiple agents in parallel, return the first to succeed.
Future<AgentResult> runRace(
  List<(Agent, String)> tasks,
);

/// Route input to different agents based on classification.
class Router {
  Router(this.classifier, this.routes);
  final Agent classifier;
  final Map<String, Agent> routes;

  Future<AgentResult> route(String input);
}

/// Track and enforce token budget.
class Budget {
  Budget({required this.maxTokens});
  final int maxTokens;

  int get used;
  int get remaining;
  bool get exceeded;

  /// Wrap an agent to track its token usage against this budget.
  Agent track(Agent agent);
}
```

### Where the SDK Lives

| Environment | Location | Purpose |
|-------------|----------|---------|
| Game client | `lib/orchestration/sdk/` | Type definitions, LSP completion, client-side validation |
| LSP workspace | `/opt/lsp-workspace/lib/orchestration.dart` | Language server analysis for code completion |
| Cloud Function / Bot | `functions/src/sdk/` | Actual execution (SDK methods call Claude API) |

The client-side SDK is types + interfaces only. The server-side implementation actually makes Claude API calls. Players write against the interface; the game executes against the implementation.

---

## Cloud Function: `executePipeline`

```typescript
// functions/src/executePipeline.ts

interface ExecutePipelineRequest {
  pipeline: Pipeline;       // nodes + edges + prompts
  scenarioId: string;
  userId: string;
}

interface ExecutePipelineResponse {
  result: PipelineResult;
}

export const executePipeline = onCall(async (request) => {
  const { pipeline, scenarioId, userId } = request.data;

  // 1. Load scenario definition (agents, test cases, budget)
  const scenario = getScenario(scenarioId);

  // 2. Validate pipeline against scenario constraints
  validatePipeline(pipeline, scenario);

  // 3. Topological sort for execution order
  const executionOrder = topologicalSort(pipeline.nodes, pipeline.edges);

  // 4. Run each test case through the pipeline
  const testResults = await Promise.all(
    scenario.testCases.map(tc => executePipelineOnce(executionOrder, pipeline, tc))
  );

  // 5. Evaluate quality with judge model
  const qualityScores = await Promise.all(
    testResults.map(tr => judgeOutput(tr.finalOutput, tr.testCase.rubric))
  );

  // 6. Compute composite score
  const result = computeScore(testResults, qualityScores, scenario.weights);

  // 7. Write to Firestore
  await writeResult(userId, scenarioId, result);

  return { result };
});
```

---

## Testing Strategy

### Unit Tests

| Component | What to Test |
|-----------|-------------|
| `Scenario` model | Serialization, validation, mode detection, agent references |
| `Pipeline` model | Serialization, topological sort, cycle detection |
| `PipelineNode` | Connection validation, input/output compatibility |
| `ScoreService` | XP calculation, rank thresholds, Firestore sync |
| `LeaderboardService` | Ordering, deduplication, entry limits |
| `SimulatedAgent` | System prompt evaluation, response selection |
| Orchestration SDK | `Agent.run()`, `runParallel()`, `runRace()`, `Router`, `Budget` |

### Widget Tests

| Component | What to Test |
|-----------|-------------|
| `OrchestrationPanel` | Mode switching (blueprint vs code), scenario display |
| `BlueprintCanvas` | Node placement, edge drawing, drag behavior |
| `AgentNode` | System prompt editing, expand/collapse |
| `OrchestrationPanel` (Code Mode) | Loads `CodeEditorPanel` with correct starter code |
| `ResultsPanel` | Score display, trace rendering |

### Integration Tests

| Scenario | What to Test |
|----------|-------------|
| Terminal → Blueprint Mode | Tap terminal (Tier 1-2) opens blueprint canvas |
| Terminal → Code Mode | Tap terminal (Tier 3-4) opens code editor with SDK imports |
| Pipeline execution (simulated) | End-to-end Tier 1 challenge in Blueprint Mode |
| Code execution | End-to-end Tier 3 challenge in Code Mode |
| Score persistence | Result → Firestore → leaderboard |
| Progression | Complete scenario → XP → rank up → unlock |

### Acceptance Tests (ATDD per project conventions)

Write acceptance tests first for each phase:

```dart
// Phase 1 acceptance test (Blueprint Mode)
testWidgets('player can open blueprint panel from Tier 1 terminal', (tester) async {
  // Given: player is near a terminal with a Tier 1 scenario
  // When: player taps the terminal
  // Then: OrchestrationPanel opens in Blueprint Mode
  // And: agent palette shows the available agents
  // And: blueprint canvas is empty (ready to build)
});

testWidgets('player can wire a single agent and run pipeline', (tester) async {
  // Given: player has dragged an agent onto the blueprint canvas
  // And: player has written a system prompt
  // When: player taps Run
  // Then: pipeline executes against test cases
  // And: score is displayed
  // And: score is persisted to Firestore
});

// Phase 2 acceptance test (Code Mode)
testWidgets('player can open code editor from Tier 3 terminal', (tester) async {
  // Given: player is near a terminal with a Tier 3 scenario
  // When: player taps the terminal
  // Then: OrchestrationPanel opens in Code Mode
  // And: code editor shows starter code with SDK imports
  // And: LSP provides completion for Agent, Pipeline, Router
});

testWidgets('player can write orchestration code and run it', (tester) async {
  // Given: player has written Dart code using the orchestration SDK
  // When: player taps Run
  // Then: code is sent to execution backend
  // And: agents are invoked per the player's logic
  // And: score is displayed across 4 dimensions
});
```

---

## Dependencies

### New Flutter Packages (Candidates)

| Package | Purpose | Notes |
|---------|---------|-------|
| `flutter_flow_chart` or custom | Pipeline node editor | May need custom implementation for our specific needs |
| `graphview` | Graph layout algorithms | For auto-arranging pipeline nodes |
| None (custom) | Agent palette | Simple draggable cards — standard Flutter |

### Cloud Function Dependencies

| Package | Purpose |
|---------|---------|
| `@anthropic-ai/sdk` | Claude API calls for pipeline execution |
| `firebase-functions` | Already in use |
| `firebase-admin` | Already in use |

---

## Infrastructure Changes

### LSP Server — Retained

The LSP server at `lsp.adventures-in-tech.world` is **retained** for Code Mode (Tier 3-4). The only change is updating the LSP workspace to include the orchestration SDK so players get code completion on `Agent`, `Pipeline`, `Router`, etc.

### Cost Impact

| Item | Before Pivot | After Pivot |
|------|-------------|-------------|
| LSP server (GCP e2-small) | ~$15/month | ~$15/month (unchanged) |
| Claude API (Clawd chat) | ~$5-10/month (Haiku) | ~$5-10/month (unchanged) |
| Claude API (pipeline execution) | $0 | ~$10-50/month (depends on usage) |
| **Total** | **~$20-25/month** | **~$30-75/month** |

Pipeline execution costs scale with player activity. Tier 1 simulated mode and token budgets per challenge keep costs bounded. Rate limiting (max N runs/player/hour) provides a hard cap.
