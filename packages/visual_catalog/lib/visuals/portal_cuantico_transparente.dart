const shaderSource = r'''
vec2 rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

vec3 paletteCos(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
  return a + b * cos(6.28318 * (c * t + d));
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

  // Split into 3 chromatic channels for subtle optical dispersion
  for (int ch = 0; ch < 3; ch++) {
    float dispersion = float(ch - 1) * (0.012 + 0.022 * spark);
    vec2 cp = p * (1.0 + dispersion);

    float r = length(cp);
    // Logarithmic tunnel coordinate moving into the screen
    float z = 1.0 / (r + 0.06);
    float tunnelDepth = z * 0.55 - t * (1.1 + 0.9 * energy);

    // Dynamic rotation modulated by sub-bass and flow
    vec2 q = rotate2D(cp, t * 0.25 + z * 0.12 + bass * 0.35);

    // Iterated Sacred Geometry / Kaleidoscope Folding
    float accum = 0.0;
    vec2 k = q * (1.8 + 0.4 * flow);
    for (int i = 0; i < 4; i++) {
      float fi = float(i);
      k = abs(k) - vec2(0.32 + 0.12 * sin(t * 0.6 + fi * 1.3), 0.22 + 0.08 * cos(t * 0.45));
      k = rotate2D(k, 0.785398 + 0.25 * bass + fi * 0.3);
      accum += 1.0 / (length(k) * 22.0 + 1.0);
    }

    // Glowing harmonic tunnel rings
    float ringPattern = abs(sin(tunnelDepth * 3.14159));
    float ringGlow = (0.025 + 0.035 * bass) / (ringPattern * ringPattern + 0.007);

    // Center singularity core radiance
    float core = (0.10 + 0.35 * bass) / (r * r * 18.0 + 0.12);

    // Color ramp: electric cyan, deep magenta, warm gold
    vec3 pal = paletteCos(
      tunnelDepth * 0.16 + float(ch) * 0.06 + t * 0.05,
      vec3(0.5, 0.5, 0.5),
      vec3(0.5, 0.5, 0.5),
      vec3(1.0, 1.0, 1.0),
      vec3(0.05, 0.33, 0.67)
    );

    float intensity = (accum * 0.42 + ringGlow * 0.48 + core * 0.6) * f.intensity * f.glow;

    if (ch == 0) col.r += intensity * pal.r;
    else if (ch == 1) col.g += intensity * pal.g;
    else if (ch == 2) col.b += intensity * pal.b;
  }

  // Soft tone mapping and subtle cinematic vignette
  col = col / (col + vec3(0.85));
  float vignette = 1.0 - smoothstep(0.45, 1.45, length(p));
  col *= vignette;

  // RGBA recto: el motor multiplica por alpha al componer.
  float alpha = clamp(max(col.r, max(col.g, col.b)) * 1.6, 0.0, 1.0);
  return vec4(clamp(col, 0.0, 1.0), alpha);
}
''';
