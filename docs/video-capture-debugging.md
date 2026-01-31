# Video Capture Debugging Notes

## Problem Summary

Video bubbles in tech_world show remote participants' video feeds. The implementation works in debug mode but had issues in release mode (dart2js). Additionally, there's a lifecycle bug where video works on first encounter but fails when re-entering proximity.

## Architecture

```
LiveKit VideoTrack → Web: HTMLVideoElement + createImageBitmap → ui.Image → Flame Canvas
                   → macOS: FFI + RTCVideoRenderer → shared memory → ui.Image → Flame Canvas
                   → iOS/Android: Not implemented (shows placeholder)
```

### Key Files

- `lib/flame/components/video_bubble_component.dart` - Flame component that renders video
- `lib/native/video_frame_web.dart` - Web implementation using createImageBitmap
- `lib/native/video_frame_ffi.dart` - macOS FFI implementation
- `lib/flame/tech_world.dart` - Creates/removes bubbles based on proximity

## Issues Fixed (PRs #71, #72, #73)

### 1. Release Mode Crash (PR #71)
**Problem**: `(mediaStreamTrack as dynamic).jsTrack` failed in release mode due to dart2js minification.

**Solution**: Get track ID from public API (`mediaStreamTrack.id`) which survives minification, then find existing video elements in DOM.

### 2. Remote Participant Video (PR #72)
**Problem**: Remote participants' video not showing because track IDs differ between LiveKit SID and WebRTC track ID.

**Solution**:
- Try both `mediaStreamTrack.id` AND `track.sid` when searching for video elements
- Use `track.mediaStream.jsStream` to create video elements (more reliable than `jsTrack`)
- Multiple fallback chain for robustness

### 3. iOS Crash (PR #73)
**Problem**: FFI code threw `UnsupportedError` at module load time on iOS, crashing the app.

**Solution**: Made native library loading lazy and added `_isSupported` check for macOS-only functionality.

## Current Bug: Video Disappears on Re-entry

### Symptoms
- Video shows correctly when first encountering a participant
- Moving away (out of proximity) and coming back → video no longer shows
- Happens on web (both mobile and desktop)

### Suspected Cause
When a player moves out of proximity:
1. `VideoBubbleComponent` is removed from the game
2. `onRemove()` calls `_disposeCapture()` which disposes the web capture
3. The web capture's `dispose()` removes the video element from DOM OR nulls srcObject

When player comes back into proximity:
1. New `VideoBubbleComponent` is created
2. `_initializeWebCapture()` tries to find existing video element
3. **BUG**: Either the video element was removed, or it exists but is in a bad state

### Investigation Needed

1. **Check if video element persists**: Does LiveKit keep the video element in DOM when we dispose our capture?

2. **Check srcObject state**: When we call `createFromExistingVideo`, is the video's srcObject still valid?

3. **Check track subscription**: Is the track still subscribed when re-entering proximity?

4. **Timing issue**: Maybe the new bubble is created before the old one is fully disposed?

### Code Flow to Trace

```
TechWorld._onProximityEvent()
  → if exit: remove bubble from game
  → if enter: _createBubbleForPlayer()
      → VideoBubbleComponent created
      → update() called repeatedly
      → _initializeCapture() on retry timer
      → _initializeWebCapture()
      → _initializeWebCaptureAsync()
          → findVideoElementByTrackId() - DOES THIS FIND IT?
          → createFromExistingVideo() - DOES THIS WORK?
          → OR createFromStream() - DOES THIS WORK?
```

### Potential Fixes to Try

1. **Don't dispose video element**: In `WebVideoFrameCapture.dispose()`, don't remove the video element if we didn't create it (`ownsElement` flag was removed - may need to restore)

2. **Re-attach to existing track**: Instead of finding video element by track ID, get a fresh reference from the LiveKit participant

3. **Keep capture alive**: Don't dispose the capture when bubble is removed, cache it by participant ID

4. **Force LiveKit to recreate**: Request track re-subscription when re-entering proximity

## Debug Logging

Current debug prints in release mode (check Chrome DevTools console):
- `WebCapture: Initializing for $displayName (isRemote=$isRemote)`
- `WebCapture: mediaStreamTrack.id=$trackId, track.sid=$trackSid`
- `WebCapture: IDs to try: $idsToTry`
- `WebCapture: findVideoElementByTrackId($id) returned: ${existingVideo != null}`
- `WebVideoFrameCapture DEBUG: Found ${videos.length} video elements`

## Test Scenarios

1. **First encounter**: Join room, walk to other player → Should see video ✅
2. **Walk away**: Move out of proximity → Video bubble removed
3. **Return**: Walk back into proximity → Should see video ❌ (BROKEN)
4. **Refresh**: Reload page, encounter same player → Should see video ✅

## Related Code Sections

### VideoBubbleComponent disposal
```dart
@override
void onRemove() {
  _disposeCapture();  // This might be too aggressive
  _currentFrame?.dispose();
  _currentFrame = null;
  super.onRemove();
}
```

### WebVideoFrameCapture disposal
```dart
void dispose() {
  stopCapture();
  _currentFrame?.dispose();
  _currentFrame = null;

  // This removes the video element - problematic for re-use!
  _videoElement.srcObject = null;
  _videoElement.remove();
}
```
