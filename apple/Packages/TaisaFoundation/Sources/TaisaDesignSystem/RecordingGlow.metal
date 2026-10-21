#include <metal_stdlib>
using namespace metal;

static float anchoredNoise(float2 cell, float seed) {
    float value = dot(cell, float2(127.1, 311.7)) + seed * 0.0001;
    return fract(sin(value) * 43758.5453);
}

static float filmNoise(float2 position, float size, float seed) {
    // A larger control value means visibly larger grain while the full range
    // stays close to the pixel scale. A second octave prevents square cells.
    float frequency = mix(1.25, 0.45, size);
    float primary = anchoredNoise(floor(position * frequency), seed);
    float micro = anchoredNoise(
        floor(position * frequency * 1.73 + float2(19.0, 43.0)),
        seed + 41.0
    );
    return mix(primary, micro, 0.36);
}

static float glowLobe(float2 point, float centerX, float width, float height, float originY, float softness) {
    float safeWidth = max(width, 0.01);
    float safeHeight = max(height, 0.01);
    float2 delta = float2((point.x - centerX) / safeWidth, (point.y - originY) / safeHeight);
    return exp(-dot(delta, delta) * mix(4.8, 1.4, softness));
}

static float softUnion(float totalWeight) {
    return 1.0 - exp(-max(totalWeight, 0.0) * 1.6);
}

[[ stitchable ]] half4 recordingGlow(
    float2 position,
    half4 currentColor,
    float2 size,
    float loudness,
    float spatialLoudness,
    float4 edgeLoudness,
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
    float globalScale = mix(0.78, 1.22, loudness);
    float centerHeight = mix(centerGeometry.x, centerGeometry.y, spatialLoudness) * globalScale;
    float centerWidth = centerGeometry.z * mix(0.82, 1.22, spatialLoudness) * mix(0.9, 1.08, loudness);
    float centerSoftness = clamp(centerGeometry.w + spatialLoudness * 0.18, 0.0, 1.0);
    float edgeWidth = mix(0.12, 0.22, edgeGeometry.x);
    float edgeSoftness = edgeGeometry.y;

    float4 edgeHeight = mix(float4(0.09), float4(0.25), edgeLoudness) * globalScale;
    float4 edgeWidthResponse = mix(float4(0.9), float4(1.12), edgeLoudness);
    float outerLeft = glowLobe(point, -0.02, edgeWidth * edgeWidthResponse.x, edgeHeight.x, originY, edgeSoftness);
    float innerLeft = glowLobe(point, 0.25, edgeWidth * 1.18 * edgeWidthResponse.y, edgeHeight.y * 1.18, originY, edgeSoftness);
    float middle = glowLobe(point, 0.5, centerWidth, centerHeight, originY, centerSoftness);
    float innerRight = glowLobe(point, 0.75, edgeWidth * 1.18 * edgeWidthResponse.z, edgeHeight.z * 1.18, originY, edgeSoftness);
    float outerRight = glowLobe(point, 1.02, edgeWidth * edgeWidthResponse.w, edgeHeight.w, originY, edgeSoftness);

    float4 edgeResponse = edgeLoudness * 1.18 * mix(0.82, 1.16, loudness);
    float leftOuterWeight = outerLeft * leftOuterContribution * edgeResponse.x;
    float leftInnerWeight = innerLeft * leftInnerContribution * edgeResponse.y;
    float centerWeight = middle * centerContribution
        * spatialLoudness * 1.18
        * mix(0.82, 1.16, loudness);
    float rightInnerWeight = innerRight * rightInnerContribution * edgeResponse.z;
    float rightOuterWeight = outerRight * rightOuterContribution * edgeResponse.w;
    float weightSum = leftOuterWeight + leftInnerWeight + centerWeight
        + rightInnerWeight + rightOuterWeight;

    float3 rgb = float3(leftOuterColor.rgb) * leftOuterWeight;
    rgb += float3(leftInnerColor.rgb) * leftInnerWeight;
    rgb += float3(centerColor.rgb) * centerWeight;
    rgb += float3(rightInnerColor.rgb) * rightInnerWeight;
    rgb += float3(rightOuterColor.rgb) * rightOuterWeight;

    float grainVisibility = grain.x * (1.0 + loudness * grainLoudnessInfluence);
    float noise = filmNoise(position, grain.y, grainSeed);
    noise = smoothstep(grain.w, 1.0, noise);
    float grit = mix(1.0 - grainVisibility, 1.0 + grainVisibility, noise);
    float3 glowColor = clamp(
        (rgb / max(weightSum, 0.0001)) * mix(1.0, grit, grain.z),
        0.0,
        1.0
    );

    // Keep the approved 15% inactive energy legible against the white canvas;
    // active bands still gain their shape and dominance from their own weights.
    float alpha = clamp(softUnion(weightSum) * globalOpacity * 1.9, 0.0, 1.0);
    float3 compositedColor = mix(float3(1.0), glowColor, alpha);
    return half4(half3(compositedColor), half(1.0));
}
