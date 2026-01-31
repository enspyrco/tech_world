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

## Fixed: Video Disappears on Re-entry (PR #76)

### Symptoms (Before Fix)
- Video shows correctly when first encountering a participant
- Moving away (out of proximity) and coming back → video no longer shows
- Happens on web (both mobile and desktop)

### Root Cause
When a player moves out of proximity:
1. `VideoBubbleComponent` is removed from the game
2. `onRemove()` calls `_disposeCapture()` which disposes the web capture
3. The web capture's `dispose()` removed the video element from DOM, **even if LiveKit created it**

When player comes back into proximity:
1. New `VideoBubbleComponent` is created
2. `_initializeWebCapture()` tries to find existing video element
3. **BUG**: The video element was removed by our dispose!

### Solution
Added `_ownsElement` flag to `WebVideoFrameCapture`:
- `createFromStream()` and `createFromTrack()` set `ownsElement: true` (we created the element)
- `createFromExistingVideo()` sets `ownsElement: false` (LiveKit owns it)
- `dispose()` only removes the video element if `_ownsElement` is true

```dart
// In dispose():
if (_ownsElement) {
  _videoElement.srcObject = null;
  _videoElement.remove();
}
```

This preserves LiveKit's video elements so they can be reused when re-entering proximity

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
  _disposeCapture();
  _currentFrame?.dispose();
  _currentFrame = null;
  super.onRemove();
}
```

### WebVideoFrameCapture disposal (after fix)
```dart
void dispose() {
  stopCapture();
  _currentFrame?.dispose();
  _currentFrame = null;

  // Only remove the video element if we created it
  // If we're using an existing LiveKit element, leave it alone
  if (_ownsElement) {
    _videoElement.srcObject = null;
    _videoElement.remove();
  }
}
```
