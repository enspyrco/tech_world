# Video Bubble Implementation Approaches

This document explores different approaches for rendering WebRTC video feeds within the Flame game engine.

## Current Implementation: Frame Capture (Option 1)

**File:** `lib/flame/components/video_bubble_component.dart`

Uses `MediaStreamTrack.captureFrame()` to grab RGBA frames and convert them to `dart:ui.Image` for rendering as a Flame component.

### How it works
1. Timer captures frames at target FPS (default 15)
2. `captureFrame()` returns raw RGBA bytes
3. Bytes decoded to `ui.Image` via `ImageDescriptor.raw()`
4. Image drawn to canvas with circular clip

### Pros
- Full Flame integration - video is a real game component
- Can apply Flame effects, shaders, particles
- Participates in Flame's z-ordering and camera system
- Works with collision detection if needed

### Cons
- CPU overhead from copying pixels every frame
- Memory pressure from creating new images
- Realistic max ~15-30fps for small bubbles
- Latency from capture → decode → render pipeline

### Performance Tips
- Keep bubble size small (64-80px)
- Use lower target FPS (10-15) for many players
- Dispose old frames promptly
- Consider pooling/reusing image buffers

---

## Alternative: Hybrid Layer (Option 2)

Use Flutter's `TextureLayer` positioned to match game world coordinates.

### How it would work
1. Get `textureId` from `RTCVideoRenderer`
2. Calculate screen position from game world position
3. Add `TextureLayer` to Flutter's compositing layer tree
4. Update position each frame based on camera

### Implementation sketch
```dart
class VideoOverlayManager {
  final TechWorld techWorld;
  final Map<String, RTCVideoRenderer> renderers = {};
  
  List<TextureLayer> buildLayers(Size screenSize) {
    return renderers.entries.map((entry) {
      final worldPos = techWorld.getPlayerPosition(entry.key);
      final screenPos = techWorld.worldToScreen(worldPos);
      return TextureLayer(
        rect: Rect.fromCenter(center: screenPos, width: 80, height: 80),
        textureId: entry.value.textureId!,
      );
    }).toList();
  }
}
```

### Pros
- Native GPU performance - no frame copying
- Full video frame rate
- Lower CPU usage

### Cons
- Video renders in compositing layer, not on Flame canvas
- Cannot apply Flame effects/shaders
- Z-ordering challenges - video always "on top" of canvas
- Requires careful coordinate synchronization

---

## Alternative: Custom Engine Integration (Option 3)

Modify Flame or create custom component that injects `TextureLayer` into rendering pipeline.

### Concept
Flame's rendering eventually goes through `PaintingContext`. A custom component could potentially add layers during the paint phase.

### Challenges
- Flame doesn't expose `PaintingContext` to components
- Would require Flame modifications or fork
- Layer compositing happens after canvas painting
- May break Flame's assumptions about rendering

### Potential approach
```dart
class TextureComponent extends PositionComponent {
  final int textureId;
  
  @override
  void renderTree(Canvas canvas) {
    // Would need access to PaintingContext here
    // context.addLayer(TextureLayer(...));
  }
}
```

This would require changes to Flame's core rendering.

---

## Alternative: Shader-based (Option 4)

Use a custom fragment shader that samples from an external texture.

### Concept
1. Create GLSL shader that accepts external texture
2. Bind WebRTC texture to shader uniform
3. Render quad with shader applied

### Challenges
- Flutter's shader system (`FragmentProgram`) doesn't support external textures
- Would need platform-specific native code
- Complex setup for each platform

---

## Recommendation

For Tech World's use case (small video bubbles, game effects desired):

1. **Start with Frame Capture** - it works, integrates fully, performance acceptable for small bubbles
2. **Monitor performance** - track `debugStats` in production
3. **Consider Hybrid** if performance becomes issue - lose effects but gain performance
4. **Explore Custom Engine** as long-term investment if game heavily uses video

## Related Files

- `lib/flame/components/video_bubble_component.dart` - Frame capture implementation
- `lib/flame/components/player_bubble_component.dart` - Fallback colored bubble
- `lib/livekit/widgets/proximity_video_overlay.dart` - Original Flutter overlay approach
