const shaderSource = r'''
vec2 rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float getAngle(vec2 p) {
  float r = length(p);
  if (r < 0.00001) { return 0.0; }
  float a = asin(clamp(p.y / r, -1.0, 1.0));
  if (p.x < 0.0) {
    a = 3.14159265 - a;
  }
  if (a < 0.0) {
    a = a + 6.2831853;
  }
  return a;
}

vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.2;

  float r = length(p);
  float a = getAngle(p);

  float beat = clamp(f.pulse, 0.0, 1.0);
  float bass = clamp(f.bass, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);
  float t = f.time * 0.42 * f.speed;

  vec3 col = vec3(0.0);

  // Fibonacci Petal Ring 1 (Inner 5 petals)
  float a1 = a + t * 0.6;
  float pet1 = cos(5.0 * a1);
  float r1 = 0.18 + 0.08 * pet1 + bass * 0.06;
  float d1 = abs(r - r1);
  float edge1 = 0.012 / (d1 + 0.012);
  vec3 col1 = mix(vec3(1.0, 0.85, 0.2), vec3(1.0, 0.25, 0.6), 0.5 + 0.5 * pet1);
  col = col + col1 * edge1 * 0.7;

  // Fibonacci Petal Ring 2 (Middle 8 petals, counter-rotating)
  float a2 = a - t * 0.4;
  float pet2 = cos(8.0 * a2);
  float r2 = 0.35 + 0.12 * pet2 + beat * 0.08;
  float d2 = abs(r - r2);
  float edge2 = 0.015 / (d2 + 0.018);
  vec3 col2 = mix(vec3(0.2, 0.85, 1.0), vec3(0.9, 0.1, 0.7), 0.5 + 0.5 * pet2);
  col = col + col2 * edge2 * 0.65;

  // Fibonacci Petal Ring 3 (Outer 13 petals)
  float a3 = a + t * 0.25;
  float pet3 = cos(13.0 * a3);
  float r3 = 0.58 + 0.15 * pet3 + bass * 0.1;
  float d3 = abs(r - r3);
  float edge3 = 0.018 / (d3 + 0.022);
  vec3 col3 = mix(vec3(0.95, 0.3, 0.8), vec3(1.0, 0.7, 0.2), 0.5 + 0.5 * pet3);
  col = col + col3 * edge3 * 0.6;

  // Fibonacci Petal Ring 4 (Ethereal 21 filaments)
  float a4 = a - t * 0.15;
  float pet4 = cos(21.0 * a4);
  float r4 = 0.82 + 0.14 * pet4 + beat * 0.06;
  float d4 = abs(r - r4);
  float edge4 = 0.012 / (d4 + 0.025);
  vec3 col4 = mix(vec3(0.4, 0.3, 1.0), vec3(0.2, 0.95, 0.8), 0.5 + 0.5 * pet4);
  col = col + col4 * edge4 * (0.4 + 0.3 * spark);

  // Sacred golden spiral rays
  float spiral1 = sin(log(r + 0.02) * 5.0 - a * 3.0 + t * 1.2);
  float spiral2 = sin(log(r + 0.02) * 5.0 + a * 3.0 - t * 1.2);
  float spiralGrid = smoothstep(0.85, 0.98, spiral1) + smoothstep(0.85, 0.98, spiral2);
  col = col + vec3(1.0, 0.8, 0.3) * spiralGrid * 0.35 * exp(-r * 1.8);

  // Radiant Golden Core / Lotus Stamen
  float coreDist = r;
  float coreGlow = 0.04 / (coreDist * coreDist * 6.0 + 0.04);
  float corePulse = 1.0 + 0.4 * sin(t * 4.0) + bass * 0.8;
  vec3 coreColor = mix(vec3(1.0, 0.95, 0.5), vec3(1.0, 0.4, 0.1), clamp(r * 5.0, 0.0, 1.0));
  col = col + coreColor * coreGlow * corePulse * 1.2;

  // Stardust / Pollen particles swirling around the flower
  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    float pAngle = fi * 1.047 + t * (0.8 + 0.2 * fi);
    float pRad = 0.25 + 0.15 * sin(fi * 2.1 + t * 1.5) + bass * 0.1;
    vec2 pPos = vec2(cos(pAngle), sin(pAngle)) * pRad;
    float pDist = length(p - pPos);
    float pGlow = 0.003 / (pDist * pDist * 25.0 + 0.003);
    col = col + vec3(1.0, 0.9, 0.4) * pGlow * (0.8 + 0.8 * spark);
  }

  // Soft tone mapping and cinematic vignette
  col = col / (col + vec3(0.85));
  float vig = 1.0 - smoothstep(0.5, 1.5, r);
  col = col * vig * f.intensity * f.glow;

  // RGBA recto: el motor multiplica por alpha al componer.
  float alpha = clamp(max(col.r, max(col.g, col.b)) * 1.6, 0.0, 1.0);
  return vec4(clamp(col, 0.0, 1.0), alpha);
}
''';
