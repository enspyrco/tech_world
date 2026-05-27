# Video & Audio Diagnostic Logging

## 1. What is being logged

Ten event types capture the full lifecycle of the audio-visual bubble pipeline:

### Periodic snapshot (the most important one)

**`AvPipelineSnapshot`** — emitted every 5 seconds for every participant (including yourself). One line per person tells you exactly where they sit in the pipeline:

```json
{"type":"av_pipeline_snapshot","participant":"alice","hasVideoTrack":true,"captureMethod":"directTrack","captureRetryCount":1,"framesCaptured":147,"framesDropped":2,"bubbleType":"video","audioEnabled":true,"distance":2,"isLocal":false,"timestamp":"2026-05-16T14:23:45.123"}
```

Fields:
- `participant` — LiveKit identity string
- `hasVideoTrack` — did LiveKit deliver a video track?
- `captureMethod` — which capture path is active: `ffi` (macOS), `directTrack` (Chrome MediaStreamTrackProcessor), `videoElement` (fallback HTMLVideoElement), `canvasCapture` (Dreamfinder iframe), or null if not yet initialized
- `captureRetryCount` — how many init attempts so far (max 10)
- `framesCaptured` / `framesDropped` — lifetime frame counters
- `bubbleType` — `video`, `player` (avatar initial), `bot`, or null (no bubble)
- `audioEnabled` — is this participant's audio track subscribed?
- `distance` — Chebyshev grid distance from you
- `isLocal` — true for your own publish state

### State transition events

| Event | When | Key fields |
|-------|------|-----------|
| `AvTrackSubscribed` | LiveKit delivers a video track | `participant` |
| `AvTrackUnsubscribed` | LiveKit drops a video track | `participant` |
| `AvCaptureInitialized` | Frame capture starts working | `participant`, `method`, `retryCount` |
| `AvCaptureInitFailed` | 10 retries exhausted, gave up | `participant`, `maxRetries`, `lastError` |
| `AvBubbleCreated` | Proximity bubble appears | `participant`, `bubbleType` |
| `AvBubbleRemoved` | Proximity bubble disappears | `participant` |
| `AvAudioGateChanged` | Audio enabled/disabled by proximity | `participant`, `enabled`, `distance` |
| `AvFrameDecodeError` | A video frame failed to decode | `participant`, `error` |
| `AvSpeakingChanged` | Speaker detection fires | `participant`, `speaking` |

## 2. Why it is being logged

The AV bubble pipeline has ~7 stages per participant, and a silent failure at any stage produces the same symptom: "I can't see/hear them." Without diagnostics, you cannot distinguish between:

- LiveKit never delivered the track (server/network issue)
- The track arrived but capture init failed after 10 retries (platform issue)
- Capture succeeded but frames are never produced (codec issue)
- Frames are produced but proximity distance is wrong (position desync)
- Proximity is correct but audio gating silently failed
- A bubble was created but it's the wrong type (PlayerBubble instead of VideoBubble)

The periodic snapshot solves this by showing the **full pipeline state** for every participant at a glance. When two people compare their snapshots, the asymmetry becomes immediately visible.

## 3. Where it is being logged

Three JSONL files on native platforms (macOS, iOS, Android). All in the app's documents directory:

```
~/Documents/tech_world_logs/
  events.log           ← all events (existing, now with rotation)
  av-pipeline.jsonl    ← AV diagnostic events only (new)
  errors.jsonl         ← warning+ severity from all systems (new)
```

**Not available on web** — the web platform has no filesystem access. On web, AV events still flow through the console sink in debug mode (`debugPrint`).

**AV errors appear in both files** — `av-pipeline.jsonl` and `errors.jsonl`. This is intentional. When debugging video issues, read `av-pipeline.jsonl` for the full timeline. When something's broken and you don't know what, scan `errors.jsonl` first.

## 4. How to read the logs

### Find the files

On macOS, the documents directory is typically:
```
~/Library/Containers/cc.imagineering.techWorld/Data/Documents/tech_world_logs/
```

Or, if running from Xcode/flutter in debug mode:
```
~/Documents/tech_world_logs/
```

### Read with standard tools

Each file is JSONL (one JSON object per line). Use `jq`, `grep`, or any text editor:

```bash
# Pretty-print the last 10 AV snapshots
tail -10 av-pipeline.jsonl | jq .

# Find all capture failures
grep 'av_capture_init_failed' av-pipeline.jsonl | jq .

# See all events for a specific participant
grep '"alice"' av-pipeline.jsonl | jq .

# Count frames captured per participant in the latest snapshots
grep 'av_pipeline_snapshot' av-pipeline.jsonl | tail -20 | jq '{participant, framesCaptured, captureMethod}'

# See all errors in the last hour
cat errors.jsonl | jq 'select(.timestamp > "2026-05-16T13:00:00")'
```

### Compare two clients

When the bug is asymmetric (works for Nick, not for Robin), have both clients enable AV diagnostics and then compare snapshots for the same participant at the same timestamp:

```bash
# Robin's view of alice
grep '"alice"' robin-av-pipeline.jsonl | grep 'av_pipeline_snapshot' | tail -1 | jq .
# → hasVideoTrack: false, captureMethod: null, bubbleType: "player"

# Nick's view of alice
grep '"alice"' nick-av-pipeline.jsonl | grep 'av_pipeline_snapshot' | tail -1 | jq .
# → hasVideoTrack: true, captureMethod: "directTrack", framesCaptured: 892, bubbleType: "video"
```

The diff tells you exactly where Robin's pipeline stalled.

## 5. What to look for when video or audio is not working

### "I can't see someone"

Read their latest `AvPipelineSnapshot` and check each field in order:

| Field | Bad value | Diagnosis |
|-------|-----------|-----------|
| `hasVideoTrack` | `false` | LiveKit never delivered the track. Check their camera permissions, network, or LiveKit server logs. |
| `captureMethod` | `null` | Track arrived but capture never initialized. Check `captureRetryCount` — if 10, look for `AvCaptureInitFailed` events. |
| `framesCaptured` | `0` | Capture initialized but no frames produced. Platform bug — the capture path is running but the video source isn't producing frames (muted remote track, codec mismatch). |
| `framesDropped` | High | Frames are arriving but being discarded (frame rate capping or decode failures). Check for `AvFrameDecodeError` events. |
| `bubbleType` | `"player"` | Bubble exists but it's the avatar-initial fallback, not video. Either `hideVideoBubbles` is on, or the track wasn't available when the bubble was created. Wait for `AvTrackSubscribed` → the bubble should auto-upgrade. |
| `bubbleType` | `null` | No bubble at all. Check `distance` — if > 5, you're too far. If ≤ 5, there's a bug in BubbleManager proximity logic. |

### "I can't hear someone"

| Field | Bad value | Diagnosis |
|-------|-----------|-----------|
| `audioEnabled` | `false` | You're more than 2 grid squares apart. Walk closer. |
| `audioEnabled` | `true` but no sound | Audio track is subscribed but the participant may be muted, or their mic permissions are denied. Check LiveKit server-side participant state. |
| `distance` | `-1` or unexpectedly large | Position desync — their position data isn't arriving. Check for `AvTrackSubscribed` (video works = data channel works) and look at heartbeat logs. |

### "It works for Nick but not for me"

Compare snapshots (see section 4). Common causes:
- **Different browsers**: Chrome has `MediaStreamTrackProcessor`, Safari doesn't. Check `captureMethod` — if Nick gets `directTrack` and you get `videoElement`, the fallback path may have a bug.
- **Different platforms**: macOS uses FFI (`ffi`), web uses JS interop. Completely different code paths.
- **Race condition**: One client subscribed to tracks before the other published. Check `AvTrackSubscribed` timestamps — if they never appear, the track was published before the subscription was set up.

### "It works sometimes but not always"

Enable AV diagnostics and leave them running. After the next failure, check:
1. `errors.jsonl` — any `AvCaptureInitFailed` or `AvFrameDecodeError`?
2. `av-pipeline.jsonl` — find the transition from working to broken. Look for `AvTrackUnsubscribed` followed by no `AvTrackSubscribed` (track lost, never recovered).
3. Check `captureRetryCount` in snapshots — if it's climbing toward 10, capture is struggling to initialize.

## 6. How to toggle the logs on and off

### Default: both on

AV diagnostics and error logging are **both on by default**. Logs rotate at 5MB × 3 files per sink, so the disk footprint is bounded (~60MB worst case across all three sinks). No UI toggle exists — diagnostics is an operator-tier concern, not a player surface.

### Disabling temporarily

To silence AV logging for a specific session, call the service directly from code:

```dart
import 'package:tech_world/diagnostics/diagnostics_service.dart';
import 'package:tech_world/utils/locator.dart';

final diagnostics = Locator.locate<DiagnosticsService>();
await diagnostics.setAvEnabled(false);    // stops AV pipeline writes
await diagnostics.setErrorLoggingEnabled(false); // stops error writes
```

Or ask Claude — the operator-tier admin path goes through the AI rather than UI. Claude can flip the SharedPreferences key from the shell, or edit the persisted value directly.

Both toggles are exposed as `ValueListenable<bool>` (`diagnostics.avEnabled`, `diagnostics.errorLoggingEnabled`). Producers (`BubbleManager`, `VideoBubbleComponent`, `LiveKitGameBridge`) read `.value` to gate AV-event dispatches; sinks read `.value` from their `enabledCheck` callbacks. The single owner pattern eliminates the dual-write invariant the prior module-level globals had.

The toggles are persisted in `SharedPreferences` and survive app restarts. Sinks check the toggle synchronously on every event, so flipping mid-session takes effect immediately — no restart needed.

### SharedPreferences keys

If you need to flip from outside the app (e.g., shell pre-launch):

| Key | Type | Default | Effect |
|-----|------|---------|--------|
| `avDiagnosticsEnabled` | `bool` | `true` | Controls AV pipeline sink + 5-second snapshot timer |
| `errorLoggingEnabled` | `bool` | `true` | Controls error sink |

### Why no UI toggle

The diagnostic data captures other participants' LiveKit identities, audio gate states, frame counts, and proximity timings. While the logs are local-only (never transmitted off-device) and the events are inside the trust boundary by design, exposing the toggle as a consumer-tier button invited the failure mode where any user could collect this data about others without thinking about it. Routing the admin path through Claude keeps the data flowing for operator debugging without creating a player-facing surface.

When Tech World ships publicly, the privacy policy should disclose local diagnostic logging: "this app maintains local diagnostic logs on your device for debugging purposes; logs are not transmitted off-device; rotation caps usage at ~60 MB."

## 7. When the logs will be deleted

### Automatic rotation

All three log files use **size-based rotation**:

- **Maximum file size**: 5 MB per file
- **Rotation count**: 3 (keeps `.1`, `.2`, `.3` suffixes)
- **Check frequency**: every 100 writes (not every write)

When a file exceeds 5 MB:
```
av-pipeline.jsonl.3  ← deleted
av-pipeline.jsonl.2  ← was .1
av-pipeline.jsonl.1  ← was current
av-pipeline.jsonl    ← new empty file
```

**Maximum disk usage**: 5 MB x 4 files x 3 sinks = 60 MB worst case. In practice, much less — `errors.jsonl` is tiny (low volume), and `av-pipeline.jsonl` only writes when diagnostics are enabled.

### Manual cleanup

Delete the files at any time — the sinks will recreate them on next write:

```bash
rm ~/Documents/tech_world_logs/av-pipeline.jsonl*
rm ~/Documents/tech_world_logs/errors.jsonl*
```

### App uninstall

On macOS sandboxed builds, the entire `tech_world_logs/` directory lives inside the app container and is removed when the app is uninstalled. On debug builds (unsandboxed), the logs persist in `~/Documents/tech_world_logs/` until manually deleted.
