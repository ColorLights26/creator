const shaderSource = r'''
vec2 rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float crystalFacet(vec2 p, float size, float t, float bass) {
  vec2 q = abs(p);
  // Octahedral and dodecahedral folding planes
  float d1 = dot(q, normalize(vec2(1.0, 1.0))) - size;
  float d2 = dot(q, normalize(vec2(1.732, 1.0))) - size;
  float d3 = dot(q, normalize(vec2(1.0, 1.732))) - size;
  float d4 = max(q.x, q.y) - size * 0.92;
  return max(max(d1, d2), max(d3, d4));
}

vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.2;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.42;

  vec3 col = vec3(0.0);
  float crystalBaseSize = 0.52 + 0.08 * bass;

  // 3-channel Chromatic Dispersion (Abbe number split)
  for (int ch = 0; ch < 3; ch++) {
    float dispersion = float(ch - 1) * (0.016 + 0.035 * spark);
    vec2 cp = p * (1.0 + dispersion);

    // Slowly rotating crystal body
    vec2 rotP = rotate2D(cp, t * 0.35 + bass * 0.25);

    // External crystal facets
    float dExt = crystalFacet(rotP, crystalBaseSize, t, bass);
    float edgeGlow = (0.018 + 0.025 * spark) / (abs(dExt) * 18.0 + 0.008);

    // Internal refracted layers / nested smaller crystal shells
    vec2 innerP1 = rotate2D(rotP * 1.55, -t * 0.55 + float(ch) * 0.2);
    float dInt1 = crystalFacet(innerP1, crystalBaseSize * 0.85, t, bass);
    float innerGlow1 = (0.012 + 0.02 * bass) / (abs(dInt1) * 22.0 + 0.012);

    vec2 innerP2 = rotate2D(rotP * 2.4, t * 0.75 + float(ch) * 0.4);
    float dInt2 = crystalFacet(innerP2, crystalBaseSize * 0.7, t, bass);
    float innerGlow2 = (0.008 + 0.015 * energy) / (abs(dInt2) * 28.0 + 0.015);

    // Caustic light rays radiating through the crystal faces
    float angle = atan(rotP.y / (rotP.x + 0.00001)) + (rotP.x < 0.0 ? 3.14159 : 0.0);
    float causticRays = pow(abs(cos(angle * 6.0 + t * 0.8)), 8.0) * (0.3 + 0.7 * bass);
    float rayFalloff = exp(-length(cp) * 2.2);
    float caustics = causticRays * rayFalloff;

    // Center radiant hyper-core
    float core = (0.08 + 0.32 * bass) / (length(cp) * length(cp) * 16.0 + 0.12);

    // Rainbow spectral palette
    vec3 palColor;
    if (ch == 0) {
      palColor = vec3(1.0, 0.15, 0.45); // Ruby / Magenta
    } else if (ch == 1) {
      palColor = vec3(0.15, 1.0, 0.65); // Emerald / Cyan
    } else {
      palColor = vec3(0.25, 0.55, 1.0); // Sapphire / Violet
    }

    float channelTotal = (edgeGlow * 0.45 + innerGlow1 * 0.35 + innerGlow2 * 0.25 + caustics * 0.5 + core * 0.7);

    col += palColor * channelTotal;
  }

  // Specular facet glints (sharp diamond flare)
  vec2 flareP = rotate2D(p, t * 0.35);
  float starX = exp(-abs(flareP.x) * 45.0) * exp(-abs(flareP.y) * 4.0);
  float starY = exp(-abs(flareP.y) * 45.0) * exp(-abs(flareP.x) * 4.0);
  float diamondFlare = (starX + starY) * (0.2 + 1.8 * spark);
  col += vec3(1.0, 0.98, 0.92) * diamondFlare;

  // Background velvet depth and cinematic vignette
  vec3 bg = vec3(0.012, 0.015, 0.03) * (1.0 - 0.4 * length(p));
  col = mix(bg, col, smoothstep(0.0, 0.15, length(col)));

  // Soft tone mapping
  col = col / (col + vec3(0.88));
  float vignette = 1.0 - smoothstep(0.45, 1.45, length(p));
  col *= vignette;

  return vec4(clamp(col * f.intensity * f.glow, 0.0, 1.0), 1.0);
}
''';
