const shaderSource = r'''
float liquidField(vec2 p, float t, float bass, float spark, float flow) {
  float r = length(p);
  // Concentric liquid ripples expanding from center
  float ripple = sin(r * (14.0 + 3.0 * flow) - t * 3.8) * (0.035 + 0.055 * bass);

  // Cross-interfering droplet orbits
  vec2 c1 = vec2(sin(t * 0.7) * 0.42, cos(t * 0.8) * 0.35);
  vec2 c2 = vec2(cos(t * 0.9 + 1.8) * 0.38, sin(t * 0.6) * 0.42);
  float wave1 = sin(length(p - c1) * 16.0 - t * 4.2) * (0.025 + 0.035 * bass);
  float wave2 = sin(length(p - c2) * 18.0 - t * 3.6) * (0.020 + 0.030 * spark);

  // High-frequency surface sizzle from spark / hi-hats
  float sizzle = sin(p.x * 32.0 + t * 4.5) * cos(p.y * 32.0 + t * 4.0) * (0.006 + 0.018 * spark);

  // Base organic dome
  float dome = exp(-r * r * 2.2) * 0.16;

  return dome + ripple + wave1 + wave2 + sizzle;
}

vec4 paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.1;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.48;

  // Surface Normal via finite differences
  float eps = 0.0035;
  float hC = liquidField(p, t, bass, spark, flow);
  float hR = liquidField(p + vec2(eps, 0.0), t, bass, spark, flow);
  float hU = liquidField(p + vec2(0.0, eps), t, bass, spark, flow);

  vec3 normal = normalize(vec3((hC - hR) / eps, (hC - hU) / eps, 0.32));

  // Environmental reflection vector
  vec3 view = normalize(vec3(p * 0.22, 1.0));
  vec3 ref = reflect(-view, normal);

  // Studio lighting environment ramp (chrome horizon, deep velvet zenith)
  float horizon = smoothstep(-0.25, 0.25, ref.y);
  float stripe = sin(ref.y * 12.0 + ref.x * 6.0 + t * 0.25);
  float studioStripe = smoothstep(0.35, 0.75, stripe);

  vec3 deepMetal = vec3(0.02, 0.035, 0.07);
  vec3 silver = vec3(0.85, 0.90, 0.98);
  vec3 neonCyan = vec3(0.20, 0.85, 1.0);
  vec3 neonMagenta = vec3(0.95, 0.20, 0.65);

  vec3 chrome = mix(deepMetal, silver, horizon * 0.8 + studioStripe * 0.25);

  // Directional specular glints
  vec3 lightDir1 = normalize(vec3(-0.45, 0.7, 0.6));
  float spec1 = pow(max(dot(ref, lightDir1), 0.0), 36.0) * (1.6 + 2.4 * spark);
  vec3 lightDir2 = normalize(vec3(0.55, -0.5, 0.55));
  float spec2 = pow(max(dot(ref, lightDir2), 0.0), 22.0) * (0.8 + 1.4 * bass);

  // Fresnel rim glow with subtle chromatic sheen
  float fresnel = pow(1.0 - max(dot(normal, view), 0.0), 2.6);
  vec3 rimColor = mix(neonCyan, neonMagenta, 0.5 + 0.5 * sin(t * 0.35 + p.y * 2.2));

  // Combine chrome surface
  vec3 surface = chrome + (spec1 + spec2) * vec3(1.0, 0.98, 0.93) + fresnel * rimColor * (0.65 + 0.85 * energy);

  // Smooth dropoff into transparency
  float fluidAlpha = smoothstep(1.35, 0.65, length(p));
  float alpha = fluidAlpha * smoothstep(0.04, 0.20, max(surface.r, max(surface.g, surface.b)));

  return vec4(clamp(surface * f.intensity * f.glow * alpha, 0.0, 1.0), alpha);
}
''';
