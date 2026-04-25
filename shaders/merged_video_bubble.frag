#version 460 core

#include <flutter/runtime_effect.glsl>

// ── Float uniforms (setFloat indices 0–23) ────────────────────
uniform vec2 u_size;            // 0,1  — component pixel size
uniform float u_time;           // 2    — animation clock
uniform float u_count;          // 3    — active bubbles (1–4)
uniform float u_bubble_radius;  // 4    — individual bubble radius (px)
uniform vec3 u_glow_color;      // 5,6,7

// Bubble positions in local (component) coordinates.
uniform vec2 u_b0;              // 8,9
uniform vec2 u_b1;              // 10,11
uniform vec2 u_b2;              // 12,13
uniform vec2 u_b3;              // 14,15

// Per-video dimensions for aspect-correct UV mapping.
uniform vec2 u_vid0;            // 16,17
uniform vec2 u_vid1;            // 18,19
uniform vec2 u_vid2;            // 20,21
uniform vec2 u_vid3;            // 22,23

// ── Image samplers (setImageSampler indices 0–3) ──────────────
uniform sampler2D u_video0;
uniform sampler2D u_video1;
uniform sampler2D u_video2;
uniform sampler2D u_video3;

out vec4 frag_color;

// ── Video UV mapping ──────────────────────────────────────────
// Maps a world-space pixel to UV coordinates for a bubble's video,
// cropping to fill the circle (cover mode, centred).
vec2 videoUV(vec2 fragPos, vec2 bubblePos, vec2 vidSize) {
    vec2 offset = fragPos - bubblePos;
    float aspect = vidSize.x / vidSize.y;

    // Normalize to -0.5..0.5 range within the bubble diameter.
    vec2 uv = offset / (u_bubble_radius * 2.0);

    // Aspect-correct cover crop.
    if (aspect > 1.0) {
        uv.x /= aspect;
    } else {
        uv.y *= aspect;
    }

    return uv + 0.5;
}

// ── Sample a specific video by index ──────────────────────────
// GLSL forbids dynamic sampler indexing, so we branch explicitly.
vec4 sampleVideo(int idx, vec2 fragPos) {
    vec2 uv;
    if (idx == 0) {
        uv = videoUV(fragPos, u_b0, u_vid0);
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
            return vec4(u_glow_color * 0.3, 1.0);
        return texture(u_video0, uv);
    } else if (idx == 1) {
        uv = videoUV(fragPos, u_b1, u_vid1);
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
            return vec4(u_glow_color * 0.3, 1.0);
        return texture(u_video1, uv);
    } else if (idx == 2) {
        uv = videoUV(fragPos, u_b2, u_vid2);
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
            return vec4(u_glow_color * 0.3, 1.0);
        return texture(u_video2, uv);
    } else {
        uv = videoUV(fragPos, u_b3, u_vid3);
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
            return vec4(u_glow_color * 0.3, 1.0);
        return texture(u_video3, uv);
    }
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    int count = int(u_count + 0.5);

    float r2 = u_bubble_radius * u_bubble_radius;
    float field = 0.0;

    // ── Compute metaball field + per-bubble distances ─────────
    float d0 = 1e6, d1 = 1e6, d2 = 1e6, d3 = 1e6;

    if (count > 0) {
        vec2 delta = p - u_b0;
        float dd = dot(delta, delta);
        field += r2 / (dd + 1.0);
        d0 = sqrt(dd);
    }
    if (count > 1) {
        vec2 delta = p - u_b1;
        float dd = dot(delta, delta);
        field += r2 / (dd + 1.0);
        d1 = sqrt(dd);
    }
    if (count > 2) {
        vec2 delta = p - u_b2;
        float dd = dot(delta, delta);
        field += r2 / (dd + 1.0);
        d2 = sqrt(dd);
    }
    if (count > 3) {
        vec2 delta = p - u_b3;
        float dd = dot(delta, delta);
        field += r2 / (dd + 1.0);
        d3 = sqrt(dd);
    }

    // ── Breathing ─────────────────────────────────────────────
    float breath = 1.0 + 0.025 * sin(u_time * 2.0);
    float threshold = 1.0 / breath;

    // ── Outside the merged shape — transparent ────────────────
    float band = 0.35;
    if (field < threshold - band) {
        frag_color = vec4(0.0);
        return;
    }

    // ── Glow band at the edge ─────────────────────────────────
    float outer_glow = smoothstep(threshold - band, threshold, field);
    float inner_fade = 1.0 - smoothstep(threshold, threshold + band * 0.5, field);
    float glow = outer_glow * inner_fade;

    // ── Interior: inside the merged metaball ──────────────────
    float inside = smoothstep(threshold, threshold + 0.05, field);

    if (inside > 0.01) {
        // Find nearest and second-nearest bubble.
        // No arrays or dynamic loops — CanvasKit's WebGL compiler forbids both.
        int nearest = 0;
        float nearDist = d0;
        int secondNearest = -1;
        float secDist = 1e6;

        if (count > 1) {
            if (d1 < nearDist) {
                secondNearest = 0; secDist = nearDist;
                nearest = 1; nearDist = d1;
            } else {
                secondNearest = 1; secDist = d1;
            }
        }
        if (count > 2) {
            if (d2 < nearDist) {
                secondNearest = nearest; secDist = nearDist;
                nearest = 2; nearDist = d2;
            } else if (d2 < secDist) {
                secondNearest = 2; secDist = d2;
            }
        }
        if (count > 3) {
            if (d3 < nearDist) {
                secondNearest = nearest; secDist = nearDist;
                nearest = 3; nearDist = d3;
            } else if (d3 < secDist) {
                secondNearest = 3; secDist = d3;
            }
        }

        // Sample nearest bubble's video.
        vec4 nearColor = sampleVideo(nearest, p);

        // Voronoi blend: smooth transition at boundary between two bubbles.
        vec4 videoColor;
        if (secondNearest >= 0) {
            float blendWidth = u_bubble_radius * 0.3;
            float t = smoothstep(-blendWidth, blendWidth, secDist - nearDist);
            vec4 secColor = sampleVideo(secondNearest, p);
            videoColor = mix(secColor, nearColor, t);
        } else {
            videoColor = nearColor;
        }

        // Composite: video inside + glow at edge.
        float pulse = 1.0 + 0.12 * sin(u_time * 2.5);
        vec3 glowContrib = u_glow_color * glow * 0.6 * pulse;
        vec3 color = videoColor.rgb * inside + glowContrib;
        float alpha = max(inside, glow * 0.7);

        frag_color = vec4(clamp(color, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
    } else {
        // Edge glow only (outside video region).
        float pulse = 1.0 + 0.12 * sin(u_time * 2.5);
        float wave = 0.06 * sin(u_time * 4.0 + field * 8.0);
        vec3 color = u_glow_color * glow * 0.75 * (pulse + wave);
        float alpha = glow * 0.7;

        frag_color = vec4(clamp(color, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
    }
}
