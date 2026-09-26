const shaderSource = r'''
vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.0;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.5;

  float horizonY = -0.05;
  vec3 col = vec3(0.0);

  // Background deep sky gradient
  vec3 skyTop = vec3(0.02, 0.02, 0.08);
  vec3 skyHorizon = vec3(0.35, 0.05, 0.35);
  float skyGradient = smoothstep(horizonY, 1.2, p.y);
  col = mix(skyHorizon, skyTop, skyGradient);

  // Retro horizon glowing synth sun
  vec2 sunPos = vec2(0.0, horizonY + 0.32);
  float sunDist = length(p - sunPos);
  float sunRadius = 0.38 + 0.05 * bass;
  if (p.y > horizonY) {
    if (sunDist < sunRadius) {
      // Horizontal laser stripes cut through the sun
      float sunStripe = sin(p.y * 36.0);
      float stripeMask = smoothstep(0.2, 0.4, sunStripe);
      if (p.y < sunPos.y) {
        stripeMask = mix(1.0, stripeMask, smoothstep(sunPos.y - sunRadius, sunPos.y, p.y));
      } else {
        stripeMask = 1.0;
      }
      vec3 sunTopCol = vec3(1.0, 0.9, 0.2);
      vec3 sunBotCol = vec3(1.0, 0.15, 0.55);
      float sunY = (p.y - (sunPos.y - sunRadius)) / (sunRadius * 2.0);
      vec3 sunColor = mix(sunBotCol, sunTopCol, sunY);
      col = mix(col, sunColor, stripeMask);
    }
  }

  // Soft atmospheric sun corona glow
  float sunGlow = (0.04 + 0.06 * bass) / (sunDist * sunDist * 10.0 + 0.1);
  col += vec3(1.0, 0.25, 0.6) * sunGlow;

  // Infinite Perspective Cyber Grid (below horizon)
  if (p.y < horizonY) {
    // 3D ray projection onto the ground plane
    float py = horizonY - p.y;
    float depth = 1.0 / (py + 0.03);

    // Ground plane coordinates (x: sideways, z: forward depth)
    float worldX = p.x * depth * 0.85;
    float worldZ = depth * 1.5 + t * (2.5 + 2.5 * energy);

    // Topographical terrain elevation modulated by sound waves
    float mountainFreq = worldX * 0.35;
    float mountainH = sin(mountainFreq) * cos(worldZ * 0.15) * (0.8 + 0.5 * flow);
    // Shockwave ripple surging from the beat
    float ripple = sin(worldZ * 0.8 - t * 4.5) * (0.3 + 0.8 * bass);
    worldX += mountainH * 0.2;

    // Grid lines with antialiased inverse-distance glow
    float gridX = abs(fract(worldX) - 0.5) * 2.0;
    float gridZ = abs(fract(worldZ * 0.4) - 0.5) * 2.0;

    float lineX = 1.0 - smoothstep(0.0, 0.08 * (1.0 + depth * 0.05), gridX);
    float lineZ = 1.0 - smoothstep(0.0, 0.08 * (1.0 + depth * 0.05), gridZ);

    float gridLines = max(lineX, lineZ);
    // Sparkle points at grid vertices
    float vertices = pow(lineX * lineZ, 0.5) * (1.0 + 3.0 * spark);

    // Grid color ramp: Neon cyan near, hot magenta towards the horizon
    float fog = smoothstep(22.0, 2.0, depth);
    vec3 nearColor = vec3(0.15, 0.95, 1.0);
    vec3 farColor = vec3(1.0, 0.15, 0.75);
    vec3 gridColor = mix(farColor, nearColor, fog);

    vec3 groundSurface = gridColor * (gridLines * 1.2 + vertices * 2.0);
    // Dark metallic reflective ground under the grid lines
    vec3 groundBase = vec3(0.015, 0.01, 0.03) + sunGlow * vec3(0.2, 0.05, 0.15);

    vec3 finalGround = groundBase + groundSurface;
    col = mix(skyHorizon, finalGround, fog);
  }

  // Horizon laser separator line
  float horizonLine = exp(-abs(p.y - horizonY) * 65.0) * (0.6 + 0.8 * bass);
  col += vec3(0.3, 0.9, 1.0) * horizonLine;

  // Soft tone mapping and subtle vignette
  col = col / (col + vec3(0.85));
  float vignette = 1.0 - smoothstep(0.6, 1.5, length(p));
  col *= vignette;

  return vec4(clamp(col * f.intensity * f.glow, 0.0, 1.0), 1.0);
}
''';
