const shaderSource = r'''
vec2 rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.2;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.38;

  // Multi-frequency fluid domain warping
  vec2 q = vec2(
    sin(p.x * 1.8 + t * 0.45 + bass * 0.2),
    cos(p.y * 1.8 + t * 0.38 + flow * 0.3)
  );

  vec2 r = vec2(
    sin(p.x * 2.8 + q.y * 2.4 + t * 0.52),
    cos(p.y * 2.8 + q.x * 2.4 + t * 0.44)
  );

  // Sheer silk ribbon folds
  vec2 warpedP = p + r * (0.35 + 0.15 * flow);
  warpedP = rotate2D(warpedP, t * 0.12 + bass * 0.2);

  float ribbon1 = sin(warpedP.y * 4.2 + warpedP.x * 2.1 + t * 1.2);
  float ribbon2 = cos(warpedP.y * 5.6 - warpedP.x * 2.8 - t * 0.95);
  float ribbon3 = sin(length(warpedP) * 5.0 - t * 1.6);

  float sheet1 = 1.0 / (abs(ribbon1) * 14.0 + 1.0);
  float sheet2 = 1.0 / (abs(ribbon2) * 16.0 + 1.0);
  float sheet3 = 1.0 / (abs(ribbon3) * 12.0 + 1.0);

  // Bioluminescent deep-ocean palette
  vec3 deepNavy = vec3(0.008, 0.024, 0.070);
  vec3 bioEmerald = vec3(0.08, 0.96, 0.60);
  vec3 bioCyan = vec3(0.15, 0.85, 1.0);
  vec3 bioViolet = vec3(0.62, 0.10, 0.95);
  vec3 warmSparkle = vec3(1.0, 0.95, 0.80);

  // Layered transmission & rim light
  vec3 col = deepNavy;
  col += bioCyan * sheet1 * (0.75 + 0.55 * bass);
  col += bioEmerald * sheet2 * (0.65 + 0.65 * energy);
  col += bioViolet * sheet3 * (0.55 + 0.45 * flow);

  // Bioluminescent micro-spores dancing on the crests
  float sporeGrid = sin(warpedP.x * 32.0 + t * 4.0) * cos(warpedP.y * 32.0 - t * 3.5);
  float spores = smoothstep(0.72, 0.98, sporeGrid) * (sheet1 + sheet2);
  col += warmSparkle * spores * (0.4 + 2.2 * spark);

  // Soft caustics / volumetric underwater rays
  float rays = sin(p.x * 6.0 + p.y * 3.0 + t * 0.8) * 0.5 + 0.5;
  col += bioCyan * rays * 0.12 * (1.0 + bass * 0.6);

  // Tone mapping and gentle vignette
  col = col / (col + vec3(0.9));
  float vignette = 1.0 - smoothstep(0.5, 1.45, length(p));
  col *= vignette;

  return vec4(clamp(col * f.intensity * f.glow, 0.0, 1.0), 1.0);
}
''';
