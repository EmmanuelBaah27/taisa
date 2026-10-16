#include <metal_stdlib>
using namespace metal;

static float anchoredNoise(float2 cell, float seed) {
    float value = dot(cell, float2(127.1, 311.7)) + seed * 0.0001;
    return fract(sin(value) * 43758.5453);
}

static float glowLobe(float2 point, float centerX, float width, float height, float originY, float softness) {
    float safeWidth = max(width, 0.01);
    float safeHeight = max(height, 0.01);
    float2 delta = float2((point.x - centerX) / safeWidth, (point.y - originY) / safeHeight);
    return exp(-dot(delta, delta) * mix(4.8, 1.4, softness));
}

[[ stitchable ]] half4 recordingGlow(
    float2 position,
    half4 currentColor,
    float2 size,
    float loudness,
    float spatialLoudness,
    half4 leftOuterColor,
    half4 leftInnerColor,
    half4 centerColor,
    half4 rightInnerColor,
    half4 rightOuterColor,
    float leftOuterContribution,
    float leftInnerContribution,
    float centerContribution,
    float rightInnerContribution,
    float rightOuterContribution,
    float4 centerGeometry,
    float4 edgeGeometry,
    float4 grain,
    float grainLoudnessInfluence,
    float grainSeed,
    float globalOpacity
) {
    float2 safeSize = max(size, float2(1.0));
    float2 point = position / safeSize;
    float originY = edgeGeometry.w;
    float centerHeight = mix(centerGeometry.x, centerGeometry.y, spatialLoudness);
    float centerWidth = centerGeometry.z * mix(0.82, 1.22, spatialLoudness);
    float centerSoftness = clamp(centerGeometry.w + spatialLoudness * 0.18, 0.0, 1.0);
    float edgeHeight = mix(0.09, 0.2, spatialLoudness);
    float edgeWidth = mix(0.12, 0.22, edgeGeometry.x);
    float edgeSoftness = edgeGeometry.y;

    float outerLeft = glowLobe(point, -0.02, edgeWidth, edgeHeight, originY, edgeSoftness);
    float innerLeft = glowLobe(point, 0.25, edgeWidth * 1.18, edgeHeight * 1.18, originY, edgeSoftness);
    float middle = glowLobe(point, 0.5, centerWidth, centerHeight, originY, centerSoftness);
    float innerRight = glowLobe(point, 0.75, edgeWidth * 1.18, edgeHeight * 1.18, originY, edgeSoftness);
    float outerRight = glowLobe(point, 1.02, edgeWidth, edgeHeight, originY, edgeSoftness);

    float3 rgb = float3(leftOuterColor.rgb) * outerLeft * leftOuterContribution;
    rgb += float3(leftInnerColor.rgb) * innerLeft * leftInnerContribution;
    rgb += float3(centerColor.rgb) * middle * centerContribution * mix(0.68, 1.2, loudness);
    rgb += float3(rightInnerColor.rgb) * innerRight * rightInnerContribution;
    rgb += float3(rightOuterColor.rgb) * outerRight * rightOuterContribution;

    float field = max(max(max(outerLeft, innerLeft), middle), max(innerRight, outerRight));
    float grainVisibility = grain.x * (1.0 + loudness * grainLoudnessInfluence);
    float2 grainCell = floor(position * mix(0.08, 0.34, grain.y));
    float noise = anchoredNoise(grainCell, grainSeed);
    noise = smoothstep(grain.w, 1.0, noise);
    float grit = mix(1.0 - grainVisibility, 1.0 + grainVisibility, noise);
    rgb *= mix(1.0, grit, grain.z) * field;

    float alpha = clamp(field * globalOpacity, 0.0, 1.0);
    rgb = clamp(rgb, 0.0, 1.0) * alpha;
    return half4(half3(rgb), half(alpha));
}
