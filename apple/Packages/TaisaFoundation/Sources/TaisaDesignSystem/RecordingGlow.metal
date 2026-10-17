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

    float leftOuterWeight = outerLeft * leftOuterContribution;
    float leftInnerWeight = innerLeft * leftInnerContribution;
    float centerWeight = middle * centerContribution * mix(0.68, 1.2, loudness);
    float rightInnerWeight = innerRight * rightInnerContribution;
    float rightOuterWeight = outerRight * rightOuterContribution;
    float weightSum = leftOuterWeight + leftInnerWeight + centerWeight
        + rightInnerWeight + rightOuterWeight;

    float3 rgb = float3(leftOuterColor.rgb) * leftOuterWeight;
    rgb += float3(leftInnerColor.rgb) * leftInnerWeight;
    rgb += float3(centerColor.rgb) * centerWeight;
    rgb += float3(rightInnerColor.rgb) * rightInnerWeight;
    rgb += float3(rightOuterColor.rgb) * rightOuterWeight;

    float grainVisibility = grain.x * (1.0 + loudness * grainLoudnessInfluence);
    float2 grainCell = floor(position * mix(0.08, 0.34, grain.y));
    float noise = anchoredNoise(grainCell, grainSeed);
    noise = smoothstep(grain.w, 1.0, noise);
    float grit = mix(1.0 - grainVisibility, 1.0 + grainVisibility, noise);
    float3 glowColor = clamp(
        (rgb / max(weightSum, 0.0001)) * mix(1.0, grit, grain.z),
        0.0,
        1.0
    );

    float weightedField = max(
        max(max(leftOuterWeight, leftInnerWeight), centerWeight),
        max(rightInnerWeight, rightOuterWeight)
    );
    float alpha = clamp(weightedField * globalOpacity * 1.25, 0.0, 1.0);
    float3 compositedColor = mix(float3(1.0), glowColor, alpha);
    return half4(half3(compositedColor), half(1.0));
}
