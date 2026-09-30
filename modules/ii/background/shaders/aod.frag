#version 440
// Source of aod.frag.qsb — rebuild with:
//   qsb --qt6 -o aod.frag.qsb aod.frag
//
// Lockscreen always-on-display cover. Same noisy reveal as the reversed
// magic transition, measured inward from the farthest edge instead of out
// from the centre: opaque black sweeps in from the corners towards the
// middle, and everything it has not touched yet stays transparent so the
// blurred wallpaper underneath shows through unchanged.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    vec2 aspectRatio;
    vec2 origin;
};

float getDistance(vec2 uv) {
    vec2 scaled = (uv - origin) * aspectRatio;
    return length(scaled);
}

float random(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.546875);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float p = clamp(progress, 0.0, 1.0);
    if (p >= 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0) * qt_Opacity;
        return;
    }
    if (p <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 maxVec = max(origin, vec2(1.0) - origin) * aspectRatio;
    float maxDistance = length(maxVec);
    // Reversed: same span [0, maxDistance], but counted inward from the edge.
    float dist = maxDistance - getDistance(uv);
    float threshold = p * maxDistance;
    float edgeNoise = smoothstep(0.0, 1.0, random(uv * 150.0)) * 0.12;
    float blend = smoothstep(threshold - 0.05, threshold + edgeNoise, dist);
    // blend = 0 → covered (opaque black), blend = 1 → untouched (see-through).
    fragColor = vec4(0.0, 0.0, 0.0, 1.0 - blend) * qt_Opacity;
}
