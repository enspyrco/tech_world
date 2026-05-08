# Architectural Refactor 1: Extract BubbleManager from TechWorld

**Branch:** `audit/extract-bubble-manager`
**Effort:** Large
**Fixes:** CR-1 (god object), dead ProximityService duplication, type-switching dispatch, untestable bubble logic

---

## Problem

`TechWorld` (2081 lines, 30+ fields) is a Mediator that grew into a God Object. Among its 10+ responsibilities, **bubble lifecycle management** is the most self-contained — it has clear inputs (player positions, LiveKit participants), clear outputs (visible bubble components), and well-defined physics (repulsion, merge detection). Extracting it reduces TechWorld by ~400 lines and makes bubble physics independently testable.

---

## Current Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      TechWorld (2081 lines)                   │
│                                                               │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐   │
│  │ Map Lifecycle│  │ LiveKit Subs │  │ Bubble Lifecycle   │   │
│  │ loadMap()    │  │ connectTo()  │  │ _playerBubbles     │   │
│  │ _loadMap     │  │ _onPosition  │  │ _bubbleDisplace    │   │
│  │ Components() │  │ _onTrack     │  │ _audioEnabled      │   │
│  │ _removeMap   │  │ _onJoined    │  │ _lastPlayerGrid    │   │
│  │ Components() │  │ _onLeft      │  │                    │   │
│  └─────────────┘  │ _onSpeaking  │  │ _updatePlayerBub() │   │
│                    └──────────────┘  │ _setBubbleOpacity() │   │
│  ┌─────────────┐                     │ _updateParticipant │   │
│  │ Editor Mode │  ┌──────────────┐  │   Audio()          │   │
│  │ enterEditor │  │ Bot Handling │  │ _updateBubblePos() │   │
│  │ exitEditor  │  │ _spawnBots   │  │ _applyBubbleRep()  │   │
│  │ _onEditor   │  │ _onBotJoin   │  │ _updateBubbleField│   │
│  │ Changed()   │  │ _dreamfinder │  │ _updateMergedVideo│   │
│  └─────────────┘  └──────────────┘  │ _findMergeGroup() │   │
│                                      │ _createBubbleFor() │   │
│  ┌─────────────┐  ┌──────────────┐  │ _createLocalBub()  │   │
│  │ Pathfinding │  │ Speech/Door  │  │ _createDFBubble()  │   │
│  │ _pathComp   │  │ _handleSpeech│  │ _hasVideoTrack()   │   │
│  │ onTap       │  │ unlockDoor() │  │ _refreshBubble()   │   │
│  └─────────────┘  │ _recompute   │  │ _downgradeVideo()  │   │
│                    │ NearbyDoor() │  │ _initDFBridge()    │   │
│  ┌─────────────┐  └──────────────┘  │ _loadShaders() ×3  │   │
│  │ Tileset     │                     └───────────────────┘   │
│  │ prefetch    │                                              │
│  │ _tilesetByte│      ← EVERYTHING IN ONE CLASS →            │
│  └─────────────┘                                              │
└─────────────────────────────────────────────────────────────┘
```

The bubble subsystem uses **14 private fields** and **16 private methods** in TechWorld. It also contains inline Chebyshev distance computation that duplicates the (now deleted) ProximityService.

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  TechWorld (~1650 lines)                      │
│                                                               │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐   │
│  │ Map Lifecycle│  │ LiveKit Subs │  │ BubbleManager     │   │
│  │             │  │             │  │ (ref only)         │   │
│  └─────────────┘  └──────────────┘  └────────┬──────────┘   │
│                                               │               │
│  ┌─────────────┐  ┌──────────────┐           │               │
│  │ Editor Mode │  │ Bot Handling │           │               │
│  └─────────────┘  └──────────────┘           │               │
│                                               │               │
│  ┌─────────────┐  ┌──────────────┐           │               │
│  │ Pathfinding │  │ Speech/Door  │           │               │
│  └─────────────┘  └──────────────┘           │               │
│                                               │               │
│  ┌─────────────┐                              │               │
│  │ Tileset     │                              │               │
│  └─────────────┘                              │               │
└───────────────────────────────────────────────┼───────────────┘
                                                │
                    ┌───────────────────────────┘
                    ▼
┌─────────────────────────────────────────────────────────────┐
│               BubbleManager (~400 lines)                     │
│               lib/flame/bubble_manager.dart                   │
│                                                               │
│  Fields:                                                      │
│  ├─ _playerBubbles: Map<String, PositionComponent>           │
│  ├─ _bubbleDisplacements: Map<String, Vector2>               │
│  ├─ _audioEnabledParticipants: Set<String>                   │
│  ├─ _lastPlayerGridPosition: Point<int>?                     │
│  ├─ _bubbleField: BubbleFieldComponent?                      │
│  ├─ _mergedBubble: MergedVideoBubbleComponent?               │
│  ├─ _shaderProgram: FragmentProgram? (×3)                    │
│  └─ _dreamfinderAvatarBridge: DreamfinderAvatarBridge?       │
│                                                               │
│  Public API:                                                  │
│  ├─ loadShaders() → Future<void>                             │
│  ├─ update(dt, playerGrid, entities) → void                  │
│  ├─ createBubble(playerId, participant?) → PositionComponent │
│  ├─ refreshBubble(playerId) → void                           │
│  ├─ initDreamfinderBridge(liveKit) → void                    │
│  ├─ dispose() → void                                         │
│  └─ nearbyLockedDoor (stays in TechWorld — door logic)       │
│                                                               │
│  Internal:                                                    │
│  ├─ _updateProximity(playerGrid, entities)                   │
│  ├─ _setBubbleOpacity(bubble, distance)                      │
│  ├─ _updateParticipantAudio(playerId, distance)              │
│  ├─ _updateBubblePositions(dt)                               │
│  ├─ _applyBubbleRepulsion(dt)                                │
│  ├─ _updateBubbleField(centres, priority)                    │
│  ├─ _updateMergedVideo(priority)                             │
│  └─ _findMergeGroup(bubbles) → List<String>                  │
│                                                               │
│  Static:                                                      │
│  ├─ chebyshevDistance(Point<int>, Point<int>) → int           │
│  └─ (replaces inline computation + dead ProximityService)    │
└─────────────────────────────────────────────────────────────┘
```

---

## What Moves

| From TechWorld | To BubbleManager | Notes |
|---------------|-----------------|-------|
| `_playerBubbles` | `_playerBubbles` | The central map |
| `_bubbleDisplacements` | `_bubbleDisplacements` | Physics state |
| `_audioEnabledParticipants` | `_audioEnabledParticipants` | Audio tracking |
| `_lastPlayerGridPosition` | `_lastPlayerGridPosition` | Frame skip optimization |
| `_bubbleField` | `_bubbleField` | Metaball component |
| `_mergedBubble` | `_mergedBubble` | Merged video component |
| `_shaderProgram` (×3) | `_shaderProgram` (×3) | Shader refs |
| `_dreamfinderAvatarBridge` | `_dreamfinderAvatarBridge` | 3D avatar capture |
| `_localPlayerBubbleKey` | `_localPlayerBubbleKey` | Constant |
| `_visualThreshold` | `_visualThreshold` | Constant |
| `_audioThreshold` | `_audioThreshold` | Constant |
| `_bubbleOffset` | `_bubbleOffset` | Constant |
| `_mergeThreshold` | `_mergeThreshold` | Constant |
| `_bubbleDiameter` | `_bubbleDiameter` | Constant |
| `_maxTetherDistance` | `_maxTetherDistance` | Constant |
| `_repulsionDamping` | `_repulsionDamping` | Constant |
| `_updatePlayerBubbles()` | `update()` | Main entry point |
| `_setBubbleOpacity()` | `_setBubbleOpacity()` | |
| `_updateParticipantAudio()` | `_updateParticipantAudio()` | |
| `_updateBubblePositions()` | `_updateBubblePositions()` | |
| `_applyBubbleRepulsion()` | `_applyBubbleRepulsion()` | |
| `_updateBubbleField()` | `_updateBubbleField()` | |
| `_updateMergedVideo()` | `_updateMergedVideo()` | |
| `_findMergeGroup()` | `_findMergeGroup()` | |
| `_createBubbleForPlayer()` | `createBubble()` | Public |
| `_createLocalPlayerBubble()` | `_createLocalBubble()` | |
| `_createDreamfinderVideoBubble()` | `_createDreamfinderBubble()` | |
| `_hasVideoTrack()` | `_hasVideoTrack()` | |
| `_refreshBubbleForPlayer()` | `refreshBubble()` | Public |
| `_downgradeVideoBubble()` | `_downgradeBubble()` | |
| `_initDreamfinderAvatarBridge()` | `initDreamfinderBridge()` | Public |
| `_loadVideoBubbleShader()` | `loadShaders()` | Combined |
| `_loadMetaballShader()` | (merged into loadShaders) | |
| `_loadMergedVideoShader()` | (merged into loadShaders) | |

## What Stays in TechWorld

- `nearbyLockedDoor` + `_recomputeNearbyLockedDoor()` — door proximity is game logic, not bubble logic
- `playerGridPosition` ValueNotifier — consumed by UI, not just bubbles
- All map lifecycle, editor mode, pathfinding, speech, bot handling, LiveKit subscriptions

## Interface Between TechWorld and BubbleManager

```dart
// In TechWorld.update():
_bubbleManager.update(
  dt: dt,
  playerGrid: _userPlayerComponent.miniGridPosition,
  localPlayer: _userPlayerComponent,
  remotePlayers: _otherPlayerComponentsMap,
  bots: _botCharacterComponents,
  dreamfinder: _dreamfinderComponent,
  dreamfinderIdentity: _dreamfinderIdentity,
  liveKitService: _liveKitService,
  addComponent: add,        // callback to add to World
  removeComponent: remove,  // callback to remove from World
);
```

BubbleManager does NOT extend Component — it's a plain class that TechWorld owns. It receives callbacks to add/remove components from the World, keeping the Flame component tree ownership in TechWorld.

## Migration Steps

1. Create `lib/flame/bubble_manager.dart` with the class shell
2. Move constants first (zero risk)
3. Move fields one at a time, updating TechWorld references
4. Move private methods, starting from leaves (no internal callers)
5. Move `_updatePlayerBubbles` last (the entry point)
6. Add `static int chebyshevDistance(Point<int> a, Point<int> b)` method
7. Combine 3 shader loaders into one `loadShaders()` method
8. Update TechWorld.update() to delegate to BubbleManager
9. Run `flutter analyze` + `flutter test` after each step
10. Write BubbleManager unit tests (repulsion, merge detection, opacity)

## Testability Gains

After extraction, BubbleManager can be tested with:
- **Repulsion physics**: create 2 mock bubbles at known positions, call `_applyBubbleRepulsion`, verify displacement
- **Merge detection**: create N bubbles at known positions, call `_findMergeGroup`, verify connected components
- **Opacity curve**: verify `chebyshevDistance` + opacity mapping
- **Audio threshold**: verify enable/disable calls at boundary distances
- **Shader loading**: verify graceful degradation when shaders fail

None of these tests are currently possible because the logic is entangled in TechWorld's 2081-line god object.
