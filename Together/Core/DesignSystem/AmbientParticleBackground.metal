#include <metal_stdlib>
using namespace metal;

float ambientHash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float2 ambientHash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

[[ stitchable ]] half4 ambientParticleField(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float darkAppearance,
    float contrastMultiplier
) {
    (void)color;

    if (size.y <= 0.0) {
        return half4(0.0);
    }

    float2 uv = position / size.y;
    float accumulatedAlpha = 0.0;

    // Each layer evaluates only its current cell. Particle centers, sway, and
    // radii stay inside that cell, removing the reference shader's 3x3 search.
    for (int layer = 0; layer < 4; layer += 1) {
        float layerIndex = float(layer);
        float scale = 14.0 + layerIndex * 15.0;
        float layerSeed = layerIndex * 153.25;
        float layerSpeed = (0.12 + layerIndex * 0.08) * 0.65;
        float2 st = float2(uv.x, uv.y + time * layerSpeed) * scale;
        float2 cellID = floor(st);
        float2 cellPosition = fract(st) - 0.5;
        float2 randomPosition = ambientHash22(cellID + layerSeed);
        float densityNoise = ambientHash12(cellID + layerSeed + 78.9);

        // About 16% active cells: roughly 57% of the reference's 28% density.
        if (densityNoise > 0.84) {
            float2 particlePosition = (randomPosition - 0.5) * 0.64;
            float swaySpeed = 0.65 + randomPosition.x * 1.45;
            float swayAmount = 0.025 + randomPosition.y * 0.040;
            particlePosition.x += sin(time * swaySpeed + randomPosition.y * 6.2831853) * swayAmount;

            float nearWeight = 1.0 - layerIndex / 3.0;
            float minimumRadiusPoints = mix(0.40, 0.60, nearWeight);
            float maximumRadiusPoints = mix(0.70, 1.10, nearWeight);
            float sizeRandom = randomPosition.y * randomPosition.y;
            float radiusPoints = mix(minimumRadiusPoints, maximumRadiusPoints, sizeRandom);
            float pointsPerCellUnit = size.y / scale;
            float distanceToParticlePoints = length(cellPosition - particlePosition) * pointsPerCellUnit;

            // Keep anti-aliasing in point space. Derivatives of a fract-based
            // distance are discontinuous at cell boundaries and reveal the
            // grid as rectangular outlines on device.
            constexpr float antialiasWidthPoints = 0.35;
            float circleAlpha = 1.0 - smoothstep(
                radiusPoints - antialiasWidthPoints,
                radiusPoints + antialiasWidthPoints,
                distanceToParticlePoints
            );

            float opacityNoise = ambientHash12(cellID + layerSeed + 211.7);
            float opacityRandom = opacityNoise * opacityNoise;
            float lightOpacity = mix(0.12, 0.22, opacityRandom);
            float darkOpacity = mix(0.10, 0.20, opacityRandom);
            float particleOpacity = mix(lightOpacity, darkOpacity, darkAppearance);
            accumulatedAlpha += circleAlpha * particleOpacity;
        }
    }

    float normalizedY = position.y / size.y;
    float topFade = smoothstep(0.0, 0.10, normalizedY);
    float bottomFade = 1.0 - smoothstep(0.84, 1.0, normalizedY);
    float maximumAlpha = mix(0.22, 0.20, darkAppearance);
    float alpha = min(accumulatedAlpha, maximumAlpha)
        * topFade
        * bottomFade
        * contrastMultiplier;
    half3 particleColor = mix(half3(0.12, 0.14, 0.17), half3(0.96, 0.95, 0.93), half(darkAppearance));
    half premultipliedAlpha = half(alpha);
    return half4(particleColor * premultipliedAlpha, premultipliedAlpha);
}
