const shaderSource = r'''
vec2 rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.3;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.44;

  float r = length(p);
  float eventHorizon = 0.26 + 0.05 * bass;

  // Gravitational deflection / Einstein ring lensing
  vec2 lensP = p;
  if (r > eventHorizon) {
    float defl = (eventHorizon * eventHorizon) / (r * r + 0.001);
    lensP = p * (1.0 - defl * 0.42);
  }

  // Accretion disk coordinate with tilt and logarithmic spiral
  vec2 diskP = lensP;
  diskP.y *= 2.35; // 3D orbital inclination tilt
  diskP = rotate2D(diskP, 0.38);

  float diskR = length(diskP);
  // Analytical polar angle
  float diskAngle = atan(diskP.y / (diskP.x + 0.00001)) + (diskP.x < 0.0 ? 3.14159 : 0.0);

  // Swirling plasma arms in relativistic accretion disk
  float spiral = diskAngle * 2.0 - log(diskR + 0.001) * 3.4 - t * (2.2 + 1.4 * flow + 1.8 * energy);
  float arm1 = sin(spiral) * 0.5 + 0.5;
  float arm2 = sin(spiral * 2.0 + 1.3) * 0.5 + 0.5;
  float arms = arm1 * 0.7 + arm2 * 0.3;

  // Accretion disk radial bounds
  float diskMask = smoothstep(eventHorizon * 0.88, eventHorizon * 1.32, diskR) *
                   smoothstep(1.65, eventHorizon * 1.5, diskR);

  // Doppler boosting: approaching plasma orbital side is brighter and hotter
  float doppler = 1.0 - clamp(diskP.x * 0.65, -0.65, 0.65);

  // Photon ring radiance directly surrounding event horizon boundary
  float photonDist = abs(r - eventHorizon);
  float photonRing = (0.012 + 0.025 * bass) / (photonDist * photonDist + 0.0028);

  // Color temperature ramp: from fiery volcanic orange to burning electric cyan
  vec3 hotOrange = vec3(1.0, 0.45, 0.12);
  vec3 electricCyan = vec3(0.25, 0.85, 1.0);
  vec3 pureWhite = vec3(1.0, 0.98, 0.92);

  vec3 diskColor = mix(hotOrange, electricCyan, arms * 0.5 + energy * 0.45);
  diskColor = mix(diskColor, pureWhite, pow(arms, 3.0) * (0.45 + spark * 0.8));

  vec3 col = diskColor * arms * diskMask * doppler * (1.6 + bass * 0.85);
  col += vec3(0.28, 0.72, 1.0) * photonRing * (0.85 + energy * 0.65);

  // Background starfield distorted by gravity
  vec2 starGrid = floor(lensP * 28.0);
  float starHash = hash21(starGrid);
  if (starHash > 0.962) {
    if (r > eventHorizon * 1.15) {
      vec2 starFrac = fract(lensP * 28.0) - 0.5;
      float starDist = length(starFrac);
      float starTwinkle = 0.5 + 0.5 * sin(t * 3.0 + starHash * 30.0);
      float starBright = (0.018 * starTwinkle + 0.028 * spark) / (starDist * starDist * 60.0 + 0.05);
      col += vec3(0.85, 0.92, 1.0) * starBright;
    }
  }

  // Black hole pitch black core shadow
  float shadow = smoothstep(eventHorizon * 0.85, eventHorizon * 1.05, r);
  col *= shadow;

  // Relativistic polar jet radiance
  float jetY = abs(p.y);
  float jetX = abs(p.x);
  float jet = exp(-jetX * 36.0) * smoothstep(0.18, 1.25, jetY) * (0.15 + 0.85 * bass);
  col += electricCyan * jet * 0.55;

  // Cinematic tone mapping and soft vignette
  col = col / (col + vec3(0.92));
  float vignette = 1.0 - smoothstep(0.55, 1.45, length(p));
  col *= vignette;

  float alpha = clamp(max(col.r, max(col.g, col.b)) * 1.8, 0.0, 1.0);
  return vec4(clamp(col * f.intensity * f.glow * alpha, 0.0, 1.0), alpha);
}
''';
