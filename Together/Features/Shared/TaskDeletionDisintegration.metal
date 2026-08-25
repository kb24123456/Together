#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

float taskDeletionHash21(float2 value) {
    value = fract(value * float2(123.34, 456.21));
    value += dot(value, value + 45.32);
    return fract(value.x * value.y);
}

float taskDeletionValueNoise(float2 value) {
    float2 cell = floor(value);
    float2 fraction = fract(value);
    float2 curve = fraction * fraction * (3.0 - 2.0 * fraction);
    float top = mix(
        taskDeletionHash21(cell),
        taskDeletionHash21(cell + float2(1.0, 0.0)),
        curve.x
    );
    float bottom = mix(
        taskDeletionHash21(cell + float2(0.0, 1.0)),
        taskDeletionHash21(cell + float2(1.0, 1.0)),
        curve.x
    );
    return mix(top, bottom, curve.y);
}

float taskDeletionDampedProgress(float progress) {
    float response = 2.6;
    float endpoint = 1.0 - (1.0 + response) * exp(-response);
    float value = 1.0
        - (1.0 + response * progress) * exp(-response * progress);
    return clamp(value / max(endpoint, 0.001), 0.0, 1.0);
}

[[ stitchable ]] half4 taskDeletionDisintegrate(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float progress,
    float seed,
    float controlOpacity
) {
    half4 original = layer.sample(position);

    half maximumChannel = max(original.r, max(original.g, original.b));
    half minimumChannel = min(original.r, min(original.g, original.b));
    half chroma = maximumChannel - minimumChannel;
    if (original.a > half(0.001) && chroma > half(0.075)) {
        return original * half(controlOpacity);
    }

    float safeWidth = max(size.x, 1.0);
    float2 coarseCoordinate = position / 8.0 + float2(seed * 37.0, seed * 19.0);
    float coarseNoise = taskDeletionValueNoise(coarseCoordinate);
    float particleSize = mix(0.68, 1.18, coarseNoise);
    float2 particleCell = floor(position / particleSize);
    float grainNoise = taskDeletionHash21(particleCell + float2(seed * 997.0));

    float normalizedX = clamp(position.x / safeWidth, 0.0, 1.0);
    float releaseThreshold = 0.015
        + normalizedX * 0.24
        + grainNoise * 0.070
        + coarseNoise * 0.030;
    float particleAge = clamp(
        (progress - releaseThreshold) / 0.645,
        0.0,
        1.0
    );

    if (particleAge <= 0.0) {
        return original;
    }

    float gust = taskDeletionValueNoise(
        particleCell * 0.13 + float2(seed * 53.0, particleAge * 0.85)
    );
    float windProgress = taskDeletionDampedProgress(particleAge);
    float windStrength = mix(0.92, 1.06, gust);
    float horizontalTravel = mix(46.0, 66.0, grainNoise)
        * windStrength
        * windProgress;
    float verticalTravel = -mix(8.0, 18.0, gust) * windProgress;
    float flutterEnvelope = sin(particleAge * M_PI_F);
    float flutterPhase = particleCell.x * 0.71
        + particleCell.y * 1.13
        + seed * 31.0;
    float turbulence = (
        sin(flutterPhase + particleAge * 6.0) * 2.55
        + sin(flutterPhase * 0.47 + particleAge * 2.7) * 1.15
    ) * flutterEnvelope;
    float longitudinalFlutter = sin(
        flutterPhase * 0.63 + particleAge * 4.2
    ) * 1.35 * flutterEnvelope;
    float2 samplePosition = position - float2(
        horizontalTravel + longitudinalFlutter,
        verticalTravel + turbulence
    );
    half4 displaced = layer.sample(samplePosition);

    half displacedMaximum = max(displaced.r, max(displaced.g, displaced.b));
    half displacedMinimum = min(displaced.r, min(displaced.g, displaced.b));
    half displacedChroma = displacedMaximum - displacedMinimum;
    if (displacedChroma > half(0.075)) {
        return original * half(controlOpacity);
    }

    float2 dustCoordinate = samplePosition / particleSize
        + float2(seed * 131.0, seed * 79.0);
    float2 dustLocal = fract(dustCoordinate) - 0.5;
    float dustRadius = mix(0.34, 0.46, grainNoise);
    float dustShape = 1.0 - smoothstep(
        dustRadius,
        dustRadius + 0.09,
        length(dustLocal)
    );
    float survival = 1.0 - smoothstep(0.76, 1.0, particleAge);
    float sourceCoverage = smoothstep(0.015, 0.14, float(displaced.a));
    half alphaMultiplier = half(survival * dustShape * sourceCoverage);
    half4 dust = half4(
        displaced.rgb * alphaMultiplier,
        displaced.a * alphaMultiplier
    );
    float dustFormation = smoothstep(0.0, 0.34, particleAge);
    return mix(original, dust, half(dustFormation));
}
