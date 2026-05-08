# Phase 2: Challenge & Spellbook System Audit

**Date**: 2026-05-06
**Scope**: 41 educational challenges (23 code + 18 prompt), 18 words of power, 5 spell combos, 3 doors, evaluation engines, LSP integration, progress persistence.
**Type**: READ-ONLY audit.

---

## 1. Complete Inventory

### 1.1 Code Challenges (23) — `CodeChallengeId` enum

All 23 enum values have corresponding `Challenge` definitions in `predefined_challenges.dart`.

| # | CodeChallengeId | Title | Difficulty | wireName |
|---|-----------------|-------|------------|----------|
| 1 | helloDart | Hello Dart | beginner | hello_dart |
| 2 | sumList | Sum a List | beginner | sum_list |
| 3 | fizzbuzz | FizzBuzz | beginner | fizzbuzz |
| 4 | stringReversal | String Reversal | beginner | string_reversal |
| 5 | evenNumbers | Even Numbers | beginner | even_numbers |
| 6 | palindromeCheck | Palindrome Check | beginner | palindrome_check |
| 7 | wordCounter | Word Counter | beginner | word_counter |
| 8 | temperatureConverter | Temperature Converter | beginner | temperature_converter |
| 9 | findMaximum | Find Maximum | beginner | find_maximum |
| 10 | removeDuplicates | Remove Duplicates | beginner | remove_duplicates |
| 11 | binarySearch | Binary Search | intermediate | binary_search |
| 12 | fibonacciSequence | Fibonacci Sequence | intermediate | fibonacci_sequence |
| 13 | caesarCipher | Caesar Cipher | intermediate | caesar_cipher |
| 14 | anagramChecker | Anagram Checker | intermediate | anagram_checker |
| 15 | flattenList | Flatten List | intermediate | flatten_list |
| 16 | matrixSum | Matrix Sum | intermediate | matrix_sum |
| 17 | bracketMatching | Bracket Matching | intermediate | bracket_matching |
| 18 | mergeSort | Merge Sort | advanced | merge_sort |
| 19 | stackImplementation | Stack Implementation | advanced | stack_implementation |
| 20 | romanNumerals | Roman Numerals | advanced | roman_numerals |
| 21 | runLengthEncoding | Run Length Encoding | advanced | run_length_encoding |
| 22 | longestCommonSubsequence | Longest Common Subsequence | advanced | longest_common_subsequence |
| 23 | asyncDataPipeline | Async Data Pipeline | advanced | async_data_pipeline |

**Distribution**: 10 beginner, 7 intermediate, 6 advanced.

Every challenge has: title, description, starter code, difficulty. All are fully defined.

### 1.2 Prompt Challenges (18) — `PromptChallengeId` enum

All 18 enum values have corresponding `PromptChallenge` definitions in `predefined_prompt_challenges.dart`.

| # | PromptChallengeId | Title | School | Difficulty | Tier | wireName |
|---|-------------------|-------|--------|------------|------|----------|
| 1 | evocationFizzbuzz | The Unspoken FizzBuzz | evocation | beginner | deterministic | evocation_fizzbuzz |
| 2 | evocationCountdown | Precision Countdown | evocation | beginner | deterministic | evocation_countdown |
| 3 | evocationDiamond | Diamond Caster | evocation | intermediate | structural | evocation_diamond |
| 4 | divinationColor | The Hidden Hue | divination | beginner | deterministic | divination_color |
| 5 | divinationExtract | Data Archaeologist | divination | intermediate | structural | divination_extract |
| 6 | divinationPattern | Pattern Oracle | divination | advanced | behavioral | divination_pattern |
| 7 | transmutationBullets | Bullet Alchemist | transmutation | beginner | structural | transmutation_bullets |
| 8 | transmutationTable | Table Forge | transmutation | intermediate | structural | transmutation_table |
| 9 | transmutationJson | Format Shifter | transmutation | intermediate | deterministic | transmutation_json |
| 10 | illusionPirate | Storm on the Horizon | illusion | beginner | behavioral | illusion_pirate |
| 11 | illusionChild | Through Young Eyes | illusion | intermediate | behavioral | illusion_child |
| 12 | illusionDual | Two Minds, One Meal | illusion | advanced | behavioral | illusion_dual |
| 13 | enchantmentBrevity | Word Budget | enchantment | beginner | deterministic | enchantment_brevity |
| 14 | enchantmentFormal | Formality Breaker | enchantment | intermediate | behavioral | enchantment_formal |
| 15 | enchantmentContradict | The Loyalty Test | enchantment | advanced | behavioral | enchantment_contradict |
| 16 | conjurationGlorp | Wordsmith | conjuration | beginner | behavioral | conjuration_glorp |
| 17 | conjurationPattern | Pattern Teacher | conjuration | intermediate | behavioral | conjuration_pattern |
| 18 | conjurationLanguage | Language Architect | conjuration | advanced | behavioral | conjuration_language |

**Distribution**: 6 schools x 3 challenges each (1 beginner, 1 intermediate, 1 advanced per school).

Every challenge has: title, description, school, difficulty, generationSystemPrompt, evaluationCriteria, evaluationPrompt, tier. All fully defined.

**Tier distribution**: 4 deterministic, 4 structural, 10 behavioral.

### 1.3 Words of Power (18) — `WordId` enum

| # | WordId | Meaning | School | Element | Intensity | Role | Granted by |
|---|--------|---------|--------|---------|-----------|------|------------|
| 1 | ignis | fire | evocation | fire | 1 | substance | evocationFizzbuzz |
| 2 | tempus | time | evocation | fire | 1 | substance | evocationCountdown |
| 3 | crystallum | crystal | evocation | fire | 2 | substance | evocationDiamond |
| 4 | lumen | light | divination | water | 1 | substance | divinationColor |
| 5 | verum | truth | divination | water | 2 | modifier | divinationExtract |
| 6 | oraculum | oracle | divination | water | 3 | substance | divinationPattern |
| 7 | forma | shape | transmutation | earth | 1 | substance | transmutationBullets |
| 8 | structura | structure | transmutation | earth | 2 | substance | transmutationTable |
| 9 | muta | change | transmutation | earth | 2 | action | transmutationJson |
| 10 | umbra | shadow | illusion | air | 1 | substance | illusionPirate |
| 11 | speculum | mirror | illusion | air | 2 | substance | illusionChild |
| 12 | phantasma | phantom | illusion | air | 3 | substance | illusionDual |
| 13 | vinculum | bond | enchantment | spirit | 1 | substance | enchantmentBrevity |
| 14 | libera | freedom | enchantment | spirit | 2 | action | enchantmentFormal |
| 15 | dominus | mastery | enchantment | spirit | 3 | substance | enchantmentContradict |
| 16 | genesis | creation | conjuration | void_ | 1 | action | conjurationGlorp |
| 17 | exemplar | pattern | conjuration | void_ | 2 | substance | conjurationPattern |
| 18 | lexicon | language | conjuration | void_ | 3 | substance | conjurationLanguage |

### 1.4 Spell Combos (5) — `predefined_combinations.dart`

| # | Words | ComboKey (canonical) | Effect | Type | Magnitude |
|---|-------|---------------------|--------|------|-----------|
| 1 | ignis + lumen | ignis,lumen | Blazing Sight | illumination | 6 |
| 2 | tempus + libera | libera,tempus | Time Unbound | passage | 7 |
| 3 | crystallum + vinculum | crystallum,vinculum | Crystal Ward | protection | 5 |
| 4 | verum + oraculum | oraculum,verum | Oracle's Truth | revelation | 6 |
| 5 | ignis + muta + forma | forma,ignis,muta | Pyric Reshape | fireBurst | 8 |

All combo words reference valid `WordId` values. All are achievable through their respective prompt challenges.

### 1.5 Doors (3) — Wizard's Tower map only

| # | Position | Required Challenges | Chamber Transition |
|---|----------|--------------------|--------------------|
| D0 | (24, 36) | evocationFizzbuzz | Antechamber -> Great Hall |
| D1 | (24, 25) | evocationCountdown, divinationColor | Great Hall -> Upper Study |
| D2 | (24, 15) | evocationDiamond, divinationExtract | Upper Study -> Sanctum |

### 1.6 Terminals (Wizard's Tower) — 6 prompt-mode terminals

| # | Position | Challenge Assignment | Chamber |
|---|----------|---------------------|---------|
| T0 | (24, 41) | allPromptChallenges[0] = evocationFizzbuzz | Antechamber |
| T1 | (20, 31) | allPromptChallenges[1] = evocationCountdown | Great Hall left |
| T2 | (20, 21) | allPromptChallenges[2] = evocationDiamond | Upper Study left |
| T3 | (29, 31) | allPromptChallenges[3] = divinationColor | Great Hall right |
| T4 | (29, 21) | allPromptChallenges[4] = divinationExtract | Upper Study right |
| T5 | (24, 11) | allPromptChallenges[5] = divinationPattern | Sanctum |

---

## 2. Bijection Verification

### 2.1 PromptChallengeId <-> WordId bijection: PASS

The bijection is enforced at three levels:

1. **Compile-time**: `WordOfPower.challengeId` is typed as `PromptChallengeId` (not `String`), so referencing a nonexistent challenge fails to compile. `WordId` is an enum, so uniqueness within the word set is guaranteed by the type system.

2. **Runtime length assertion**: The test in `predefined_words_test.dart` asserts `|allWords| == |WordId.values| == |allPromptChallenges|` (all = 18). This confirms the two 18-element enums are in bijection through the `allWords` list.

3. **Coverage tests**: `predefined_words_test.dart` verifies:
   - Every prompt challenge has exactly one word (`challengeToWord` is total).
   - Every word maps back to a real prompt challenge.
   - `wordById` is total over `WordId.values`.
   - Intensity matches difficulty (1=beginner, 2=intermediate, 3=advanced).
   - Element matches `schoolElement` mapping.
   - Three words per school.

**Verdict**: The bijection is sound and well-tested.

### 2.2 CodeChallengeId <-> Challenge bijection: PASS

- `|CodeChallengeId.values| == |allChallenges|` (both = 23), tested in `code_challenge_id_test.dart`.
- Each `Challenge` instance has a typed `CodeChallengeId id` field.
- Wire names are unique and follow snake_case pattern (tested).

### 2.3 Code challenges do NOT award words: CORRECT

Code challenges (`CodeChallengeId`) have no connection to `WordId` or the spellbook. Only prompt challenges award words. This is by design -- code challenges are a separate progression track.

---

## 3. Wire Name Disjointness: PASS

The test in `code_challenge_id_test.dart` explicitly verifies:
- No `CodeChallengeId.wireName` equals any `PromptChallengeId.wireName`.

This is critical because both share the `completedChallenges` Firestore array in `ProgressService`. The disjointness test is source-of-truth-driven (iterates both enum `.values`), so adding a new challenge on either side that collides will fail the build.

Verification by inspection: all code challenge wire names are bare descriptors (`hello_dart`, `fizzbuzz`, etc.), while all prompt challenge wire names follow the `school_subject` pattern (`evocation_fizzbuzz`, `divination_color`, etc.). The naming convention itself makes collisions improbable, and the test makes them impossible.

---

## 4. Door Gating Achievability Analysis: PASS

### 4.1 Progression path through the Wizard's Tower

The Wizard's Tower has `terminalMode: TerminalMode.prompt`, so all 6 terminals present prompt challenges. The terminal-to-challenge assignment is `allPromptChallenges[i % allPromptChallenges.length]`, which for indices 0-5 maps to the first 6 prompt challenges.

**Door D0** (Antechamber exit): Requires `evocationFizzbuzz`.
- Terminal T0 is inside the Antechamber and presents `evocationFizzbuzz`.
- **Achievable**: Solve T0, earn IGNIS, speak IGNIS at D0.

**Door D1** (Great Hall exit): Requires `evocationCountdown` AND `divinationColor`.
- Terminal T1 (Great Hall left) presents `evocationCountdown`.
- Terminal T3 (Great Hall right) presents `divinationColor`.
- **Achievable**: Solve both T1 and T3, earn TEMPUS and LUMEN.
- Note: The door requires both challenges to be completed. The cast pipeline (`classifyCast`) only checks one word at a time against the door's required challenges list. A player speaks one word, which satisfies one challenge; then speaks the other. The door tracks completion via `ProgressService` -- each `CastPass` marks its challenge completed. The door unlocks when ALL required challenges are marked complete.
- **FINDING [P2-F1, medium]**: The `DoorComponent` rendering checks `doorData.isUnlocked` which is a single boolean, but `DoorData.requiredChallengeIds` can list multiple challenges. The cast pipeline (`performCast`) marks individual challenges as completed. **However, the logic that checks whether ALL required challenges are completed and flips `isUnlocked` is in the UI layer (`unlockDoor` in `tech_world.dart`), called from `SpeechCastOverlay.onCastSuccess`.** The `onCastSuccess` callback receives the `DoorData` and unconditionally sets `isUnlocked = true`. This means casting ANY one of the required words at a multi-requirement door unlocks it, even if the other requirements are not met. This is a **progression bypass bug for multi-challenge doors**.

**Door D2** (Upper Study exit): Requires `evocationDiamond` AND `divinationExtract`.
- Terminal T2 (Upper Study left) presents `evocationDiamond`.
- Terminal T4 (Upper Study right) presents `divinationExtract`.
- **Achievable** (subject to the same F1 issue above).

**Sanctum**: Terminal T5 presents `divinationPattern` (advanced). No door beyond the Sanctum.

### 4.2 The 12 unused prompt challenges

Only 6 of the 18 prompt challenges are assigned to terminals in the Wizard's Tower. The remaining 12 (all of transmutation, illusion, enchantment, and conjuration schools) have no terminals in any predefined map. They are defined and functional but have no in-game way to encounter them yet.

**FINDING [P2-F2, informational]**: 12 of 18 prompt challenges are orphaned -- no terminal presents them in any predefined map. The code challenge maps (The Library = 4 terminals, The Workshop = 2 terminals) use `TerminalMode.code` and present code challenges, not prompt challenges. The Open Arena, Four Corners, Simple Maze, and L-room have no terminals or only code terminals. This is likely intentional (future rooms/maps), but worth noting.

### 4.3 Combo achievability

All 5 predefined combos use words from different schools. A player who completes the required prompt challenges can learn the constituent words and cast combos via the free-cast system (speech at runestones, Phase 3). All combos are achievable.

---

## 5. Evaluation Reliability Assessment

### 5.1 Code challenge evaluation (bot-claude / Clawd)

Code challenges are submitted via the "Submit to Clawd" button in `CodeEditorPanel`. The submission flow:

1. Player writes code in `CodeForgeWeb` editor.
2. `onSubmit(code)` callback fires.
3. Code is sent to bot-claude via LiveKit data channel (the `chat` topic with metadata containing `challengeId`).
4. Bot evaluates and sends back a response on `chat-response` topic.
5. The response is parsed for `RESULT:PASS` / `RESULT:FAIL` markers (same `ChatEvaluationEngine.parseResponse` as prompt challenges).

**Bot offline handling**: The help button in `CodeEditorPanel` checks `BotStatus` via `botStatusNotifier`. When `BotStatus.absent`, the help button is disabled (greyed out). However, the **Submit button has no bot-status gate** -- a player can submit code when the bot is offline.

**FINDING [P2-F3, medium]**: The "Submit to Clawd" button is always enabled regardless of bot status. When the bot is offline, submission will silently fail (the LiveKit message goes nowhere, no response comes back, and the player sees no feedback -- no timeout, no error message, no indication of failure). The help button correctly gates on `BotStatus.absent`, but the submit button does not.

### 5.2 Prompt challenge evaluation (ChatEvaluationEngine)

`ChatEvaluationEngine` sends the player's prompt to the bot via `ChatService.sendMessage`, with metadata containing `promptChallengeId` (as wire-format `String`). The bot responds with `RESULT:PASS` or `RESULT:FAIL` plus optional `FEEDBACK:` markers.

**Response parsing** (`parseResponse`):
- `RESULT:` marker must appear at line start (regex: `(^|\n)\s*RESULT:`) -- reduces risk of player embedding `RESULT:PASS` in their prompt.
- Case-insensitive matching.
- Empty response -> fail with `CastFeedback.unclear`.
- No `RESULT:` marker -> fail with `CastFeedback.fizzled`.
- Feedback categories: `FEEDBACK:BACKFIRED`, `FEEDBACK:FIZZLED`, `FEEDBACK:UNCLEAR`. Default: fizzled.

**FINDING [P2-F4, low]**: The `RESULT:` marker check uses `(^|\n)\s*RESULT:` regex to require line-start positioning, which defends against embedding `RESULT:PASS` mid-sentence. However, a player could craft a prompt that causes the bot to output `RESULT:PASS` at the start of a line even for an incorrect solution. The single-round-trip architecture (bot both generates AND evaluates in one message) is acknowledged as MVP -- the doc comment says "The two-call separation (generation -> judge) comes later." This is a known trade-off, not a bug.

**FINDING [P2-F5, low]**: The `ChatEvaluationEngine` has no timeout. If the bot is slow or hangs, the `evaluate` method will await indefinitely on `_chatService.sendMessage`. There is no `Future.timeout` wrapper. The `OracleService` has a 5-second timeout with fallback, but the evaluation engine does not.

### 5.3 Evaluation tier implementation gap

**FINDING [P2-F6, medium]**: The `EvaluationTier` enum defines three tiers (`deterministic`, `structural`, `behavioral`) with clear semantics documented in the class, but `ChatEvaluationEngine.evaluate` does not branch on `challenge.tier` at all. All challenges go through the same single-round-trip bot evaluation regardless of tier. The deterministic challenges (FizzBuzz output, countdown, JSON format, word count) that could be checked programmatically without an LLM are instead sent to the bot. This means:
- Deterministic challenges are unreliable (LLM may misjudge deterministic criteria).
- All challenges fail when the bot is offline (no local fallback for deterministic checks).
- The `tier` field is metadata only, not functional.

### 5.4 Spell slot system

`SpellSlotService` implements a regenerating resource pool that limits cast attempts. Configuration per difficulty: beginner (5 slots, 2min regen), intermediate (3 slots, 3min regen), advanced (3 slots, 5min regen, 2 slots per cast). Progression bonuses: +1 max slot per 3 challenges, -30s regen per 5 challenges.

The service handles offline regen (calculates elapsed time on restore), serialization/deserialization, and has injected clock for testing. Well-structured.

---

## 6. LSP Integration Analysis

### 6.1 Architecture

The code editor uses `CodeForgeWeb` (from `code_forge_web` package) with LSP support via WebSocket:

- **Server**: `wss://lsp.adventures-in-tech.world` (nginx -> `lsp-ws-proxy` -> `dart language-server --protocol=lsp`)
- **Workspace**: `/opt/lsp-workspace` (pre-configured with pubspec.yaml and analysis_options.yaml)
- **File URIs**: Each editor session creates a unique file: `file:///opt/lsp-workspace/lib/{challenge_wireName}_{timestamp}.dart`

### 6.2 Capabilities

Enabled: code completion, hover info, signature help.
Disabled: semantic highlighting, code action, document color, document highlight, code folding, inlay hint, go-to-definition, rename.

### 6.3 Error handling

- **Constructor errors** (malformed URL): caught synchronously, `lspConfig` stays `null`, editor falls back to plain text mode.
- **Async failures** (DNS, WebSocket connect): handled internally by `CodeForgeWebController` -- editor falls back to plain text.
- **Comment in code**: "Async WebSocket failures (e.g. DNS) are handled internally by CodeForgeWebController -- the editor falls back to plain text."

**FINDING [P2-F7, low]**: The LSP config catches synchronous constructor errors but uses a bare `catch (_)` with no logging. If the LSP URL becomes malformed through a config change, the failure is silently swallowed. A `_log.warning` would aid debugging.

### 6.4 Session isolation

Good: Each editor session uses a unique file URI with timestamp (`{wireName}_{timestamp}.dart`), so concurrent sessions don't collide on the LSP server.

---

## 7. Progress Persistence

### 7.1 Architecture

`ProgressService` stores completion as a `Set<String>` in memory, persisted to Firestore at `users/{uid}.completedChallenges` (array of wire-format strings). `SpellbookService` stores learned words as a `Set<WordId>` in memory, persisted to `users/{uid}.learnedWords` (array of wire-format strings).

### 7.2 Consistency model

Both services use **optimistic local update with rollback on Firestore failure**:
1. Add to local cache.
2. Emit stream update.
3. Write to Firestore with `FieldValue.arrayUnion` (idempotent).
4. On failure: remove from local cache, re-emit, rethrow.

This is sound for single-device usage. The `arrayUnion` makes writes idempotent at the Firestore level.

### 7.3 Desync risks

**FINDING [P2-F8, low]**: No real-time Firestore listener. The services do a one-time `loadProgress` / `loadSpellbook` at startup. If a player completes a challenge on device A, device B won't see the completion until it restarts. The optimistic-update-with-rollback pattern is correct for single-device, but multi-device desync is possible. Low priority because Tech World is primarily single-device.

### 7.4 Side-effect ordering

`applyCastSuccessEffects` runs `learnWord` before `markChallengeCompleted`. The comment explains why: if spellbook write fails, the challenge stays re-castable (not yet marked completed). If progress write fails, the word is learned but the challenge can be re-cast (idempotent learnWord). Either service being `null` is handled gracefully (logged and skipped). Both paths are tested, including null services, idempotency, and the full bijection smoke test.

---

## 8. Difficulty Progression Analysis

### 8.1 Code challenges

**Beginner (10)**: Hello Dart, Sum List, FizzBuzz, String Reversal, Even Numbers, Palindrome Check, Word Counter, Temperature Converter, Find Maximum, Remove Duplicates.

These are appropriate beginner tasks -- basic string/list manipulation, simple conditionals, iteration.

**Intermediate (7)**: Binary Search, Fibonacci, Caesar Cipher, Anagram Checker, Flatten List, Matrix Sum, Bracket Matching.

Good intermediate level -- algorithms requiring recursion, nested data, state tracking.

**Advanced (6)**: Merge Sort, Stack Implementation, Roman Numerals, Run Length Encoding, LCS, Async Data Pipeline.

Good advanced level -- divide-and-conquer, data structures, dynamic programming, async/await.

**FINDING [P2-F9, informational]**: The beginner tier has 10 challenges while intermediate has 7 and advanced has 6. This is a reasonable pyramid shape for a learning game (more on-ramps, fewer gates). However, the difficulty gap between the easiest beginner (Hello Dart) and the hardest beginner (Palindrome Check, Remove Duplicates) is significant. Consider whether some beginner challenges might be better classified as intermediate.

### 8.2 Prompt challenges

Each school has exactly 3 challenges: 1 beginner, 1 intermediate, 1 advanced. The progression within each school is well-designed:

- **Evocation** (precise instruction): FizzBuzz without keywords -> zero-padded countdown -> ASCII diamond. Progresses from avoiding words to precise formatting to spatial pattern.
- **Divination** (extraction): yes/no questions for a color -> structured data extraction -> pattern deduction. Good escalation.
- **Transmutation** (format conversion): prose to bullets -> data to table -> text to JSON. Clean progression.
- **Illusion** (persona): pirate weather -> child's perspective -> dual perspectives. Nice difficulty curve.
- **Enchantment** (constraint breaking): word budget (< 10 words) -> formality breaking -> loyalty contradiction. Excellent progression -- each level is a harder constraint to overcome.
- **Conjuration** (few-shot): teach a word -> teach a pattern -> teach a language. Well-designed escalation.

**Verdict**: Prompt challenge difficulty progression is excellent.

### 8.3 Wizard's Tower door gating progression

The tower progression uses only evocation and divination:
1. Antechamber: evocationFizzbuzz (beginner) -- earn IGNIS to exit.
2. Great Hall: evocationCountdown + divinationColor (both beginner) -- earn TEMPUS + LUMEN to exit.
3. Upper Study: evocationDiamond + divinationExtract (both intermediate) -- earn CRYSTALLUM + VERUM to exit.
4. Sanctum: divinationPattern (advanced) -- terminal only, no door beyond.

The progression goes beginner -> beginner (two schools) -> intermediate (two schools) -> advanced. This is a well-designed difficulty ramp.

---

## 9. Test Coverage Summary

### 9.1 Challenge/spellbook tests found

| Test File | What it covers |
|-----------|----------------|
| `test/editor/code_challenge_id_test.dart` | Wire name round-trip, uniqueness, snake_case format, count match, disjointness with PromptChallengeId |
| `test/prompt/prompt_challenge_id_test.dart` | Wire name round-trip, uniqueness, school_subject format, count match |
| `test/prompt/evaluation_engine_test.dart` | MockEvaluationEngine cycling, feedback categories |
| `test/prompt/chat_evaluation_engine_test.dart` | Metadata JSON-encodability, wire-format strings, parseResponse (PASS/FAIL/feedback markers) |
| `test/prompt/spell_slot_service_test.dart` | (exists, not read -- likely slot consumption/regen) |
| `test/spellbook/predefined_words_test.dart` | Bijection, intensity, element mapping, 3 per school, WordId parse |
| `test/spellbook/spell_algebra_test.dart` | 2x2 confidence lattice, noise floor, un-learned words, order independence, ComboKey validation, SpellEffectId, magnitude invariant |
| `test/spellbook/cast_effects_test.dart` | applyCastSuccessEffects: word granting, progress marking, null services, idempotency, full bijection smoke test |
| `test/spellbook/voice_cast_acceptance_test.dart` | classifyCast + performCast: CastPass, NoMatch, NotLearned, WrongDoor, normalisation, multi-challenge doors, side-effect correctness |
| `test/spellbook/spellbook_service_test.dart` | (exists, not read) |
| `test/spellbook/spellbook_service_rollback_test.dart` | (exists, not read) |
| `test/spellbook/oracle_service_test.dart` | (exists, not read) |
| `test/spellbook/spellbook_panel_test.dart` | (exists, not read) |
| `test/flame/maps/door_data_test.dart` | DoorData JSON round-trip, forward-compat with unknown challenges, equality |
| `test/progress/progress_service_test.dart` | Load, mark, idempotency, stream, dispose, user isolation |

**Verdict**: Strong test coverage across the challenge and spellbook system. The bijection, wire format, cast pipeline, and side-effects are all well-tested.

---

## 10. Priority-Ranked Issues

### HIGH

None.

### MEDIUM

**[P2-F1] Multi-challenge door bypass** (`tech_world.dart` / `speech_cast_overlay.dart`)
The `SpeechCastOverlay.onCastSuccess` callback calls `widget.onCastSuccess(door)` which triggers `TechWorld.unlockDoor(door)`, which sets `door.isUnlocked = true` and removes the barrier. This happens on ANY `CastPass`, even if the door requires multiple challenges and only one has been completed. A player at door D1 (requires evocationCountdown AND divinationColor) who casts TEMPUS (satisfying only evocationCountdown) will have the door fully unlocked, bypassing the divinationColor requirement.

**Fix**: `unlockDoor` (or the `onCastSuccess` callback) should check whether ALL of the door's `requiredChallengeIds` are marked completed in `ProgressService` before setting `isUnlocked = true`. If not all are met, show feedback like "One seal broken, but the door still holds" instead of opening.

**[P2-F3] Submit button not gated on bot status** (`code_editor_panel.dart`)
The "Submit to Clawd" button is enabled even when `BotStatus.absent`. Submission silently fails with no feedback.

**Fix**: Gate the submit button on `botStatusNotifier != BotStatus.absent`, matching the help button's behavior. Alternatively, show an error/timeout message if no response arrives within N seconds.

**[P2-F6] EvaluationTier not functional** (`chat_evaluation_engine.dart`)
The `tier` field on each `PromptChallenge` is ignored by the evaluation engine. All challenges go through the single-round-trip bot path. Deterministic challenges (FizzBuzz output verification, countdown format checking, JSON validation, word counting) could be checked programmatically, providing faster and more reliable evaluation.

**Fix**: Implement tier-aware evaluation in `ChatEvaluationEngine.evaluate`: for `deterministic` tier, run programmatic checks first (and potentially skip the bot entirely). For `structural`, try programmatic checks then fall back to bot. For `behavioral`, always use the bot.

### LOW

**[P2-F4] RESULT:PASS spoofing risk**
A player could potentially craft a prompt that causes the bot to output `\nRESULT:PASS` even for an incorrect solution. The line-start regex mitigates but doesn't eliminate this. Known trade-off of the single-round-trip MVP architecture.

**[P2-F5] No timeout on evaluation**
`ChatEvaluationEngine.evaluate` has no timeout. If the bot hangs, the UI awaits forever.

**[P2-F7] Silent catch in LSP config** (`code_editor_panel.dart`)
`catch (_)` swallows LSP config errors without logging.

**[P2-F8] No real-time Firestore sync**
Multi-device progress desync is possible. Low priority for current single-device usage.

### INFORMATIONAL

**[P2-F2] 12 orphaned prompt challenges**
12 of 18 prompt challenges have no terminal in any predefined map. Only evocation (3) and divination (3) challenges are reachable in the Wizard's Tower. The 4 remaining schools (transmutation, illusion, enchantment, conjuration) are fully defined but have no in-game presence yet. This limits spellbook acquisition to 6 of 18 words.

**[P2-F9] Beginner code challenge difficulty spread**
The gap between "Hello Dart" and "Palindrome Check" within the beginner tier is notable.

---

## 11. Architecture Quality Notes

Several things are done exceptionally well:

1. **Branded types** (`ComboKey`, `SpellEffectId`, `CodeChallengeId`, `PromptChallengeId`, `WordId`): prevent stringly-typed bugs at compile time. The `ComboKey.fromCanonical` validation is particularly thorough.

2. **Sealed class hierarchies** (`DoorCastResult`, `FreeCastResult`, `CastResult`): disjoint by design, exhaustive switching enforced by the compiler. The doc comment explicitly notes that `DoorCastResult` and `FreeCastResult` are intentionally separate so the compiler proves routing.

3. **Optimistic update with rollback**: Both `SpellbookService` and `ProgressService` implement this pattern correctly with `FieldValue.arrayUnion` for Firestore idempotency.

4. **Pure classification functions**: `classifyCast` and `classifyFreeCast` are pure (no I/O), making them trivially testable. Side effects are separated into `performCast` / `applyCastSuccessEffects`.

5. **Test quality**: Tests are well-structured, testing invariants rather than implementations. The bijection test is a single length assertion plus type-system guarantees. The voice cast acceptance test exercises the full pipeline without touching browser STT.

6. **Forward compatibility**: `DoorData.fromJson` and `SpellbookService.loadSpellbook` both handle unknown wire formats gracefully (log and skip), enabling newer clients to write data older clients can still load.
