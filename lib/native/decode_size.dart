// Pure, platform-independent sizing logic for decoded video-bubble textures.
//
// Kept free of `dart:ui` / `package:web` imports so it can be unit-tested in
// the plain VM test runner (the web capture files that use it cannot — see
// the dart_webrtc / package:web note in video_frame_web_v2.dart).

/// Longest-side cap (px) for decoded video-bubble textures.
///
/// Video bubbles render as small circles (`bubbleSize` 64px, a few hundred px
/// at high DPR), but cameras deliver 640x480–1280x720 frames. Decoding at the
/// full camera resolution uploads a multi-megabyte RGBA texture every frame
/// just to draw a thumbnail — tens-of-x more GPU memory than the display needs.
/// That churn drives CanvasKit's WebGL context into memory pressure and, on
/// Firefox, into context loss + heap corruption (the engine's own recovery then
/// fails inside `MakeGrContext` with "index out of bounds"). Capping the
/// longest side keeps the uploaded texture proportional to what's drawn: 256px
/// gives crisp headroom for a 64px bubble even at 3x DPR (192px) while shrinking
/// a 1280x720 frame's texture ~24x.
const int kMaxBubbleDecodeDimension = 256;

/// The readback/decode size for a [srcW]x[srcH] source frame, with the longest
/// side capped to [maxDim] and aspect ratio preserved.
///
/// - Frames already within [maxDim] on both sides pass through unchanged (no
///   upscaling — we only ever shrink).
/// - Never returns a zero dimension for a non-empty source: extreme aspect
///   ratios clamp the short side to a minimum of 1px.
/// - Non-positive source dimensions pass through unchanged so callers can keep
///   their existing zero-size guards.
({int width, int height}) scaledDecodeSize(int srcW, int srcH, int maxDim) {
  if (srcW <= 0 || srcH <= 0) return (width: srcW, height: srcH);
  if (srcW <= maxDim && srcH <= maxDim) return (width: srcW, height: srcH);
  final int longest = srcW >= srcH ? srcW : srcH;
  final double scale = maxDim / longest;
  final int w = (srcW * scale).round().clamp(1, maxDim);
  final int h = (srcH * scale).round().clamp(1, maxDim);
  return (width: w, height: h);
}
