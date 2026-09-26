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

// Multi-octave convective solar plasma noise
float solarNoise(vec2 p, float t) {
  float n = 0.0;
  n = n + sin(p.x * 6.0 + t * 1.2) * cos(p.y * 6.0 - t * 0.9);
  n = n + sin(p.x * 14.0 - t * 1.8 + p.y * 5.0) * 0.5;
  n = n + cos(p.y * 24.0 + t * 3.1 - p.x * 10.0) * 0.25;
  n = n + sin((p.x + p.y) * 36.0 + t * 4.5) * 0.12;
  return n * 0.53;
}

// Blackbody thermal incandescent ramp (0=dark vacuum, 1=blinding white)
vec3 blackbody(float heat) {
  vec3 col = vec3(0.0);
  col = mix(col, vec3(0.65, 0.03, 0.0), smoothstep(0.0, 0.32, heat));
  col = mix(col, vec3(1.0, 0.32, 0.02), smoothstep(0.24, 0.62, heat));
  col = mix(col, vec3(1.0, 0.88, 0.18), smoothstep(0.52, 0.82, heat));
  col = mix(col, vec3(1.0, 1.0, 0.98), smoothstep(0.78, 1.05, heat));
  return col;
}

vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.2;

  float t = f.time * 0.55 * f.speed;
  float bass = clamp(f.bass, 0.0, 1.0);
  float beat = clamp(f.pulse, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);

  float r = length(p);
  float a = getAngle(p);

  // Stellar core radius with bass pulsation
  float coreRadius = 0.34 + bass * 0.09 + beat * 0.04;

  // Background deep space with hot ambient nebula dust
  vec3 col = vec3(0.015, 0.003, 0.008) + vec3(0.14, 0.018, 0.0) * exp(-r * 1.6);

  // Shockwave blast rings propagating outward
  float wavePhase = mod(r * 2.8 - t * 2.0, 2.0);
  float shock = exp(-abs(wavePhase - 1.0) * 14.0) * exp(-r * 0.9);
  col = col + vec3(1.0, 0.45, 0.08) * shock * (0.6 + 0.9 * bass);

  // Solar Prominences / coronal mass ejections (flares radiating outward)
  float flares = 0.0;
  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    float flareAngle = fi * 1.047 + sin(t * 0.4 + fi * 1.2) * 0.35;
    float da = abs(mod(a - flareAngle + 3.14159, 6.28318) - 3.14159);
    float flareDist = abs(r - (coreRadius + 0.18 + 0.16 * sin(t * 2.2 + fi * 2.0) + bass * 0.18));
    float flareIntensity = exp(-da * 8.5) * exp(-flareDist * 9.0);
    flares = flares + flareIntensity;
  }
  col = col + vec3(1.0, 0.38, 0.06) * flares * 2.0;

  // Ethereal coronal streamers (solar wind filaments)
  float rays = sin(a * 16.0 + t * 2.2 + sin(r * 6.0 - t * 3.5)) * 0.5 + 0.5;
  rays = rays * smoothstep(coreRadius * 0.8, 1.3, r) * exp(-r * 2.0);
  col = col + vec3(1.0, 0.55, 0.12) * rays * (0.8 + 0.8 * beat);

  // Magnetic coronal loops (toroidal magnetic flux arches)
  for (int m = 0; m < 5; m++) {
    float fm = float(m);
    vec2 loopCenter = vec2(cos(fm * 1.256 + t * 0.35), sin(fm * 1.256 + t * 0.35)) * (coreRadius * 0.92);
    float dLoop = length(p - loopCenter);
    float loopRadius = 0.13 + 0.05 * sin(t * 1.6 + fm * 1.8);
    float loopRing = abs(dLoop - loopRadius);
    float loopGlow = 0.0035 / (loopRing * loopRing * 22.0 + 0.004);
    col = col + vec3(1.0, 0.75, 0.25) * loopGlow * (0.7 + 0.6 * spark);
  }

  // Solar photosphere surface with boiling convective granulation
  if (r < coreRadius * 1.25) {
    vec2 surfCoord = rotate2D(p, t * 0.18);
    float granulation = solarNoise(surfCoord * 5.0, t * 1.5);
    
    // Radial darkening towards the limb, searing nuclear interior
    float radialFactor = clamp((coreRadius - r) / coreRadius, 0.0, 1.0);
    float heat = radialFactor * 0.92 + granulation * 0.32 + bass * 0.35;
    vec3 sunSurface = blackbody(clamp(heat, 0.0, 1.25));

    // Crisp limb transition with solar atmosphere rim
    float diskAlpha = smoothstep(coreRadius + 0.02, coreRadius - 0.02, r);
    col = mix(col, sunSurface, diskAlpha);
  }

  // Radiant nuclear core glow
  float coreGlow = 0.06 / (r * r * 8.5 + 0.06);
  col = col + vec3(1.0, 0.92, 0.75) * coreGlow * (0.9 + 1.1 * bass);

  // High-energy relativistic plasma sparks
  for (int s = 0; s < 8; s++) {
    float fs = float(s);
    float spAngle = fs * 0.785 + t * (1.3 + 0.25 * fs);
    float spRad = coreRadius + 0.10 + 0.28 * fract(sin(fs * 43.12) * 532.1 + t * 0.45);
    vec2 spPos = vec2(cos(spAngle), sin(spAngle)) * spRad;
    float spDist = length(p - spPos);
    float sparkGlow = 0.002 / (spDist * spDist * 32.0 + 0.002);
    col = col + vec3(1.0, 0.9, 0.4) * sparkGlow * (1.0 + 1.3 * spark);
  }

  // Soft tone mapping and subtle vignette
  col = col / (col + vec3(0.82));
  float vig = 1.0 - smoothstep(0.5, 1.5, r);
  col = col * vig * f.intensity * f.glow;

  return vec4(clamp(col, 0.0, 1.0), 1.0);
}
''';
