#version 460 core

#include <flutter/runtime_effect.glsl>

// Canvas size — required first uniform for Paint.shader usage.
uniform vec2 u_size;

// Animation & field parameters
uniform float u_time;
uniform float u_count;          // number of active bubbles (0–8)
uniform vec3 u_color;           // base glow color (RGB, 0–1)
uniform float u_bubble_radius;  // individual bubble radius in pixels

// Up to 8 bubble positions in local (component) pixel coordinates.
uniform vec2 u_b0;
uniform vec2 u_b1;
uniform vec2 u_b2;
uniform vec2 u_b3;
uniform vec2 u_b4;
uniform vec2 u_b5;
uniform vec2 u_b6;
uniform vec2 u_b7;

out vec4 frag_color;

void main() {
    vec2 p = FlutterFragCoord().xy;

    float r2 = u_bubble_radius * u_bubble_radius;
    float field = 0.0;
    float min_d2 = 1e12;  // track closest bubble (squared distance)

    // Accumulate metaball field: r² / (d² + ε)
    // The +1.0 prevents division by zero and softens the center.
    #define BALL(b) {                             \
        vec2 delta = p - b;                       \
        float d2 = dot(delta, delta);             \
        field += r2 / (d2 + 1.0);                 \
        min_d2 = min(min_d2, d2);                  \
    }

    if (u_count > 0.5) BALL(u_b0)
    if (u_count > 1.5) BALL(u_b1)
    if (u_count > 2.5) BALL(u_b2)
    if (u_count > 3.5) BALL(u_b3)
    if (u_count > 4.5) BALL(u_b4)
    if (u_count > 5.5) BALL(u_b5)
    if (u_count > 6.5) BALL(u_b6)
    if (u_count > 7.5) BALL(u_b7)

    // ── Threshold & glow band ─────────────────────────────
    //
    // field ≈ 1.0 at exactly one bubble-radius from a single bubble.
    // When two bubbles overlap fields, the sum pushes above 1.0 in the
    // gap — that's the merge.
    float threshold = 1.0;

    // The glow lives in a band around the threshold.
    // inner_edge → threshold: ramp up (entering the glow from outside)
    // threshold → outer_edge: ramp down (leaving the glow into the interior)
    float band = 0.35;
    float outer_glow = smoothstep(threshold - band, threshold, field);
    float inner_fade = 1.0 - smoothstep(threshold, threshold + band * 0.5, field);
    float glow = outer_glow * inner_fade;

    // ── Bridge fill ───────────────────────────────────────
    //
    // The bridge is the region INSIDE the merged metaball but OUTSIDE
    // any individual bubble circle. It gets a subtle translucent fill
    // so the connection between players is visible.
    float inside_merged = smoothstep(threshold, threshold + 0.05, field);
    float inside_circle = step(min_d2, u_bubble_radius * u_bubble_radius * 0.9025);
    float bridge = inside_merged * (1.0 - inside_circle);

    // ── Animation ─────────────────────────────────────────
    //
    // Gentle breathing pulse on the glow, plus a traveling wave along
    // the field gradient that makes the energy feel alive.
    float pulse = 1.0 + 0.12 * sin(u_time * 2.5);
    float wave = 0.06 * sin(u_time * 4.0 + field * 8.0);

    // ── Composite ─────────────────────────────────────────
    float glow_alpha = glow * 0.75 * (pulse + wave);
    float bridge_alpha = bridge * 0.2;
    float alpha = max(glow_alpha, bridge_alpha);

    vec3 color = u_color * (pulse + wave);

    // Clamp and output with pre-multiplied alpha (additive blend target).
    color = clamp(color, 0.0, 1.0);
    alpha = clamp(alpha, 0.0, 1.0);

    frag_color = vec4(color * alpha, alpha);
}
