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
vec4 creator_0_paintVisual(vec2 uv, CreatorFrame f) {
vec2 p = uv - 0.5;
p.x *= f.size.x / max(f.size.y, 1.0);
float t = f.time * f.speed * 0.32;
float seed = mod(f.seedLow + f.seedHigh, 10000.0) * 0.001;
vec3 c = f.color0.rgb * (0.7 + 0.3 * uv.y);
for (int i = 0; i < 4; i++) {
  float k = float(i);
  float center = 0.14 * sin(p.x * (2.0 + k * 0.32) + t + seed + k)
               + 0.08 * cos(p.x * 5.0 * f.detail - t * 0.6 + k)
               + (k - 1.5) * 0.105;
  float d = abs(p.y - center);
  float width = 0.014 + 0.013 * f.bass;
  float core = exp(-d * d / (width * width));
  float halo = exp(-d * 12.0) * 0.13 * f.glow;
  vec3 ink = mix(f.color1.rgb, f.color2.rgb, k / 3.0);
  ink = mix(ink, f.color3.rgb, 0.15 * (0.5 + 0.5 * sin(t + p.x * 2.0 + k)));
  c += ink * (core * 0.30 + halo) * f.intensity * (0.75 + 0.3 * f.energy + 0.15 * f.pulse);
}
float vignette = clamp(1.0 - dot(p, p) * 0.65, 0.25, 1.0);
return vec4(c * vignette, 1.0);
}

vec2 creator_1_hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
mat2 creator_1_rot2(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat2(c, -s, s, c);
}
vec4 creator_1_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0);
  vec3 acc = vec3(0.0);
  float aAcc = 0.0;
  for (int i = 0; i < 5; i++) {
    float k = float(i);
    vec2 h = creator_1_hash22(vec2(k * 7.7 + seed * 0.11, k * 3.3 + 1.0));
    float orbR = 0.10 + 0.15 * h.y;
    float orbA = t * (0.08 + 0.07 * h.x) * (1.0 + 0.6 * f.flow) + h.x * 6.2831853;
    float orbB = t * (0.06 + 0.05 * h.y) + h.y * 6.2831853;
    vec2 c = vec2(cos(orbA) * orbR * min(aspect * 1.05, 1.3), sin(orbB) * orbR * 0.85);
    float spin = t * (0.30 + 0.45 * h.y) * (1.0 + 0.4 * f.flow) + h.x * 6.2831853 + k;
    vec2 lp = creator_1_rot2(spin) * (p - c);
    float s = (0.05 + 0.055 * h.x) * (1.0 + 0.18 * f.bass);
    float shape = 0.9 + 0.18 * sin(k * 2.1 + t * 0.35 + seed);
    float d = (abs(lp.x) * 0.60 + abs(lp.y) * 1.0) / shape - s;
    d *= 0.85;
    float fill = smoothstep(0.004, -0.004, d);
    float facet = 0.5 + 0.5 * sin(lp.x * (40.0 + 14.0 * h.y) + lp.y * 26.0 + k * 3.1 + t * 0.10);
    vec2 nl = lp / max(length(lp), 0.0001);
    float sheen = pow(clamp(0.5 + 0.5 * dot(vec2(0.55, 0.83), nl), 0.0, 1.0), 3.0);
    float eR = exp(-abs(d + 0.005) * 150.0);
    float eG = exp(-abs(d) * 160.0);
    float eB = exp(-abs(d - 0.005) * 150.0);
    float kick = 0.55 + 0.30 * f.pulse + 0.15 * f.bass;
    acc += vec3(1.0, 0.30, 0.52) * eR * 0.38 * kick;
    acc += vec3(1.0) * eG * 0.55 * kick * (0.7 + 0.6 * facet);
    acc += vec3(0.32, 0.78, 1.0) * eB * 0.38 * kick;
    vec3 glass = mix(f.color1.rgb, f.color2.rgb, facet);
    glass = mix(glass, f.color3.rgb, sheen * 0.55);
    acc += glass * fill * (0.10 + 0.20 * sheen + 0.06 * facet);
    aAcc += fill * (0.13 + 0.20 * sheen + 0.05 * facet) * (0.75 + 0.5 * f.glow);
    aAcc += (eR + eG + eB) * 0.42 * kick;
    float ty = s * shape * 1.12;
    float tdx = lp.x;
    float tdy = abs(lp.y) - ty;
    float td2 = tdx * tdx + tdy * tdy;
    float glint = exp(-td2 * 5200.0) * (0.25 + 0.75 * f.spark);
    acc += vec3(1.0, 0.95, 0.85) * glint * 0.5;
    aAcc += glint * 0.30;
  }
  return vec4(acc * f.intensity, clamp(aAcc * (0.55 + 0.45 * f.glow), 0.0, 0.9));
}

float creator_2_hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
vec2 creator_2_hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
float creator_2_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * (3.0 - 2.0 * u);
  return mix(mix(creator_2_hash12(i), creator_2_hash12(i + vec2(1.0, 0.0)), u.x),
             mix(creator_2_hash12(i + vec2(0.0, 1.0)), creator_2_hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float creator_2_fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * creator_2_vnoise(p);
    p = p * 2.03 + vec2(11.7, 5.3);
    a *= 0.5;
  }
  return v;
}
vec4 creator_2_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.017;
  vec3 col = mix(f.color0.rgb * 0.5, f.color0.rgb * 1.25, smoothstep(0.0, 1.0, uv.y));
  vec2 w = vec2(t * 0.012 + seed, -t * 0.009) * (1.0 + f.flow * 0.8);
  float n1 = creator_2_fbm4(p * 2.4 + w + seed);
  float n2 = creator_2_fbm4(p * 3.2 - w * 1.3 + 1.8 * n1 + 4.7);
  float neb1 = pow(clamp(n1 * 1.65 - 0.42, 0.0, 1.0), 1.7);
  float neb2 = pow(clamp(n2 * 1.5 - 0.45, 0.0, 1.0), 2.0);
  col += f.color1.rgb * neb1 * (0.36 + 0.38 * f.bass);
  col += f.color2.rgb * neb2 * (0.30 + 0.30 * f.body);
  float dust = pow(clamp(creator_2_fbm4(p * 4.6 + n2 * 1.5 - w + 9.1), 0.0, 1.0), 2.2);
  col *= 1.0 - 0.38 * dust;
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (10.0 + k * 10.0) + vec2(seed * 2.3 + k * 9.7, k * 4.3)
            - vec2(0.0, t * (0.035 + 0.02 * k));
    vec2 cell = floor(gp);
    vec2 h = creator_2_hash22(cell + k * 23.0);
    float on = step(0.88 - 0.04 * k, h.x);
    vec2 pos = cell + 0.30 + 0.40 * h;
    vec2 dd = gp - pos;
    float d2 = dot(dd, dd);
    float tw = 0.5 + 0.5 * sin(t * (1.0 + 2.6 * h.y) + h.x * 6.2831853);
    float star = on * exp(-d2 * 620.0) * tw * (0.40 + 0.90 * f.spark);
    col += vec3(0.82, 0.88, 1.0) * star * 0.52 * (0.6 + 0.6 * f.glow);
  }
  float ct = floor(t / 9.0 + seed);
  float cx2 = fract(t / 9.0 + seed);
  vec2 sh = creator_2_hash22(vec2(ct * 3.7, ct * 1.9) + seed);
  vec2 head = vec2(mix(-0.25, 0.60, sh.x) + cx2 * mix(0.70, 1.00, sh.y),
                   mix(0.02, 0.35, sh.y) + cx2 * mix(0.25, 0.55, sh.x));
  float life = smoothstep(0.0, 0.10, cx2) * smoothstep(0.50, 0.22, cx2);
  vec2 q2 = vec2(p.x, uv.y) - head;
  float along = dot(q2, vec2(0.82, 0.57));
  float perp2 = dot(q2, vec2(-0.57, 0.82));
  float tail = exp(-max(-along, 0.0) * 14.0) * 0.5 + exp(-max(along, 0.0) * 55.0);
  float shoot = life * exp(-perp2 * perp2 * 2600.0) * tail;
  col += vec3(1.0) * clamp(shoot, 0.0, 1.0) * 0.8;
  float vig = clamp(1.05 - dot(p, p) * 0.35, 0.45, 1.0);
  return vec4(col * vig * f.intensity, 1.0);
}

float creator_3_hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
vec2 creator_3_hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
float creator_3_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * (3.0 - 2.0 * u);
  return mix(mix(creator_3_hash12(i), creator_3_hash12(i + vec2(1.0, 0.0)), u.x),
             mix(creator_3_hash12(i + vec2(0.0, 1.0)), creator_3_hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float creator_3_fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * creator_3_vnoise(p);
    p = p * 2.03 + vec2(11.7, 5.3);
    a *= 0.5;
  }
  return v;
}
vec4 creator_3_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.019;
  float rise = t * (0.9 + 1.0 * f.flow) + seed;
  float n = creator_3_fbm4(vec2(p.x * (5.5 * f.detail) + seed, uv.y * 3.2 - rise));
  n = pow(clamp(n * 1.55 - 0.08, 0.0, 1.0), 1.9);
  float lift = uv.y / (0.34 + 0.15 * f.bass);
  float heat = clamp(n * 1.85 - lift * 1.05 + 0.30, 0.0, 1.25);
  heat *= 0.50 + 0.50 * smoothstep(-0.03, 0.10, uv.y);
  vec3 fireCol = f.color1.rgb;
  fireCol = mix(fireCol, f.color2.rgb, clamp(heat * 1.55, 0.0, 1.0));
  fireCol = mix(fireCol, f.color3.rgb, pow(clamp(heat * 1.5 - 0.85, 0.0, 1.0), 1.6));
  vec3 col = mix(f.color0.rgb * 0.55, f.color0.rgb * 0.25, smoothstep(0.25, 1.0, uv.y));
  col += fireCol * heat * (0.85 + 0.40 * f.energy + 0.30 * f.pulse);
  float bed = exp(-(1.0 - uv.y) * 5.5);
  float bedNoise = creator_3_fbm4(vec2(p.x * (5.0 * f.detail) + seed, rise * 1.2));
  col += mix(f.color1.rgb, f.color2.rgb, bedNoise) * bed * (0.30 + 0.30 * f.bass) * (0.55 + 0.45 * bedNoise);
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    float cols = 6.0 + k * 5.0;
    vec2 gp = vec2(p.x * cols + seed * 7.0 + k * 19.0,
                   (uv.y + t * (0.10 + 0.08 * k) * (1.0 + 0.5 * f.flow)) * (cols * 0.62));
    gp.x += 0.5 * sin(t * 0.5 + k * 2.0 + uv.y * 4.0);
    vec2 cell = floor(gp);
    vec2 h = creator_3_hash22(cell + k * 41.0);
    float on = step(0.30, h.y);
    vec2 pos = cell + 0.25 + 0.50 * h;
    vec2 dd = gp - pos;
    float d2 = dot(dd, dd);
    float flick = pow(0.5 + 0.5 * sin(t * (2.0 + 3.0 * h.x) + h.y * 6.2831853), 2.0);
    float ember = on * exp(-d2 * (700.0 - k * 140.0)) * flick * (0.45 + 1.25 * f.spark);
    vec3 emberCol = mix(f.color3.rgb, f.color2.rgb, smoothstep(1.0, 0.30, uv.y));
    col += emberCol * ember * 0.75 * (0.7 + 0.5 * f.bass);
  }
  float vig = clamp(1.10 - dot(p, p) * 0.40, 0.40, 1.0);
  return vec4(col * vig * f.intensity, 1.0);
}

float creator_4_hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
vec2 creator_4_hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
vec4 creator_4_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.011;
  vec3 acc = vec3(0.0);
  float aAcc = 0.0;
  for (int i = 0; i < 4; i++) {
    float k = float(i);
    float scale = 4.5 + k * 3.5;
    vec2 gp = vec2(p.x, uv.y) * scale;
    gp.y += t * (0.10 + 0.06 * k) * (1.0 + 0.7 * f.flow);
    gp.x += seed + 0.4 * sin(t * 0.20 + k * 2.3) + k * 13.7;
    vec2 cell = floor(gp);
    vec2 h = creator_4_hash22(cell + k * 31.0);
    float on = step(h.y, 0.72 - 0.06 * k);
    vec2 pos = cell + 0.25 + 0.50 * h;
    vec2 dv = gp - pos;
    float d2 = dot(dv, dv);
    float tw = 0.5 + 0.5 * sin(t * (0.7 + 2.4 * h.y) + h.x * 6.2831853);
    tw = pow(clamp(tw + 0.35 * f.spark - 0.18, 0.0, 1.0), 1.5 + 2.0 * h.x);
    float rad = (0.16 + 0.10 * h.x) * (1.0 + 0.25 * f.bass);
    float core = exp(-d2 / (rad * rad));
    float halo = exp(-sqrt(d2) * (9.0 + k * 3.0)) * 0.35;
    float fx = exp(-abs(dv.x) * 90.0) * exp(-abs(dv.y) * 12.0)
             + exp(-abs(dv.y) * 90.0) * exp(-abs(dv.x) * 12.0);
    float flare = fx * step(2.5, k) * 0.30;
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.x);
    tint = mix(tint, f.color3.rgb, pow(core, 3.0) * 0.7);
    float a = on * (core * (0.30 + 0.45 * tw) + halo * tw * (0.4 + 0.6 * f.glow) + flare * tw)
            * (0.34 - 0.05 * k) * f.intensity * (0.65 + 0.5 * f.bass + 0.45 * f.pulse * tw);
    acc += tint * a;
    aAcc += a;
  }
  return vec4(acc, clamp(aAcc * (0.55 + 0.45 * f.glow), 0.0, 0.80));
}

float creator_5_hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
vec2 creator_5_hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
float creator_5_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * (3.0 - 2.0 * u);
  return mix(mix(creator_5_hash12(i), creator_5_hash12(i + vec2(1.0, 0.0)), u.x),
             mix(creator_5_hash12(i + vec2(0.0, 1.0)), creator_5_hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float creator_5_fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * creator_5_vnoise(p);
    p = p * 2.03 + vec2(11.7, 5.3);
    a *= 0.5;
  }
  return v;
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
  float warp = t * 0.5 + seed + 0.30 * f.flow + 0.22 * f.bass;
  vec3 col = f.color0.rgb * (0.75 - 0.35 * clamp(r, 0.0, 1.0));
  float n = creator_5_fbm4(dir * 2.2 + vec2(seed, r * 3.0 - warp * 0.8));
  col += f.color2.rgb * pow(clamp(n * 1.4 - 0.45, 0.0, 1.0), 2.2) * 0.40;
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    float ci = 30.0 + k * 22.0;
    float ac = ang / 6.2831853 * ci;
    float ai = floor(ac);
    float af = fract(ac);
    vec2 h = creator_5_hash22(vec2(ai + k * 57.0, k * 13.7 + seed * 3.0));
    float dAng = abs(af - 0.5 - (h.x - 0.5) * 0.62);
    float z = fract(h.y * 7.31 + warp * (0.55 + 0.30 * k));
    float rr = 0.02 + 1.55 * z * z;
    float sw = 0.03 + 0.30 * z;
    float dr = (r - rr) / sw;
    float aw = 0.05 + 0.10 * z;
    float streak = exp(-dAng * dAng / (aw * aw)) * exp(-dr * dr);
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.x);
    tint = mix(tint, f.color3.rgb, z * z * 0.65);
    col += tint * streak * smoothstep(0.02, 0.20, z) * (0.35 + 0.65 * z)
         * (0.55 + 0.75 * f.energy + 0.30 * f.pulse);
  }
  col += f.color3.rgb * exp(-r * (7.5 - 2.4 * f.bass)) * (0.35 + 0.55 * f.bass + 0.35 * f.pulse);
  float vig = clamp(1.10 - dot(p, p) * 0.30, 0.35, 1.0);
  return vec4(col * vig * f.intensity, 1.0);
}

float creator_6_hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
vec2 creator_6_hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
float creator_6_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * (3.0 - 2.0 * u);
  return mix(mix(creator_6_hash12(i), creator_6_hash12(i + vec2(1.0, 0.0)), u.x),
             mix(creator_6_hash12(i + vec2(0.0, 1.0)), creator_6_hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float creator_6_fbm4(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * creator_6_vnoise(p);
    p = p * 2.03 + vec2(11.7, 5.3);
    a *= 0.5;
  }
  return v;
}
vec4 creator_6_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.013;
  vec2 drift = vec2(t * 0.045, -t * 0.030) * (1.0 + 1.6 * f.flow);
  vec2 q = vec2(creator_6_fbm4(p * 1.7 + drift + seed),
                creator_6_fbm4(p * 1.7 + vec2(5.2, 1.3) - drift + seed));
  float freq = 1.5 + 0.9 * f.detail;
  vec2 r = vec2(creator_6_fbm4(p * freq + 2.4 * q + vec2(1.7, 9.2) + vec2(t * 0.06, -t * 0.05)),
                creator_6_fbm4(p * freq + 2.4 * q + vec2(8.3, 2.8) + vec2(-t * 0.04, t * 0.055)));
  float ridge = creator_6_fbm4(p * (2.1 + f.detail * 0.4) + 3.0 * r + seed);
  float bands = 0.5 + 0.5 * sin((p.y * 3.4 + p.x * 1.2) * (0.8 + 0.6 * f.detail)
                + ridge * 7.0 + t * 0.4 + seed);
  float silk = pow(bands, 2.6);
  float sheen = pow(clamp(ridge * 1.5 - 0.42, 0.0, 1.0), 2.6);
  vec3 col = mix(f.color0.rgb, f.color0.rgb * 1.9, smoothstep(1.0, 0.0, uv.y));
  col = mix(col, f.color1.rgb, clamp(silk * 0.9, 0.0, 1.0));
  col = mix(col, f.color2.rgb, sheen * (0.50 + 0.35 * f.bass));
  float glintN = creator_6_vnoise(p * (70.0 + 60.0 * f.detail) + vec2(0.0, t * 0.6) + seed);
  float glint = pow(clamp(glintN * 1.25 - 0.28, 0.0, 1.0), 8.0);
  col += f.color3.rgb * glint * (0.25 + 1.4 * f.spark) * (0.35 + sheen);
  col *= 0.90 + 0.18 * f.energy + 0.22 * f.pulse;
  float vig = clamp(1.15 - dot(p, p) * 0.5, 0.4, 1.05);
  return vec4(col * vig * f.intensity, 1.0);
}

float creator_7_hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
vec2 creator_7_hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
vec4 creator_7_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.011;
  float drive = 0.85 + 0.40 * f.energy + 0.30 * f.pulse + 0.20 * f.bass;
  float horizon = 0.46;
  float skyMask = smoothstep(1.0, horizon, uv.y);
  vec3 sky = mix(f.color0.rgb * 0.22, f.color0.rgb, skyMask);
  sky += f.color2.rgb * pow(skyMask, 3.0) * 0.16 * f.glow;
  for (int i = 0; i < 2; i++) {
    float k = float(i);
    vec2 gp = vec2(p.x, uv.y) * (11.0 + k * 9.0) + vec2(seed * 3.1 + k * 7.3, k * 5.9);
    gp.y += t * (0.06 + 0.05 * k);
    vec2 cell = floor(gp);
    vec2 h = creator_7_hash22(cell + k * 17.0);
    float on = step(0.86 - 0.05 * k, h.x);
    vec2 pos = cell + 0.25 + 0.5 * h;
    vec2 dd = gp - pos;
    float d2 = dot(dd, dd);
    float tw = 0.45 + 0.55 * sin(t * (1.2 + 2.4 * h.y) + h.x * 6.2831853);
    float star = on * exp(-d2 * 700.0) * tw * (0.35 + 0.85 * f.spark);
    sky += vec3(0.85, 0.90, 1.0) * star * skyMask * 0.30;
  }
  vec2 sp = vec2(p.x * 1.06, uv.y - (horizon - 0.155));
  float sd = length(sp) - 0.245;
  float disc = smoothstep(0.010, -0.010, sd);
  float stripes = fract(sp.y * 21.0 - t * 0.05 + seed);
  float gap = mix(1.0, smoothstep(0.28, 0.52, stripes), smoothstep(-0.02, 0.16, sp.y));
  disc *= gap;
  vec3 sun = mix(f.color1.rgb, f.color2.rgb, smoothstep(-0.24, 0.24, sp.y));
  float halo = exp(-max(sd, 0.0) * 7.0) * 0.40 * f.glow;
  vec3 col = sky + sun * disc * (0.85 + 0.35 * f.bass) * drive + sun * halo;
  float ground = smoothstep(horizon - 0.0025, horizon + 0.0025, uv.y);
  float gz = max(uv.y - horizon, 0.0018);
  float persp = 0.62 / gz;
  vec3 groundCol = f.color0.rgb * 0.42;
  float rowCoord = persp * 0.85 + t * (1.1 + 1.2 * f.flow) + seed * 2.0;
  float rowFr = abs(fract(rowCoord) - 0.5);
  float rowPix = 0.85 * 0.62 / max(gz * gz * f.size.y, 1.0);
  float rowLine = exp(-rowFr * rowFr / max(2.2 * rowPix * rowPix, 0.000001));
  float vx = p.x * persp * 1.35;
  float vFr = abs(fract(vx + 0.5) - 0.5);
  float vPix = 1.35 * 0.62 / max(gz * f.size.x, 1.0);
  float vLine = exp(-vFr * vFr / max(2.2 * vPix * vPix, 0.000001));
  float gridFade = smoothstep(0.0, 0.045, gz) * (0.35 + 0.65 * smoothstep(horizon, 0.95, uv.y));
  vec3 gridCol = mix(f.color3.rgb, f.color1.rgb, 0.25 + 0.30 * smoothstep(horizon, 1.0, uv.y));
  float grid = (rowLine + vLine * 0.85) * gridFade * (0.55 + 0.45 * f.bass) * (0.40 + 0.60 * f.glow);
  col = mix(col, groundCol + gridCol * grid * drive, ground);
  float hb = (uv.y - horizon) * 26.0;
  col += gridCol * exp(-hb * hb) * 0.22 * (0.5 + f.glow * 0.5);
  float vig = clamp(1.0 - dot(p, p) * 0.28, 0.35, 1.0);
  return vec4(col * vig * f.intensity, 1.0);
}

float creator_8_hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
vec2 creator_8_hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
vec4 creator_8_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.013;
  vec3 acc = vec3(0.0);
  float aAcc = 0.0;
  for (int i = 0; i < 3; i++) {
    float k = float(i);
    float cols = (16.0 + k * 22.0) * f.detail;
    float cx = p.x * cols + k * 23.7 + seed * 5.0;
    float ci = floor(cx);
    float fx = fract(cx) - 0.5;
    vec2 h = creator_8_hash22(vec2(ci, k * 47.0 + seed));
    float spd = 0.42 + 0.45 * h.y + 0.30 * f.flow + 0.22 * f.bass;
    float len = 0.10 + 0.13 * h.x + 0.02 * k;
    float head = fract(h.x * 11.3 + t * spd);
    float rel = uv.y - head;
    float inTrail = smoothstep(-len - 0.012, -len + 0.03, rel) * (1.0 - smoothstep(-0.016, 0.004, rel));
    float lat = exp(-fx * fx * (22.0 - k * 4.0));
    float along = clamp(-rel / max(len, 0.001), 0.0, 1.0);
    float fade = 1.0 - 0.75 * along;
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.y);
    tint = mix(tint, f.color3.rgb, 0.30 + 0.25 * h.x);
    float a = inTrail * lat * fade * (0.62 - 0.12 * k) * (0.6 + 0.6 * f.spark + 0.3 * f.energy);
    float hx2 = fx * fx * 700.0;
    float hy2 = rel * rel * 900.0;
    a += exp(-(hx2 + hy2)) * 0.38 * (0.7 + 0.6 * f.spark);
    acc += tint * a;
    aAcc += a;
  }
  for (int j = 0; j < 2; j++) {
    float k = float(j);
    vec2 gp = vec2(p.x, uv.y) * 4.5 + vec2(seed * 3.0 + k * 11.0, -t * 0.05 - k * 0.02);
    vec2 cell = floor(gp);
    vec2 h = creator_8_hash22(cell + k * 29.0 + seed);
    float on = step(0.45, h.x);
    vec2 pos = cell + 0.25 + 0.50 * h;
    vec2 dd = gp - pos;
    float d2 = dot(dd, dd);
    float bob = 0.5 + 0.5 * sin(t * (0.3 + 0.4 * h.y) + h.x * 6.2831853);
    float g = exp(-d2 * (26.0 - k * 8.0));
    vec3 tint = mix(f.color1.rgb, f.color2.rgb, h.y);
    float a = on * g * bob * (0.13 - 0.04 * k) * (0.7 + 0.5 * f.glow);
    acc += tint * a;
    aAcc += a;
  }
  return vec4(acc * f.intensity, clamp(aAcc * (0.62 + 0.38 * f.glow), 0.0, 0.90));
}

float creator_9_hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
vec2 creator_9_hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
}
float creator_9_vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 u = fract(p);
  u = u * u * (3.0 - 2.0 * u);
  return mix(mix(creator_9_hash12(i), creator_9_hash12(i + vec2(1.0, 0.0)), u.x),
             mix(creator_9_hash12(i + vec2(0.0, 1.0)), creator_9_hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
vec4 creator_9_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = f.size.x / max(f.size.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);
  float t = f.time * f.speed * 0.8;
  float seed = mod(f.seedLow + f.seedHigh, 65535.0) * 0.017;
  vec2 q = p * (2.6 + 1.4 * f.detail) + seed;
  float ca = 0.0;
  vec2 wv = vec2(0.0);
  for (int i = 0; i < 3; i++) {
    float k = float(i) + 1.0;
    wv = vec2(sin(q.y * 5.9 * k + t * (0.50 + 0.20 * k) + wv.x * 1.2 + seed),
              sin(q.x * 5.1 * k - t * (0.42 + 0.18 * k) + wv.y * 1.2));
    ca += 0.5 + 0.5 * sin(q.x * (3.0 + 1.6 * k) + wv.x * 2.2 + t * 0.6 * k)
              * sin(q.y * (4.2 - 0.8 * k) + wv.y * 2.0 - t * 0.5 * k);
  }
  ca /= 3.0;
  float fil = pow(clamp(ca * 1.45 - 0.30, 0.0, 1.0), 5.0);
  float depth = smoothstep(0.0, 1.0, uv.y);
  vec3 col = mix(f.color1.rgb * 0.75, f.color0.rgb, depth);
  col += f.color2.rgb * fil * (0.26 + 0.62 * exp(-uv.y * 2.6));
  col += f.color1.rgb * pow(clamp(ca, 0.0, 1.0), 2.0) * 0.14 * (0.4 + 0.6 * (1.0 - depth));
  float bend = creator_9_vnoise(vec2(p.x * 1.8 - t * 0.11, uv.y * 1.4)) * 1.8;
  float rays = pow(clamp(0.5 + 0.5 * sin(p.x * (5.5 + 2.0 * f.detail) + bend + t * 0.16 + seed), 0.0, 1.0), 4.0);
  col += mix(f.color2.rgb, f.color3.rgb, 0.4) * rays * exp(-uv.y * 3.1) * 0.20 * (0.4 + 0.6 * f.glow);
  vec2 gp = vec2(p.x, uv.y) * 13.0 + vec2(seed * 5.0, -t * 0.12);
  vec2 cell = floor(gp);
  vec2 h = creator_9_hash22(cell + 7.7);
  float on = step(0.90, h.x);
  vec2 pos = cell + 0.30 + 0.40 * h;
  float tw = 0.5 + 0.5 * sin(t * (0.8 + 1.6 * h.y) + h.x * 6.2831853);
  vec2 dd = gp - pos;
  float d2 = dot(dd, dd);
  col += f.color3.rgb * on * exp(-d2 * 420.0) * tw * 0.16 * (0.5 + 0.5 * f.glow);
  float vig = clamp(1.12 - dot(p, p) * 0.42, 0.42, 1.0);
  return vec4(col * vig * f.intensity, 1.0);
}

vec4 creator_10_paintVisual(vec2 uv, CreatorFrame f) {
  vec2 p = (uv - 0.5) * vec2(f.size.x / max(f.size.y, 1.0), 1.0);
  float radius = 0.27 + 0.015 * sin(f.time * f.speed) + 0.025 * f.bass;
  float distance = abs(length(p) - radius);
  float beam = exp(-distance * distance * 17000.0);
  float halo = exp(-distance * 24.0) * 0.25 * f.glow;
  float alpha = clamp((beam * 0.62 + halo) * f.intensity * (0.8 + 0.2 * f.pulse), 0.0, 1.0);
  vec3 ink = mix(f.color1.rgb, f.color2.rgb, 0.5 + 0.5 * sin(p.x * 7.0 + f.time * 0.2));
  return vec4(ink, alpha);
}

vec4 creator_11_paintVisual(vec2 uv, CreatorFrame f) {
vec2 p = (uv - 0.5) * vec2(f.size.x / max(f.size.y, 1.0), 1.0);
float t = f.time * f.speed * 0.2;
vec3 c = f.color0.rgb;
for (int i = 0; i < 3; i++) {
  float k = float(i);
  vec2 center = 0.08 * vec2(cos(t + k * 2.1), sin(t * 0.7 + k * 2.1));
  float r = length(p - center);
  float ring = abs(r - (0.15 + k * 0.085));
  float beam = exp(-ring * ring * 18000.0) * 0.5;
  float halo = exp(-ring * 30.0) * 0.13 * f.glow;
  vec3 ink = mix(f.color1.rgb, f.color3.rgb, k * 0.5);
  c += ink * (beam + halo) * f.intensity;
}
return vec4(c, 1.0);
}

float creator_12_hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
vec2 creator_12_hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract(vec2((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y));
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
  float n = floor(40.0 + 40.0 * f.detail);
  float ac = ang / 6.2831853 * n;
  float ai = floor(ac);
  float af = fract(ac);
  vec2 h = creator_12_hash22(vec2(ai, seed * 0.37));
  float kick = exp(-f.phase * 3.2);
  float wave = 0.5 + 0.5 * sin(t * 0.9 + ai * 1.7 + h.y * 6.2831853);
  float wB = 0.5 + 0.5 * sin((ai / n) * 12.56637 + t * 0.5);
  float wM = 0.5 + 0.5 * cos((ai / n) * 18.84956 - t * 0.37);
  float wH = 0.5 + 0.5 * sin((ai / n) * 31.41593 + t * 0.61);
  float spec = (f.bass * wB + f.body * wM + f.spark * wH) / max(wB + wM + wH, 0.35);
  float flowMod = 0.10 * f.flow * sin(t * 1.3 + h.x * 6.2831853);
  float level = clamp(0.10 + wave * 0.07 + spec * (0.52 + 0.30 * kick) + flowMod, 0.05, 1.0);
  float r0 = 0.145;
  float len = level * 0.26;
  float barWin = smoothstep(0.02, 0.18, af) * smoothstep(0.98, 0.82, af);
  float rr = r - r0;
  float tip = 1.0 - smoothstep(len * 0.82, len, rr);
  float bar = barWin * smoothstep(-0.010, 0.002, rr) * tip;
  float glowTip = exp(-max(rr - len, 0.0) * 30.0) * barWin * (0.12 + 0.25 * level);
  vec3 barCol = mix(f.color1.rgb, f.color2.rgb, clamp(level * 1.3, 0.0, 1.0));
  barCol = mix(barCol, f.color3.rgb, pow(clamp(level * 1.5 - 0.65, 0.0, 1.0), 1.6));
  vec3 col = mix(f.color0.rgb * 0.85, f.color0.rgb * 0.4, smoothstep(0.0, 0.55, r));
  col += barCol * bar * (0.55 + 0.60 * f.energy + 0.30 * kick * f.bass);
  col += barCol * glowTip * f.glow;
  float rd2 = r - r0;
  col += f.color1.rgb * exp(-rd2 * rd2 * 5200.0) * 0.20 * (0.5 + 0.5 * f.glow);
  col += f.color2.rgb * exp(-r * 6.5) * (0.10 + 0.25 * f.bass * kick);
  float vig = clamp(1.08 - dot(p, p) * 0.30, 0.40, 1.0);
  return vec4(col * vig * f.intensity, 1.0);
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
