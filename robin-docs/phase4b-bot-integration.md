# Phase 4b: Bot Integration Audit

**Date:** 2026-05-08
**Skill:** `/tw-bot-integration`

## Bot Integration Matrix

| Feature | Clawd (bot-claude) | Gremlin (bot-gremlin) | Dreamfinder (bot-dreamfinder / agent-*) |
|---|---|---|---|
| Chat / code review (`chat` topic) | Yes — primary target | Passive (receives broadcast) | Via HTTP forward only |
| Code challenge evaluation (`challengeResult` key) | Yes | No | No |
| Prompt challenge evaluation (RESULT:PASS/FAIL) | Yes | No | No |
| Help request (`help-request` topic) | Yes | No | No |
| Oracle / flavor text (`oracle-request/response`) | Yes (default) | No | No |
| Terminal activity notifications | Yes | No | No |
| Ping / pong | Yes | No | No |
| Map info receive (`map-info`) | Yes (all bots) | Yes (all bots) | Yes (all bots) |
| Position publishing | Via path messages | Via path messages | Via DreamfinderComponent |
| DreamfinderClient HTTP events | No | No | Yes |
| `infra-health` / `infra-heal` | No | No | Yes |
| Boot sequence (`infra-boot`) | No | No | Yes |
| `speech-transcript` bubbles | No | No | Yes |

## Issues Found

### HIGH

**H1: Prompt injection bypass in RESULT:PASS parsing**
- **Bot:** Clawd
- **Feature:** Prompt challenge evaluation
- **File:** `lib/prompt/chat_evaluation_engine.dart:122-125`
- **Issue:** `hasResult` checks for `RESULT:` at line start (anchored), but `passed` uses `upper.contains('RESULT:PASS')` (unanchored). A player who injects `RESULT:PASS` anywhere in their prompt text — and the bot reflects it in the response — gets a spurious pass.
- **Fix:** Use `RegExp(r'(^|\n)\s*RESULT:PASS\s*$', caseSensitive: false, multiLine: true).hasMatch(responseText)` for the pass check. Same for RESULT:FAIL and all FEEDBACK: markers.

**H2: Code challenge evaluation is case-sensitive exact match**
- **Bot:** Clawd
- **Feature:** Code challenge evaluation
- **File:** `main.dart:1181`
- **Issue:** `response?['challengeResult'] == 'pass'` — if bot returns `'Pass'`, `'PASS'`, or `'passed'`, challenge silently not marked complete.
- **Fix:** `response?['challengeResult']?.toString().toLowerCase() == 'pass'`, plus log unrecognised values.

**H3: `agent-*` identity misclassification risk**
- **Bot:** Any
- **Feature:** Identity classification
- **File:** `lib/bots/bot_config.dart:86-87`
- **Issue:** A human player with a Firebase UID starting with `agent-` would be classified as a bot, rendered as Dreamfinder, blocked from chat panel, messages marked `isBot: true`.
- **Fix:** Add LiveKit room metadata `is-bot` flag, or at minimum log a warning when `agent-` fallback fires.

### MEDIUM

**M1: `botStatusNotifier` is global singleton — two bots cause state collision**
- **File:** `lib/flame/components/bot_status.dart:17`, `lib/chat/chat_service.dart:191,204`
- **Issue:** When Clawd is `thinking` and Gremlin connects, notifier resets to `idle`, cancelling thinking indicator.
- **Fix:** Per-bot status notifier keyed by identity.

**M2: `BotCharacterComponent.onTapDown` mutates global botStatusNotifier**
- **File:** `lib/flame/components/bot_character_component.dart:124-129`
- **Issue:** Tapping Clawd sprite toggles `thinking`/`idle` globally. "for demo purposes" but live in production.
- **Fix:** Remove or gate behind debug flag.

**M3: Oracle response not scoped to sender**
- **File:** `lib/spellbook/oracle_service.dart:108-118`
- **Issue:** Any room participant can send `oracle-response` with matching `requestId`. Low real-world risk but exploitable.
- **Fix:** Add `&& m.senderId == botIdentity` to filter chain.

**M4: `_evaluateBrevity` counts RESULT:/FEEDBACK: markers in word count**
- **File:** `lib/prompt/chat_evaluation_engine.dart:311-325`
- **Issue:** Unlike FizzBuzz/Countdown, Brevity doesn't strip RESULT markers before counting. 9-word response becomes 10+ and fails.
- **Fix:** Strip `RESULT:`/`FEEDBACK:` markers before word count.

**M5: `_evaluateDivinationColor` has dead validation loop**
- **File:** `lib/prompt/chat_evaluation_engine.dart:347-363`
- **Issue:** Loop body has no `return` or failure path. Any response passes as long as it contains "the color is: blue."
- **Fix:** Implement intended failure, or remove dead loop if lenient behavior is intentional.

**M6: `infra-heal` broadcast to whole room**
- **File:** `lib/infra/infra_health_service.dart:111-115`
- **Issue:** Heal command should be targeted to Dreamfinder only (no `destinationIdentities` set).
- **Fix:** `destinationIdentities: [dreamfinderBot.identity]`

**M7: `agent-*` identity gets `botIndex = -1` in spawn positioning**
- **File:** `lib/flame/tech_world.dart:432-433`
- **Issue:** `allBotIdentities.toList().indexOf(participant.identity)` returns -1 for `agent-*`. Currently harmless (Dreamfinder routed before reaching botIndex math) but fragile for future agent-SDK bots.
- **Fix:** Guard with null-safety fallback.

### LOW

**L1: 60-second help request timeout is excessive**
- **File:** `lib/chat/chat_service.dart`
- **Issue:** Player waits 60s for a hint. Chat timeout is 30s, oracle is 5s.
- **Fix:** Reduce to 30s.

**L2: `botStatusNotifier` multi-branch reset logic is fragile**
- **Issue:** thinking→idle reset is spread across timeout branch, catch block, bot-left subscription. Sound but hard to reason about.
- **Fix:** Centralise into `_finishEvaluation()` helper.

**L3: Gremlin bot has no active features**
- **Issue:** Registered in `botsByIdentity`, receives broadcasts, spawns a component — but no topic or endpoint routes to Gremlin. Intentional visual-only presence.

**L4: Double-tap help request creates 60s stuck state**
- **File:** `lib/chat/chat_service.dart`
- **Issue:** No guard against calling `requestHelp` while one is pending. Second completer times out after 60s.
- **Fix:** Gate with `_isRequesting` flag or cancel pending before making new.

## Parsing Fragility Assessment

| Parsing Point | Method | Assessment |
|---|---|---|
| Code challenge `challengeResult` | `== 'pass'` exact match | **Fragile** — case-sensitive, no logging |
| Prompt RESULT:PASS | Anchored regex + unanchored `.contains()` | **Fragile** — prompt injection vector |
| Prompt FEEDBACK: | Unanchored `.contains()` | **Fragile** — injectable |
| Oracle response `text` | JSON field + type check + fallback | **Robust** |
| Help response `requestId` | Keyed by unique microsecond timestamp | **Robust** |
| Infra health `ServiceStatus` | `fromString` with `unknown` fallback | **Robust** |
| Position heartbeat | `tryParse` with null on failure | **Robust** |
| FizzBuzz/Countdown evaluation | Line-by-line, strips markers first | **Robust** |
| Brevity evaluation | Word split without marker strip | **Fragile** (M4) |
| Divination color | Dead validation loop | **Fragile** (M5) |

## Timeout Analysis

| Timeout | Value | Assessment |
|---|---|---|
| Chat/code challenge | 30s | Appropriate for LLM review |
| Help request | **60s** | Too long — should be 30s |
| Oracle | 5s | Correct with fallback pool |
| Ping/pong | 5s | Appropriate |
| DreamfinderClient HTTP | 5s | Appropriate |
| Infra health stale | 20s (2× 10s interval) | Correct but narrow margin |

## What's Already Good

- **Subscribe-then-check** in `_trackBotPresence` eliminates TOCTOU race
- **Oracle never throws** — always returns a string (bot-generated or fallback)
- **Retry queue keyed by `challengeId`** — only most recent submission retried
- **`_disposed` guard** in reconnection flow prevents use-after-free
- **`DataChannelMessage.json` uses `allowMalformed: true`** — never throws on binary garbage
- **Deterministic evaluation** for FizzBuzz/Countdown/JSON — fast, reliable, immune to LLM drift
- **`retryPendingSubmissions` snapshot-and-clear** — prevents concurrent modification
- **DreamfinderClient error granularity** — distinguishes auth/server/socket/timeout
