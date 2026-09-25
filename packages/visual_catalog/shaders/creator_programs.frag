// Generated from packages/visual_catalog/lib/visuals/*.dart. Do not edit.
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uSeedLow;
uniform float uSeedHigh;
uniform float uEnergy;
uniform float uBass;
uniform float uBody;
uniform float uSpark;
uniform float uFlow;
uniform float uPulse;
uniform float uPhase;
uniform float uBpm;
uniform float uIntensity;
uniform float uSpeed;
uniform float uDetail;
uniform float uGlow;
uniform vec4 uColor0;
uniform vec4 uColor1;
uniform vec4 uColor2;
uniform vec4 uColor3;
uniform float uVisualIndex;
out vec4 fragColor;
struct CreatorFrame {
  vec2 size; float time; float seedLow; float seedHigh;
  float energy; float bass; float body; float spark;
  float flow; float pulse; float phase; float bpm;
  float intensity; float speed; float detail; float glow;
  vec4 color0; vec4 color1; vec4 color2; vec4 color3;
};
float creator_0_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
vec2 creator_0_hash23(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.zyx + 31.32);
  return fract(vec2((q.x + q.y) * q.z, (q.x + q.z) * q.y));
}
float creator_0_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0);
  float a = creator_0_hash13(i);
  float b = creator_0_hash13(i + vec2(1.0, 0.0));
  float c = creator_0_hash13(i + vec2(0.0, 1.0));
  float d = creator_0_hash13(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float creator_0_fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * creator_0_vnoise(p);
    p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.02 + vec2(3.1, 7.7);
    a *= 0.5;
  }
  return v;
}
vec3 creator_0_grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
vec4 creator_0_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.013;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 col = mix(vec3(0.010, 0.015, 0.036), vec3(0.003, 0.005, 0.016), smoothstep(0.0, 1.0, uv.y));
  col += f.color1.rgb * creator_0_fbm4(vec2(p.x * 0.9 + seed, uv.y * 1.4 - t * 0.008)) * 0.030;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (15.0 + k * 13.0) + vec2(seed * 9.0 + k * 31.0, k * 17.0);
    gp.y += t * (0.005 + 0.004 * k);
    vec2 cell = floor(gp);
    vec2 h = creator_0_hash23(cell + k * 7.0);
    float on = step(0.958 - 0.022 * k, h.x);
    vec2 pos = cell + 0.25 + 0.5 * h;
    float tw = 0.6 + 0.4 * sin(t * (0.6 + 1.6 * h.y) + h.x * 6.2831853);
    vec2 dd = gp - pos;
    float d = sqrt(dot(dd, dd));
    float r0 = (0.030 + 0.024 * h.y) * (1.0 + 0.5 * f.spark);
    float core = 1.0 - smoothstep(r0 - px * 1.5, r0 + px * 1.5, d);
    col += vec3(0.74, 0.82, 1.0) * (core * on * tw * (0.28 + 0.22 * k)) * (0.7 + 0.6 * f.glow);
  }
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    float base = 0.62 + 0.09 * k;
    float drift = t * (0.026 + 0.011 * k) + seed + k * 3.7;
    float warp = creator_0_fbm4(vec2(p.x * (1.4 + 0.5 * k) + drift * (1.7 + 0.5 * k), drift * 0.6 + k * 5.0));
    float baseY = base + 0.11 * (warp - 0.5);
    float onoff = smoothstep(0.34, 0.62, creator_0_fbm4(vec2(p.x * 1.15 + drift * 2.6 + k * 9.0, k * 4.1)));
    float above = uv.y - baseY;
    float fadeK = 4.6 + 1.4 * k;
    float body = exp(-max(above, 0.0) * fadeK) * step(0.0, above);
    float rim = exp(-abs(above) * 46.0);
    float rays = 0.60 + 0.40 * creator_0_vnoise(vec2(p.x * (26.0 + 10.0 * k) + drift * 3.2, k * 3.0 + drift * 0.5));
    float curtain = onoff * rays * (rim * 0.85 + body * 0.30);
    float hMix = clamp(above * 3.2, 0.0, 1.0);
    vec3 ink = mix(f.color1.rgb, f.color2.rgb, hMix);
    ink = mix(ink, f.color3.rgb, pow(hMix, 2.5) * 0.55);
    col += ink * curtain * (0.30 + 0.26 * f.bass) * (0.80 + 0.34 * f.energy + 0.20 * f.pulse);
  }
  float ground = smoothstep(0.055, -0.01, uv.y);
  col = mix(col, vec3(0.004, 0.007, 0.014), ground * 0.85);
  col = creator_0_grade(col * f.intensity);
  col += (creator_0_hash13(uv * f.size + seed) - 0.5) * 0.007;
  float vig = clamp(1.06 - dot(p, p) * 0.20, 0.55, 1.0);
  return vec4(col * vig, 1.0);
}

vec2 creator_1_hash23(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.zyx + 31.32);
  return fract(vec2((q.x + q.y) * q.z, (q.x + q.z) * q.y));
}
mat2 creator_1_rot2r(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat2(c, -s, s, c);
}
vec4 creator_1_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0);
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 acc = vec3(0.0);
  float aAcc = 0.0;
  for (int i = 0; i < 5; i++) {
    float k = float(i);
    vec2 h = creator_1_hash23(vec2(k * 7.7 + seed * 0.11, k * 3.3 + 1.0));
    float ring = 0.105 + 0.042 * k;
    float orbA = k * 1.2566371 + t * (0.085 + 0.030 * h.y) * (1.0 + 0.6 * f.flow);
    float bob = 0.010 * sin(t * 0.45 + k * 2.1);
    vec2 c = vec2(cos(orbA) * ring * min(aspect, 1.15), sin(orbA) * ring * 0.88 + bob);
    float spin = t * (0.30 + 0.45 * h.y) * (1.0 + 0.4 * f.flow) + h.x * 6.2831853 + k;
    vec2 lp = creator_1_rot2r(spin) * (p - c);
    float s = (0.030 + 0.028 * h.x) * (1.0 + 0.16 * f.bass);
    float shape = 0.9 + 0.16 * sin(k * 2.1 + t * 0.32 + seed);
    float d = (abs(lp.x) * 0.58 + abs(lp.y) * 1.0) / shape - s;
    float fill = 1.0 - smoothstep(-px * 1.4, px * 1.4, d);
    float facet = 0.5 + 0.5 * sin(lp.x * (38.0 + 14.0 * h.y) + lp.y * 24.0 + k * 3.1 + t * 0.09);
    vec2 nl = lp / max(length(lp), 0.0001);
    float sheen = pow(clamp(0.5 + 0.5 * dot(vec2(0.55, 0.83), nl), 0.0, 1.0), 3.2);
    float ew = px * 1.6;
    float eR = exp(-abs(d + 0.0045) / max(ew * 1.6, 0.0008));
    float eG = exp(-abs(d) / max(ew * 1.4, 0.0008));
    float eB = exp(-abs(d - 0.0045) / max(ew * 1.6, 0.0008));
    float kick = 0.55 + 0.30 * f.pulse + 0.15 * f.bass;
    acc += vec3(1.0, 0.30, 0.50) * eR * 0.27 * kick;
    acc += vec3(1.0) * eG * 0.46 * kick * (0.65 + 0.55 * facet);
    acc += vec3(0.32, 0.78, 1.0) * eB * 0.27 * kick;
    vec3 glass = mix(f.color1.rgb, f.color2.rgb, facet);
    glass = mix(glass, f.color3.rgb, sheen * 0.55);
    acc += glass * fill * (0.20 + 0.24 * sheen + 0.07 * facet);
    aAcc += fill * (0.17 + 0.20 * sheen + 0.05 * facet) * (0.75 + 0.5 * f.glow);
    aAcc += (eR + eG + eB) * 0.40 * kick;
    float ty = s * shape * 1.15;
    float tdx = lp.x;
    float tdy = abs(lp.y) - ty;
    float td2 = tdx * tdx + tdy * tdy;
    float tw2 = pow(0.5 + 0.5 * sin(t * (0.9 + 1.4 * h.x) + k * 4.0), 3.0);
    float glint = exp(-td2 * 3000.0) * (0.18 + 0.82 * tw2) * (0.30 + 0.70 * f.spark);
    acc += vec3(1.0, 0.95, 0.85) * glint * 0.38;
    aAcc += glint * 0.22;
  }
  return vec4(acc * f.intensity, clamp(aAcc * (0.55 + 0.45 * f.glow), 0.0, 0.90));
}

float creator_2_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
vec2 creator_2_hash23(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.zyx + 31.32);
  return fract(vec2((q.x + q.y) * q.z, (q.x + q.z) * q.y));
}
float creator_2_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0);
  float a = creator_2_hash13(i);
  float b = creator_2_hash13(i + vec2(1.0, 0.0));
  float c = creator_2_hash13(i + vec2(0.0, 1.0));
  float d = creator_2_hash13(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float creator_2_fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * creator_2_vnoise(p);
    p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.02 + vec2(3.1, 7.7);
    a *= 0.5;
  }
  return v;
}
vec3 creator_2_grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
vec4 creator_2_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.017;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 col = mix(f.color0.rgb * 0.45, f.color0.rgb * 1.15, smoothstep(0.0, 1.0, uv.y));
  vec2 w = vec2(t * 0.010 + seed, -t * 0.007) * (1.0 + f.flow * 0.7);
  float n1 = creator_2_fbm4(p * 2.1 + w + seed);
  float n2 = creator_2_fbm4(p * 3.0 - w * 1.25 + 1.9 * n1 + 4.7);
  float neb1 = pow(clamp(n1 * 1.62 - 0.40, 0.0, 1.0), 1.8);
  float neb2 = pow(clamp(n2 * 1.55 - 0.46, 0.0, 1.0), 2.1);
  col += f.color1.rgb * neb1 * (0.30 + 0.30 * f.bass);
  col += f.color2.rgb * neb2 * (0.26 + 0.24 * f.body);
  float dust = pow(clamp(creator_2_fbm4(p * 4.2 + n2 * 1.6 - w + 9.1), 0.0, 1.0), 2.3);
  col *= 1.0 - 0.42 * dust;
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (11.0 + k * 10.0) + vec2(seed * 2.3 + k * 9.7, k * 4.3)
            - vec2(0.0, t * (0.030 + 0.018 * k));
    vec2 cell = floor(gp);
    vec2 h = creator_2_hash23(cell + k * 23.0);
    float on = step(0.935 - 0.025 * k, h.x);
    vec2 pos = cell + 0.30 + 0.40 * h;
    float tw = 0.55 + 0.45 * sin(t * (0.9 + 2.2 * h.y) + h.x * 6.2831853);
    vec2 dd = gp - pos;
    float d = sqrt(dot(dd, dd));
    float r0 = (0.020 + 0.030 * h.y) * (1.0 + 0.45 * f.spark);
    float core = 1.0 - smoothstep(r0 - px * 1.4, r0 + px * 1.4, d);
    float flare = exp(-dd.y * dd.y * 900.0) * exp(-abs(dd.x) * 220.0) * step(0.985, h.x) * 0.35;
    col += vec3(0.80, 0.86, 1.0) * (core + flare) * on * tw * 0.40 * (0.55 + 0.65 * f.glow);
  }
  float ct = floor(t / 11.0 + seed);
  float cs = fract(t / 11.0 + seed);
  vec2 sh = creator_2_hash23(vec2(ct * 3.7, ct * 1.9) + seed);
  float life = smoothstep(0.0, 0.14, cs) * smoothstep(0.42, 0.16, cs);
  if (life > 0.001) {
    vec2 head = vec2(mix(-0.25, 0.55, sh.x) + cs * mix(0.65, 0.95, sh.y),
                     mix(0.05, 0.38, sh.y) + cs * mix(0.22, 0.50, sh.x));
    vec2 q2 = vec2(p.x, uv.y) - head;
    float along = dot(q2, vec2(0.82, 0.57));
    float perp2 = dot(q2, vec2(-0.57, 0.82));
    float tail = exp(-max(-along, 0.0) * 16.0) * 0.55 + exp(-max(along, 0.0) * 60.0);
    float shoot = life * exp(-perp2 * perp2 * 3200.0) * tail;
    col += vec3(0.95, 0.97, 1.0) * clamp(shoot, 0.0, 1.0) * 0.7;
  }
  col = creator_2_grade(col * f.intensity);
  col += (creator_2_hash13(uv * f.size + seed) - 0.5) * 0.008;
  float vig = clamp(1.06 - dot(p, p) * 0.30, 0.5, 1.0);
  return vec4(col * vig, 1.0);
}

float creator_3_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
vec2 creator_3_hash23(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.zyx + 31.32);
  return fract(vec2((q.x + q.y) * q.z, (q.x + q.z) * q.y));
}
float creator_3_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0);
  float a = creator_3_hash13(i);
  float b = creator_3_hash13(i + vec2(1.0, 0.0));
  float c = creator_3_hash13(i + vec2(0.0, 1.0));
  float d = creator_3_hash13(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float creator_3_fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * creator_3_vnoise(p);
    p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.02 + vec2(3.1, 7.7);
    a *= 0.5;
  }
  return v;
}
vec3 creator_3_grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
vec4 creator_3_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.019;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 col = mix(f.color0.rgb * 0.50, f.color0.rgb * 0.22, smoothstep(0.25, 1.0, uv.y));
  float rise = t * (0.85 + 0.95 * f.flow) + seed;
  float n = creator_3_fbm4(vec2(p.x * (5.0 * f.detail) + seed, uv.y * 3.0 - rise));
  n = pow(clamp(n * 1.52 - 0.06, 0.0, 1.0), 1.8);
  float lift = uv.y / (0.33 + 0.15 * f.bass + 0.02 * f.energy);
  float heat = clamp(n * 1.90 - lift * 1.06 + 0.30, 0.0, 1.25);
  heat *= 0.52 + 0.48 * smoothstep(-0.03, 0.10, uv.y);
  vec3 fireCol = mix(f.color1.rgb, f.color2.rgb, clamp(heat * 1.45, 0.0, 1.0));
  fireCol = mix(fireCol, f.color3.rgb, pow(clamp(heat * 1.45 - 0.80, 0.0, 1.0), 1.7));
  col += fireCol * heat * (0.85 + 0.40 * f.energy + 0.30 * f.pulse);
  float bed = exp(-(1.0 - uv.y) * 5.0);
  float pockets = pow(clamp(creator_3_vnoise(vec2(p.x * (6.5 * f.detail) + seed, t * 0.35)) * 1.45 - 0.30, 0.0, 1.0), 2.2);
  col += mix(f.color1.rgb, f.color2.rgb, pockets) * bed * (0.34 + 0.42 * f.bass) * (0.35 + 0.85 * pockets);
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    float cols = 7.0 + k * 6.0;
    vec2 gp = vec2(p.x * cols + seed * 7.0 + k * 19.0,
                   (uv.y + t * (0.09 + 0.07 * k) * (1.0 + 0.5 * f.flow)) * (cols * 0.60));
    gp.x += 0.6 * sin(t * 0.5 + k * 2.0 + uv.y * 5.0);
    vec2 cell = floor(gp);
    vec2 h = creator_3_hash23(cell + k * 41.0);
    float on = step(0.72, h.y);
    vec2 pos = cell + 0.25 + 0.50 * h;
    vec2 dd = gp - pos;
    float d2 = dot(dd, dd);
    float flick = pow(0.5 + 0.5 * sin(t * (1.8 + 2.6 * h.x) + h.y * 6.2831853), 2.2);
    float ember = on * exp(-d2 * (620.0 - k * 120.0)) * flick * (0.40 + 1.20 * f.spark);
    vec3 emberCol = mix(f.color3.rgb, f.color2.rgb, smoothstep(1.0, 0.30, uv.y));
    col += emberCol * ember * 0.72 * (0.7 + 0.5 * f.bass);
  }
  col = creator_3_grade(col * f.intensity);
  col += (creator_3_hash13(uv * f.size + seed) - 0.5) * 0.008;
  float vig = clamp(1.08 - dot(p, p) * 0.34, 0.42, 1.0);
  return vec4(col * vig, 1.0);
}

float creator_4_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
vec2 creator_4_hash23(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.zyx + 31.32);
  return fract(vec2((q.x + q.y) * q.z, (q.x + q.z) * q.y));
}
vec4 creator_4_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.011;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 acc = vec3(0.0);
  float aAcc = 0.0;
  for (int i = 0; i < 4; i++) {
    float k = float(i);
    float scale = 4.0 + k * 3.6;
    vec2 gp = vec2(p.x, uv.y) * scale;
    gp.y += t * (0.10 + 0.06 * k) * (1.0 + 0.7 * f.flow);
    gp.x += seed + 0.45 * sin(t * 0.18 + k * 2.3 + uv.y * 1.5) + k * 13.7;
    vec2 cell = floor(gp);
    vec2 h = creator_4_hash23(cell + k * 31.0);
    float on = step(h.y, 0.70 - 0.05 * k);
    vec2 pos = cell + 0.25 + 0.50 * h;
    vec2 dv = gp - pos;
    float d2 = dot(dv, dv);
    float twRaw = 0.5 + 0.5 * sin(t * (0.6 + 2.1 * h.y) + h.x * 6.2831853);
    float eased = twRaw * twRaw * (3.0 - 2.0 * twRaw);
    float tw = 0.10 + 0.90 * pow(clamp(eased + 0.30 * f.spark - 0.14, 0.0, 1.0), 1.6);
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.x);
    float big = step(1.5, k);
    float small = 1.0 - big;
    float rad = (0.10 + 0.08 * h.x) * (1.0 + 0.25 * f.bass);
    float core = exp(-d2 / max(rad * rad, 0.0001)) * small;
    float disc = 1.0 - smoothstep(0.55, 0.62, sqrt(d2)) * big;
    float halo = exp(-sqrt(d2) * (7.0 + k * 2.5)) * 0.30 * small;
    float fx = exp(-abs(dv.x) * 120.0) * exp(-abs(dv.y) * 16.0)
             + exp(-abs(dv.y) * 120.0) * exp(-abs(dv.x) * 16.0);
    float flare = fx * step(2.5, k) * 0.38;
    float bodyA = core + halo * tw * (0.35 + 0.65 * f.glow) + flare * tw;
    float discA = disc * big * (0.045 + 0.035 * tw) * (0.6 + 0.4 * f.glow);
    vec3 discTint = mix(f.color1.rgb, f.color2.rgb, 0.6 + 0.3 * h.y);
    acc += (tint * bodyA + discTint * discA) * f.intensity
         * (0.60 + 0.50 * f.bass + 0.40 * f.pulse * tw);
    aAcc += (bodyA * (0.34 - 0.05 * k) + discA * 0.8) * (0.55 + 0.45 * f.glow);
  }
  return vec4(acc, clamp(aAcc, 0.0, 0.82));
}

float creator_5_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
vec2 creator_5_hash23(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.zyx + 31.32);
  return fract(vec2((q.x + q.y) * q.z, (q.x + q.z) * q.y));
}
float creator_5_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0);
  float a = creator_5_hash13(i);
  float b = creator_5_hash13(i + vec2(1.0, 0.0));
  float c = creator_5_hash13(i + vec2(0.0, 1.0));
  float d = creator_5_hash13(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float creator_5_fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * creator_5_vnoise(p);
    p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.02 + vec2(3.1, 7.7);
    a *= 0.5;
  }
  return v;
}
vec3 creator_5_grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
vec4 creator_5_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float r = length(p) + 0.0001;
  vec2 dir = p / r;
  float ang = acos(clamp(dir.x, -1.0, 1.0));
  if (dir.y < 0.0) {
    ang = 6.2831853 - ang;
  }
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.007;
  float px = 1.0 / max(f.size.y, 1.0);
  float warp = t * 0.55 + seed + 0.28 * f.flow + 0.20 * f.bass;
  vec3 col = f.color0.rgb * (0.80 - 0.40 * clamp(r, 0.0, 1.0));
  float n = creator_5_fbm4(dir * 2.0 + vec2(seed, r * 2.6 - warp * 0.7));
  col += f.color2.rgb * pow(clamp(n * 1.45 - 0.48, 0.0, 1.0), 2.3) * 0.30;
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    float ci = 26.0 + k * 20.0;
    float ac = ang / 6.2831853 * ci;
    float ai = floor(ac);
    float af = fract(ac);
    vec2 h = creator_5_hash23(vec2(ai + k * 57.0, k * 13.7 + seed * 3.0));
    float dAng = abs(af - 0.5 - (h.x - 0.5) * 0.60);
    float z = fract(h.y * 7.31 + warp * (0.50 + 0.28 * k));
    float rr = 0.02 + 1.50 * z * z;
    float sw = 0.030 + 0.26 * z;
    float aw = max(0.045 + 0.09 * z, px * 1.4 * ci / 6.2831853 / max(r, 0.03));
    float dr = (r - rr) / sw;
    float streak = exp(-dAng * dAng / (aw * aw)) * exp(-dr * dr);
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.x);
    tint = mix(tint, f.color3.rgb, z * z * 0.60);
    float head = pow(clamp(z, 0.0, 1.0), 5.0);
    col += tint * streak * smoothstep(0.02, 0.20, z) * (0.32 + 0.62 * z)
         * (0.52 + 0.70 * f.energy + 0.28 * f.pulse);
    col += vec3(1.0) * streak * head * 0.25 * (0.4 + 0.8 * f.spark);
  }
  col += mix(f.color2.rgb, f.color3.rgb, 0.4) * exp(-r * (8.0 - 2.2 * f.bass))
       * (0.30 + 0.45 * f.bass + 0.30 * f.pulse);
  col = creator_5_grade(col * f.intensity);
  col += (creator_5_hash13(uv * f.size + seed) - 0.5) * 0.006;
  float vig = clamp(1.08 - dot(p, p) * 0.26, 0.40, 1.0);
  return vec4(col * vig, 1.0);
}

float creator_6_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
float creator_6_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0);
  float a = creator_6_hash13(i);
  float b = creator_6_hash13(i + vec2(1.0, 0.0));
  float c = creator_6_hash13(i + vec2(0.0, 1.0));
  float d = creator_6_hash13(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float creator_6_fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * creator_6_vnoise(p);
    p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.02 + vec2(3.1, 7.7);
    a *= 0.5;
  }
  return v;
}
vec3 creator_6_grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
vec4 creator_6_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.013;
  vec2 flowV = vec2(t * 0.040, -t * 0.026) * (1.0 + 1.2 * f.flow);
  vec2 q = vec2(creator_6_fbm4(p * 1.35 + flowV + seed),
                creator_6_fbm4(p * 1.35 + vec2(4.7, 1.9) - flowV));
  vec2 w = p * (1.8 + 0.7 * f.detail) + 2.2 * q + seed;
  vec2 drift = vec2(t * 0.055, -t * 0.045);
  float e = 0.055;
  float h = creator_6_fbm4(w + drift);
  float hx = creator_6_fbm4(w + vec2(e, 0.0) + drift);
  float hy = creator_6_fbm4(w + vec2(0.0, e) + drift);
  float gain = 7.0;
  vec3 n = normalize(vec3((h - hx) * gain, (h - hy) * gain, 1.0));
  vec3 L = normalize(vec3(-0.42, 0.58, 0.70));
  float diff = clamp(dot(n, L), 0.0, 1.0);
  vec3 V = vec3(0.0, 0.0, 1.0);
  vec3 Rv = reflect(-L, n);
  float spec = pow(clamp(dot(Rv, V), 0.0, 1.0), 34.0);
  float bands = 0.5 + 0.5 * sin(h * (7.5 + 2.0 * f.detail) + t * 0.32 + seed);
  float sheen = pow(diff, 2.2);
  vec3 col = mix(f.color0.rgb * 1.35, f.color1.rgb, diff * 0.75 + bands * 0.18);
  col = mix(col, f.color2.rgb, sheen * (0.52 + 0.30 * f.bass));
  float glintN = creator_6_vnoise(p * (80.0 + 50.0 * f.detail) + vec2(0.0, t * 0.55) + seed);
  float glint = pow(clamp(glintN * 1.30 - 0.42, 0.0, 1.0), 7.0);
  col += f.color3.rgb * (glint * (0.30 + 1.30 * f.spark) * (0.30 + sheen) + spec * (0.38 + 0.55 * f.spark));
  col *= 0.94 + 0.14 * f.energy + 0.18 * f.pulse;
  col = creator_6_grade(col * f.intensity);
  col += (creator_6_hash13(uv * f.size + seed) - 0.5) * 0.007;
  float vig = clamp(1.12 - dot(p, p) * 0.42, 0.45, 1.02);
  return vec4(col * vig, 1.0);
}

float creator_7_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
vec2 creator_7_hash23(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.zyx + 31.32);
  return fract(vec2((q.x + q.y) * q.z, (q.x + q.z) * q.y));
}
float creator_7_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0);
  float a = creator_7_hash13(i);
  float b = creator_7_hash13(i + vec2(1.0, 0.0));
  float c = creator_7_hash13(i + vec2(0.0, 1.0));
  float d = creator_7_hash13(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float creator_7_fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * creator_7_vnoise(p);
    p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.02 + vec2(3.1, 7.7);
    a *= 0.5;
  }
  return v;
}
vec3 creator_7_grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
vec4 creator_7_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.011;
  float px = 1.0 / max(f.size.y, 1.0);
  float horizon = 0.46;
  float drive = 0.88 + 0.34 * f.energy + 0.26 * f.pulse;
  float skyMask = smoothstep(1.0, horizon, uv.y);
  vec3 col = mix(f.color0.rgb * 0.16, f.color0.rgb, skyMask);
  col += f.color2.rgb * pow(skyMask, 3.2) * 0.10 * f.glow;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (13.0 + k * 11.0) + vec2(seed * 3.1 + k * 7.3, k * 5.9);
    vec2 cell = floor(gp);
    vec2 h = creator_7_hash23(cell + k * 17.0);
    float on = step(0.955 - 0.02 * k, h.x);
    vec2 pos = cell + 0.25 + 0.5 * h;
    float tw = 0.55 + 0.45 * sin(t * (0.9 + 1.8 * h.y) + h.x * 6.2831853);
    vec2 dd = gp - pos;
    float d = sqrt(dot(dd, dd));
    float r0 = 0.026 + 0.020 * h.y;
    float core = 1.0 - smoothstep(r0 - px * 1.5, r0 + px * 1.5, d);
    col += vec3(0.82, 0.87, 1.0) * core * on * tw * (0.22 + 0.14 * k) * (0.35 + 0.85 * f.spark);
  }
  vec2 sp = vec2(p.x * 1.06, uv.y - (horizon - 0.115));
  float sd = length(sp) - 0.185;
  float disc = 1.0 - smoothstep(-px * 1.2, px * 1.2, sd);
  float stripes = fract(sp.y * 22.0 - t * 0.05 + seed);
  float band = smoothstep(0.02, -0.05, sp.y);
  float gap = mix(1.0, smoothstep(0.30, 0.55, stripes), band);
  disc *= gap;
  vec3 sun = mix(f.color1.rgb, f.color3.rgb, smoothstep(0.20, -0.17, sp.y));
  float halo = exp(-max(sd, 0.0) * 11.0) * 0.30 * f.glow;
  col += sun * disc * (0.95 + 0.30 * f.bass) * drive;
  col += sun * halo;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    float scale = 2.6 + k * 2.4;
    float ridge = creator_7_fbm4(vec2(p.x * scale + seed * 3.0 + k * 11.0, k * 4.7));
    float skyline = horizon - 0.006 - ridge * 0.040 * (1.0 - 0.45 * k);
    float m = smoothstep(skyline - px * 1.6, skyline + px * 1.6, uv.y);
    vec3 mCol = mix(f.color0.rgb * 0.50, f.color0.rgb * 0.28, k);
    mCol += sun * exp(-abs(uv.y - skyline) * 90.0) * 0.10 * (1.0 - k * 0.5);
    col = mix(col, mCol, m);
  }
  float ground = smoothstep(horizon - px, horizon + px, uv.y);
  float gz = max(uv.y - horizon, 0.0016);
  float persp = 0.60 / gz;
  vec3 groundCol = f.color0.rgb * 0.40;
  float rowCoord = persp * 0.80 + t * (1.0 + 1.1 * f.flow) + seed * 2.0;
  float rowFr = abs(fract(rowCoord) - 0.5);
  float rowPix = 0.80 * 0.60 / max(gz * gz * f.size.y, 1.0);
  float rowLine = exp(-rowFr * rowFr / max(2.2 * rowPix * rowPix, 0.000001));
  float vx = p.x * persp * 1.30;
  float vFr = abs(fract(vx + 0.5) - 0.5);
  float vPix = 1.30 * 0.60 / max(gz * f.size.x, 1.0);
  float vLine = exp(-vFr * vFr / max(2.2 * vPix * vPix, 0.000001));
  float gridFade = smoothstep(0.0, 0.04, gz) * (0.30 + 0.70 * smoothstep(horizon, 0.92, uv.y));
  vec3 gridCol = mix(f.color3.rgb, f.color1.rgb, 0.30 + 0.30 * smoothstep(horizon, 1.0, uv.y));
  float grid = (rowLine * 1.15 + vLine * 0.95) * gridFade * (0.50 + 0.50 * f.bass) * (0.48 + 0.62 * f.glow);
  col = mix(col, groundCol + gridCol * grid * drive, ground);
  float hb = (uv.y - horizon) * 30.0;
  col += gridCol * exp(-hb * hb) * 0.16 * (0.5 + 0.5 * f.glow);
  col = creator_7_grade(col * f.intensity);
  col += (creator_7_hash13(uv * f.size + seed) - 0.5) * 0.007;
  float vig = clamp(1.05 - dot(p, p) * 0.24, 0.45, 1.0);
  return vec4(col * vig, 1.0);
}

float creator_8_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
vec2 creator_8_hash23(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.zyx + 31.32);
  return fract(vec2((q.x + q.y) * q.z, (q.x + q.z) * q.y));
}
vec4 creator_8_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.013;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 acc = vec3(0.0);
  float aAcc = 0.0;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    float cols = (13.0 + k * 21.0) * f.detail;
    float cx = p.x * cols + k * 23.7 + seed * 5.0;
    float ci = floor(cx);
    float fx = fract(cx) - 0.5;
    vec2 h = creator_8_hash23(vec2(ci, k * 47.0 + seed));
    float spd = 0.40 + 0.42 * h.y + 0.26 * f.flow + 0.20 * f.bass;
    float len = (0.10 + 0.12 * h.x) * (1.0 + k * 0.45);
    float head = fract(h.x * 11.3 + t * spd);
    float rel = uv.y - head;
    float inTrail = smoothstep(-len - 0.012, -len + 0.03, rel) * (1.0 - smoothstep(-0.015, 0.004, rel));
    float sigCell = max(0.20 - 0.05 * k, px * cols * 1.4);
    float lat = exp(-fx * fx / max(sigCell * sigCell, 0.0001));
    float along = clamp(-rel / max(len, 0.001), 0.0, 1.0);
    float fade = 1.0 - 0.72 * along;
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.y);
    tint = mix(tint, f.color3.rgb, 0.28 + 0.22 * h.x);
    float a = inTrail * lat * fade * (0.62 - 0.16 * k) * (0.6 + 0.6 * f.spark + 0.3 * f.energy);
    float hx2 = fx * fx * 420.0;
    float hy2 = rel * rel * 800.0;
    a += exp(-(hx2 + hy2)) * 0.36 * (0.7 + 0.6 * f.spark);
    acc += tint * a;
    aAcc += a;
  }
  for (int j = 0; j < 2; j++) {
    float k = float(j);
    vec2 gp = vec2(p.x, uv.y) * 4.2 + vec2(seed * 3.0 + k * 11.0, -t * 0.05 - k * 0.02);
    vec2 cell = floor(gp);
    vec2 h = creator_8_hash23(cell + k * 29.0 + seed);
    float on = step(0.42, h.x);
    vec2 pos = cell + 0.25 + 0.50 * h;
    vec2 dd = gp - pos;
    float d2 = dot(dd, dd);
    float bob = 0.5 + 0.5 * sin(t * (0.3 + 0.4 * h.y) + h.x * 6.2831853);
    float g = exp(-d2 * (24.0 - k * 7.0));
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.y);
    float a = on * g * bob * (0.14 - 0.05 * k) * (0.7 + 0.5 * f.glow);
    acc += tint * a;
    aAcc += a;
  }
  return vec4(acc * f.intensity, clamp(aAcc * (0.62 + 0.38 * f.glow), 0.0, 0.90));
}

float creator_9_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
float creator_9_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0);
  float a = creator_9_hash13(i);
  float b = creator_9_hash13(i + vec2(1.0, 0.0));
  float c = creator_9_hash13(i + vec2(0.0, 1.0));
  float d = creator_9_hash13(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
vec3 creator_9_grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
vec4 creator_9_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed * 0.75;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.017;
  vec2 q = p * (2.4 + 1.3 * f.detail) + seed;
  float ca = 0.0;
  vec2 wv = vec2(0.0);
  for (int i = 0; i < 3; i++) {
    float k = float(i) + 1.0;
    wv = vec2(sin(q.y * 5.7 * k + t * (0.50 + 0.20 * k) + wv.x * 1.2 + seed),
              sin(q.x * 5.0 * k - t * (0.42 + 0.18 * k) + wv.y * 1.2));
    ca += 0.5 + 0.5 * sin(q.x * (3.1 + 1.6 * k) + wv.x * 2.2 + t * 0.6 * k)
              * sin(q.y * (4.1 - 0.8 * k) + wv.y * 2.0 - t * 0.5 * k);
  }
  ca /= 3.0;
  float fine = 0.5 + 0.5 * sin(q.x * 17.0 + sin(q.y * 13.0 - t * 0.8) + t * 0.9);
  float fil = pow(clamp(ca * 1.42 - 0.26, 0.0, 1.0), 5.2);
  fil += pow(clamp(ca * fine * 1.9 - 0.55, 0.0, 1.0), 4.0) * 0.45;
  float depth = smoothstep(0.0, 1.0, uv.y);
  vec3 col = mix(f.color1.rgb * 0.80, f.color0.rgb, depth);
  col += f.color2.rgb * fil * (0.22 + 0.55 * exp(-uv.y * 2.4));
  col += f.color1.rgb * pow(clamp(ca, 0.0, 1.0), 2.2) * 0.10 * (0.4 + 0.6 * (1.0 - depth));
  float bend = creator_9_vnoise(vec2(p.x * 1.7 - t * 0.10, uv.y * 1.3)) * 2.0;
  float rays = pow(clamp(0.5 + 0.5 * sin(p.x * (5.0 + 2.0 * f.detail) + bend + t * 0.15 + seed), 0.0, 1.0), 4.5);
  col += mix(f.color2.rgb, f.color3.rgb, 0.4) * rays * exp(-uv.y * 2.9) * 0.15 * (0.4 + 0.6 * f.glow);
  float glintN = creator_9_vnoise(p * (60.0 + 40.0 * f.detail) + vec2(t * 0.20, -t * 0.14) + seed);
  float glint = pow(clamp(glintN * 1.35 - 0.48, 0.0, 1.0), 8.0);
  col += f.color3.rgb * glint * exp(-uv.y * 3.4) * 0.20 * (0.5 + 0.5 * f.glow);
  col = creator_9_grade(col * f.intensity);
  col += (creator_9_hash13(uv * f.size + seed) - 0.5) * 0.007;
  float vig = clamp(1.10 - dot(p, p) * 0.38, 0.45, 1.0);
  return vec4(col * vig, 1.0);
}

float creator_10_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
vec4 creator_10_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float r = length(p) + 0.0001;
  vec2 dir = p / r;
  float ang = acos(clamp(dir.x, -1.0, 1.0));
  if (dir.y < 0.0) {
    ang = 6.2831853 - ang;
  }
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.017;
  float px = 1.0 / max(f.size.y, 1.0);
  float base = 0.30 + 0.005 * sin(t * 0.55 + seed) + 0.014 * f.bass + 0.020 * f.pulse;
  float disp = 0.0032 + 0.0016 * f.body + px * 0.6;
  float sig = 0.0034 + px * 0.9;
  float shimmer = 0.74 + 0.16 * sin(ang * 5.0 + t * 0.7 + seed)
                + 0.10 * sin(ang * 9.0 - t * 1.1 + seed * 2.0);
  shimmer = clamp(shimmer + 0.25 * f.spark, 0.0, 1.15);
  float dR = abs(r - base - disp);
  float dG = abs(r - base);
  float dB = abs(r - base + disp);
  float coreR = exp(-dR * dR / (2.0 * sig * sig));
  float coreG = exp(-dG * dG / (2.0 * sig * sig));
  float coreB = exp(-dB * dB / (2.0 * sig * sig));
  vec3 ink = vec3(1.0, 0.36, 0.50) * coreR
           + vec3(0.46, 1.0, 0.64) * coreG
           + vec3(0.40, 0.72, 1.0) * coreB;
  ink *= 0.32 * shimmer;
  float bloom = exp(-abs(r - base) * 30.0) * 0.16 * f.glow * shimmer;
  vec3 tint = mix(f.color1.rgb, f.color2.rgb, 0.5 + 0.5 * sin(ang * 2.0 + t * 0.4));
  vec3 col = ink + tint * bloom;
  float alpha = clamp(dot(vec3(coreR, coreG, coreB), vec3(0.36)) * shimmer + bloom * 1.6, 0.0, 1.0);
  alpha *= f.intensity * (0.9 + 0.2 * f.pulse);
  return vec4(col * f.intensity, clamp(alpha, 0.0, 0.92));
}

float creator_11_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
vec2 creator_11_hash23(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.zyx + 31.32);
  return fract(vec2((q.x + q.y) * q.z, (q.x + q.z) * q.y));
}
float creator_11_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0);
  float a = creator_11_hash13(i);
  float b = creator_11_hash13(i + vec2(1.0, 0.0));
  float c = creator_11_hash13(i + vec2(0.0, 1.0));
  float d = creator_11_hash13(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float creator_11_fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * creator_11_vnoise(p);
    p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.02 + vec2(3.1, 7.7);
    a *= 0.5;
  }
  return v;
}
vec3 creator_11_grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
mat2 creator_11_rot2o(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat2(c, -s, s, c);
}
vec4 creator_11_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.011;
  float px = 1.0 / max(f.size.y, 1.0);
  vec3 col = mix(vec3(0.006, 0.008, 0.018), vec3(0.014, 0.020, 0.042), smoothstep(0.0, 1.0, uv.y));
  col += f.color1.rgb * creator_11_fbm4(p * 1.7 + vec2(seed, -t * 0.006)) * 0.040;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (17.0 + k * 15.0) + vec2(seed * 7.0 + k * 29.0, k * 13.0);
    vec2 cell = floor(gp);
    vec2 h = creator_11_hash23(cell + k * 5.0);
    float on = step(0.962 - 0.020 * k, h.x);
    vec2 pos = cell + 0.25 + 0.5 * h;
    float tw = 0.65 + 0.35 * sin(t * (0.4 + 1.2 * h.y) + h.x * 6.2831853);
    vec2 dd = gp - pos;
    float d = sqrt(dot(dd, dd));
    float r0 = 0.028 + 0.022 * h.y;
    float core = 1.0 - smoothstep(r0 - px * 1.5, r0 + px * 1.5, d);
    col += vec3(0.78, 0.85, 1.0) * (core * on * tw * 0.22);
  }
  float breathe = 0.90 + 0.10 * sin(t * 0.5 + seed);
  float d0 = length(p);
  float star = exp(-d0 * d0 * 300.0);
  float core0 = 1.0 - smoothstep(0.014 - px, 0.014 + px, d0);
  col += mix(f.color2.rgb, vec3(1.0), 0.60) * (star * 0.26 + core0 * 0.85) * breathe;
  col += f.color2.rgb * exp(-d0 * 5.0) * 0.05;
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    vec2 h = creator_11_hash23(vec2(k * 3.1 + seed, k * 7.7 + 2.0));
    float R = 0.155 + 0.070 * (k + 0.15 * h.x);
    float tiltY = 0.60 + 0.12 * h.x;
    float rotA = (h.y - 0.5) * 0.9;
    float dirS = mix(1.0, -1.0, step(0.5, fract(h.x * 7.3)));
    float spd = (0.10 + 0.04 * k) * (1.0 + 0.18 * h.y) * dirS;
    float ang = h.y * 6.2831853 + t * spd;
    vec2 q = creator_11_rot2o(-rotA) * p;
    vec2 e = vec2(q.x, q.y / tiltY);
    float de = abs(length(e) - R);
    float lineA = 1.0 - smoothstep(px * 0.6, px * 2.0, de);
    col += f.color1.rgb * lineA * 0.055 * (0.75 + 0.25 * sin(t * 0.3 + k * 2.0));
    vec2 local = vec2(cos(ang) * R, sin(ang) * R * tiltY);
    vec2 cpos = creator_11_rot2o(rotA) * local;
    vec2 rel = p - cpos;
    float db = length(rel);
    float body = 1.0 - smoothstep(0.0092 - px, 0.0092 + px, db);
    float glowB = exp(-db * 55.0);
    vec3 ink = mix(f.color2.rgb, f.color3.rgb, k * 0.5);
    col += ink * (body * 0.95 + glowB * 0.26);
    vec2 tangent = creator_11_rot2o(rotA) * normalize(vec2(-sin(ang) * R, cos(ang) * R * tiltY));
    float behind = -dot(rel, tangent);
    float side = dot(rel, vec2(-tangent.y, tangent.x));
    float trail = exp(-max(behind, 0.0) * 95.0) * exp(-side * side * 5200.0);
    col += ink * trail * 0.20;
  }
  col = creator_11_grade(col * f.intensity);
  col += (creator_11_hash13(uv * f.size + seed) - 0.5) * 0.006;
  float vig = clamp(1.05 - dot(p, p) * 0.18, 0.6, 1.0);
  return vec4(col * vig, 1.0);
}

float creator_12_hash13(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
  q += dot(q, q.zyx + 31.32);
  return fract((q.x + q.y) * q.z);
}
vec2 creator_12_hash23(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.zyx + 31.32);
  return fract(vec2((q.x + q.y) * q.z, (q.x + q.z) * q.y));
}
vec3 creator_12_grade(vec3 c) {
  c = max(c, vec3(0.0));
  c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
  return clamp(c, 0.0, 1.0);
}
float creator_12_barLevel(float ai, float n, float seed, float t, float bass, float body, float spark, float flow) {
  vec2 h = creator_12_hash23(vec2(ai, seed * 0.37));
  float wB = 0.5 + 0.5 * sin((ai / n) * 12.56637 + t * 0.5);
  float wM = 0.5 + 0.5 * cos((ai / n) * 18.84956 - t * 0.37);
  float wH = 0.5 + 0.5 * sin((ai / n) * 31.41593 + t * 0.61);
  float wsum = max(wB + wM + wH, 0.35);
  float spec = (bass * wB + body * wM + spark * wH) / wsum;
  float wave = 0.5 + 0.5 * sin(t * 0.9 + ai * 1.7 + h.y * 6.2831853);
  return clamp(0.10 + wave * 0.06 + spec * 0.55 + 0.08 * flow * sin(t * 1.3 + h.x * 6.2831853), 0.05, 1.0);
}
vec4 creator_12_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float r = length(p) + 0.0001;
  float ang = acos(clamp(p.x / r, -1.0, 1.0));
  if (p.y < 0.0) {
    ang = 6.2831853 - ang;
  }
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0);
  float px = 1.0 / max(f.size.y, 1.0);
  float n = floor(44.0 + 36.0 * f.detail);
  float ac = ang / 6.2831853 * n;
  float ai = floor(ac);
  float af = fract(ac);
  float kick = exp(-f.phase * 3.2);
  float lv = 0.0;
  float wsum = 0.0;
  for (int j = 0; j < 5; j++) {
    float o = float(j) - 2.0;
    float wgt = exp(-o * o * 0.5);
    lv += wgt * creator_12_barLevel(ai + o, n, seed, t, f.bass, f.body, f.spark, f.flow);
    wsum += wgt;
  }
  lv /= wsum;
  float r0 = 0.150;
  float len = lv * 0.24 + 0.012;
  float halfW = 0.34;
  float barWin = smoothstep(0.02, 0.18, af) * (1.0 - smoothstep(0.82, 0.98, af));
  float rr = r - r0;
  float cap = len + px;
  float tipA = 1.0 - smoothstep(cap - px * 2.0, cap + px * 0.5, rr);
  float baseA = smoothstep(-0.010 - px, -0.010 + px, rr);
  float bar = barWin * baseA * tipA;
  float tipGlow = exp(-max(rr - len, 0.0) * 34.0) * barWin * (0.10 + 0.26 * lv);
  vec3 barCol = mix(f.color1.rgb, f.color2.rgb, clamp(lv * 1.35, 0.0, 1.0));
  barCol = mix(barCol, f.color3.rgb, pow(clamp(lv * 1.5 - 0.70, 0.0, 1.0), 1.5));
  vec3 col = mix(f.color0.rgb * 0.90, f.color0.rgb * 0.42, smoothstep(0.0, 0.55, r));
  col += barCol * bar * (0.55 + 0.55 * f.energy + 0.28 * kick * f.bass);
  col += barCol * tipGlow * f.glow;
  float rd = r - r0;
  col += f.color1.rgb * exp(-rd * rd * 5200.0) * 0.16 * (0.5 + 0.5 * f.glow);
  col += f.color2.rgb * exp(-r * 7.0) * (0.08 + 0.22 * f.bass * kick);
  float rippleR = r0 + 0.015 + f.phase * 0.30;
  float ripple = exp(-abs(r - rippleR) * 55.0) * (1.0 - f.phase) * kick;
  col += f.color2.rgb * ripple * 0.18;
  col = creator_12_grade(col * f.intensity);
  col += (creator_12_hash13(uv * f.size + seed) - 0.5) * 0.005;
  float vig = clamp(1.08 - dot(p, p) * 0.28, 0.45, 1.0);
  return vec4(col * vig, 1.0);
}

void main() {
  CreatorFrame f;
  f.size=uSize; f.time=uTime; f.seedLow=uSeedLow; f.seedHigh=uSeedHigh;
  f.energy=uEnergy; f.bass=uBass; f.body=uBody; f.spark=uSpark;
  f.flow=uFlow; f.pulse=uPulse; f.phase=uPhase; f.bpm=uBpm;
  f.intensity=uIntensity; f.speed=uSpeed; f.detail=uDetail; f.glow=uGlow;
  f.color0=uColor0; f.color1=uColor1; f.color2=uColor2; f.color3=uColor3;
  vec2 uv=FlutterFragCoord().xy / max(f.size,vec2(1.0));
  vec4 color=vec4(0.0);
  if (abs(uVisualIndex - 0.0) < 0.5) color=creator_0_paintVisual(uv,f);
  else if (abs(uVisualIndex - 1.0) < 0.5) color=creator_1_paintVisual(uv,f);
  else if (abs(uVisualIndex - 2.0) < 0.5) color=creator_2_paintVisual(uv,f);
  else if (abs(uVisualIndex - 3.0) < 0.5) color=creator_3_paintVisual(uv,f);
  else if (abs(uVisualIndex - 4.0) < 0.5) color=creator_4_paintVisual(uv,f);
  else if (abs(uVisualIndex - 5.0) < 0.5) color=creator_5_paintVisual(uv,f);
  else if (abs(uVisualIndex - 6.0) < 0.5) color=creator_6_paintVisual(uv,f);
  else if (abs(uVisualIndex - 7.0) < 0.5) color=creator_7_paintVisual(uv,f);
  else if (abs(uVisualIndex - 8.0) < 0.5) color=creator_8_paintVisual(uv,f);
  else if (abs(uVisualIndex - 9.0) < 0.5) color=creator_9_paintVisual(uv,f);
  else if (abs(uVisualIndex - 10.0) < 0.5) color=creator_10_paintVisual(uv,f);
  else if (abs(uVisualIndex - 11.0) < 0.5) color=creator_11_paintVisual(uv,f);
  else if (abs(uVisualIndex - 12.0) < 0.5) color=creator_12_paintVisual(uv,f);
  if (any(isnan(color)) || any(isinf(color))) color=vec4(0.0);
  color=clamp(color,0.0,1.0);
  fragColor=vec4(color.rgb*color.a,color.a);
}
