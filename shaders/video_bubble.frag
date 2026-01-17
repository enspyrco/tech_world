#version 460 core

// Required include for Flutter shaders
#include <flutter/runtime_effect.glsl>

// First uniform MUST be vec2 for size (required by ImageFilter.shader)
uniform vec2 u_size;

// Effect parameters
uniform float u_time;           // For animated effects
uniform float u_glow_intensity; // 0.0 = no glow, 1.0 = full glow
uniform vec3 u_glow_color;      // RGB glow color (0.0-1.0)
uniform float u_speaking;       // 0.0 = silent, 1.0 = speaking (for pulse effect)

// The input texture - provided automatically by ImageFilter.shader
uniform sampler2D u_texture;

out vec4 frag_color;

void main() {
    vec2 uv = FlutterFragCoord().xy / u_size;

    // Flip Y for OpenGL backend compatibility
    #ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
    #endif

    // Calculate distance from center for circular effects
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(uv, center);

    // Sample the video texture
    vec4 video_color = texture(u_texture, uv);

    // Circular mask with soft edge (already clipped in Flame, but we soften edges)
    float radius = 0.48;
    float edge_softness = 0.02;
    float circle_mask = 1.0 - smoothstep(radius - edge_softness, radius, dist);

    // Apply slight vignette to video
    float vignette = 1.0 - (dist * 0.3);
    vec4 masked_video = video_color * circle_mask * vignette;

    // Glow effect on the edge
    float glow_inner = radius - 0.05;
    float glow_outer = radius + 0.08;
    float glow = smoothstep(glow_inner, radius, dist) * (1.0 - smoothstep(radius, glow_outer, dist));

    // Pulse the glow when speaking
    float pulse = 1.0 + 0.4 * sin(u_time * 10.0) * u_speaking;
    glow *= u_glow_intensity * pulse;

    // Add subtle color shift based on time for "energy" effect
    vec3 energy_color = u_glow_color;
    if (u_speaking > 0.5) {
        float shift = sin(u_time * 5.0) * 0.1;
        energy_color = vec3(
            u_glow_color.r + shift,
            u_glow_color.g,
            u_glow_color.b - shift
        );
    }

    // Combine video with glow
    vec3 glow_contribution = energy_color * glow * 1.5;
    vec3 final_color = masked_video.rgb + glow_contribution;

    // Alpha: video inside circle + glow outside
    float final_alpha = max(masked_video.a, glow * 0.9);

    // Clamp to valid range
    final_color = clamp(final_color, 0.0, 1.0);

    frag_color = vec4(final_color, final_alpha);
}
