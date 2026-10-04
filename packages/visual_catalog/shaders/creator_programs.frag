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
vec4 creator_0_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_1_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_2_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_3_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_4_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_5_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_6_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_7_paintVisual(vec2 uv, CreatorFrame f) {
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

vec4 creator_8_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_9_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_10_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_11_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_12_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_13_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_14_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_15_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_16_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_17_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_18_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_19_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_20_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_21_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_22_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_23_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_24_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_25_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_26_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_27_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_28_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_29_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_30_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_31_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_32_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_33_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_34_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_35_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_36_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_37_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec2 creator_38_rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float creator_38_crystalFacet(vec2 p, float size, float t, float bass) {
  vec2 q = abs(p);
  
  float d1 = dot(q, normalize(vec2(1.0, 1.0))) - size;
  float d2 = dot(q, normalize(vec2(1.732, 1.0))) - size;
  float d3 = dot(q, normalize(vec2(1.0, 1.732))) - size;
  float d4 = max(q.x, q.y) - size * 0.92;
  return max(max(d1, d2), max(d3, d4));
}

vec4 creator_38_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.2;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.42;

  vec3 col = vec3(0.0);
  float crystalBaseSize = 0.52 + 0.08 * bass;

  
  for (int ch = 0; ch < 3; ch++) {
    float dispersion = float(ch - 1) * (0.016 + 0.035 * spark);
    vec2 cp = p * (1.0 + dispersion);

    
    vec2 rotP = creator_38_rotate2D(cp, t * 0.35 + bass * 0.25);

    
    float dExt = creator_38_crystalFacet(rotP, crystalBaseSize, t, bass);
    float edgeGlow = (0.018 + 0.025 * spark) / (abs(dExt) * 18.0 + 0.008);

    
    vec2 innerP1 = creator_38_rotate2D(rotP * 1.55, -t * 0.55 + float(ch) * 0.2);
    float dInt1 = creator_38_crystalFacet(innerP1, crystalBaseSize * 0.85, t, bass);
    float innerGlow1 = (0.012 + 0.02 * bass) / (abs(dInt1) * 22.0 + 0.012);

    vec2 innerP2 = creator_38_rotate2D(rotP * 2.4, t * 0.75 + float(ch) * 0.4);
    float dInt2 = creator_38_crystalFacet(innerP2, crystalBaseSize * 0.7, t, bass);
    float innerGlow2 = (0.008 + 0.015 * energy) / (abs(dInt2) * 28.0 + 0.015);

    
    float angle = atan(rotP.y / (rotP.x + 0.00001)) + (rotP.x < 0.0 ? 3.14159 : 0.0);
    float causticRays = pow(abs(cos(angle * 6.0 + t * 0.8)), 8.0) * (0.3 + 0.7 * bass);
    float rayFalloff = exp(-length(cp) * 2.2);
    float caustics = causticRays * rayFalloff;

    
    float core = (0.08 + 0.32 * bass) / (length(cp) * length(cp) * 16.0 + 0.12);

    
    vec3 palColor;
    if (ch == 0) {
      palColor = vec3(1.0, 0.15, 0.45); 
    } else if (ch == 1) {
      palColor = vec3(0.15, 1.0, 0.65); 
    } else {
      palColor = vec3(0.25, 0.55, 1.0); 
    }

    float channelTotal = (edgeGlow * 0.45 + innerGlow1 * 0.35 + innerGlow2 * 0.25 + caustics * 0.5 + core * 0.7);

    col += palColor * channelTotal;
  }

  
  vec2 flareP = creator_38_rotate2D(p, t * 0.35);
  float starX = exp(-abs(flareP.x) * 45.0) * exp(-abs(flareP.y) * 4.0);
  float starY = exp(-abs(flareP.y) * 45.0) * exp(-abs(flareP.x) * 4.0);
  float diamondFlare = (starX + starY) * (0.2 + 1.8 * spark);
  col += vec3(1.0, 0.98, 0.92) * diamondFlare;

  
  vec3 bg = vec3(0.012, 0.015, 0.03) * (1.0 - 0.4 * length(p));
  col = mix(bg, col, smoothstep(0.0, 0.15, length(col)));

  
  col = col / (col + vec3(0.88));
  float vignette = 1.0 - smoothstep(0.45, 1.45, length(p));
  col *= vignette;

  return vec4(clamp(col * f.intensity * f.glow, 0.0, 1.0), 1.0);
}

vec4 creator_39_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_40_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_41_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_42_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_43_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_44_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_45_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_46_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_47_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_48_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_49_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_50_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_51_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_52_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec2 creator_53_rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float creator_53_getAngle(vec2 p) {
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

vec4 creator_53_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.2;

  float r = length(p);
  float a = creator_53_getAngle(p);

  float beat = clamp(f.pulse, 0.0, 1.0);
  float bass = clamp(f.bass, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);
  float t = f.time * 0.42 * f.speed;

  
  vec3 bgCol = mix(vec3(0.02, 0.008, 0.06), vec3(0.06, 0.015, 0.14), r * 0.8);
  bgCol = bgCol + vec3(0.1, 0.02, 0.18) * sin(r * 4.0 - t * 1.5) * 0.3;

  vec3 col = bgCol;

  
  float a1 = a + t * 0.6;
  float pet1 = cos(5.0 * a1);
  float r1 = 0.18 + 0.08 * pet1 + bass * 0.06;
  float d1 = abs(r - r1);
  float edge1 = 0.012 / (d1 + 0.012);
  vec3 col1 = mix(vec3(1.0, 0.85, 0.2), vec3(1.0, 0.25, 0.6), 0.5 + 0.5 * pet1);
  col = col + col1 * edge1 * 0.7;

  
  float a2 = a - t * 0.4;
  float pet2 = cos(8.0 * a2);
  float r2 = 0.35 + 0.12 * pet2 + beat * 0.08;
  float d2 = abs(r - r2);
  float edge2 = 0.015 / (d2 + 0.018);
  vec3 col2 = mix(vec3(0.2, 0.85, 1.0), vec3(0.9, 0.1, 0.7), 0.5 + 0.5 * pet2);
  col = col + col2 * edge2 * 0.65;

  
  float a3 = a + t * 0.25;
  float pet3 = cos(13.0 * a3);
  float r3 = 0.58 + 0.15 * pet3 + bass * 0.1;
  float d3 = abs(r - r3);
  float edge3 = 0.018 / (d3 + 0.022);
  vec3 col3 = mix(vec3(0.95, 0.3, 0.8), vec3(1.0, 0.7, 0.2), 0.5 + 0.5 * pet3);
  col = col + col3 * edge3 * 0.6;

  
  float a4 = a - t * 0.15;
  float pet4 = cos(21.0 * a4);
  float r4 = 0.82 + 0.14 * pet4 + beat * 0.06;
  float d4 = abs(r - r4);
  float edge4 = 0.012 / (d4 + 0.025);
  vec3 col4 = mix(vec3(0.4, 0.3, 1.0), vec3(0.2, 0.95, 0.8), 0.5 + 0.5 * pet4);
  col = col + col4 * edge4 * (0.4 + 0.3 * spark);

  
  float spiral1 = sin(log(r + 0.02) * 5.0 - a * 3.0 + t * 1.2);
  float spiral2 = sin(log(r + 0.02) * 5.0 + a * 3.0 - t * 1.2);
  float spiralGrid = smoothstep(0.85, 0.98, spiral1) + smoothstep(0.85, 0.98, spiral2);
  col = col + vec3(1.0, 0.8, 0.3) * spiralGrid * 0.35 * exp(-r * 1.8);

  
  float coreDist = r;
  float coreGlow = 0.04 / (coreDist * coreDist * 6.0 + 0.04);
  float corePulse = 1.0 + 0.4 * sin(t * 4.0) + bass * 0.8;
  vec3 coreColor = mix(vec3(1.0, 0.95, 0.5), vec3(1.0, 0.4, 0.1), clamp(r * 5.0, 0.0, 1.0));
  col = col + coreColor * coreGlow * corePulse * 1.2;

  
  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    float pAngle = fi * 1.047 + t * (0.8 + 0.2 * fi);
    float pRad = 0.25 + 0.15 * sin(fi * 2.1 + t * 1.5) + bass * 0.1;
    vec2 pPos = vec2(cos(pAngle), sin(pAngle)) * pRad;
    float pDist = length(p - pPos);
    float pGlow = 0.003 / (pDist * pDist * 25.0 + 0.003);
    col = col + vec3(1.0, 0.9, 0.4) * pGlow * (0.8 + 0.8 * spark);
  }

  
  col = col / (col + vec3(0.85));
  float vig = 1.0 - smoothstep(0.5, 1.5, r);
  col = col * vig * f.intensity * f.glow;

  return vec4(clamp(col, 0.0, 1.0), 1.0);
}

vec2 creator_54_rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float creator_54_getAngle(vec2 p) {
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

vec4 creator_54_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.2;

  float r = length(p);
  float a = creator_54_getAngle(p);

  float beat = clamp(f.pulse, 0.0, 1.0);
  float bass = clamp(f.bass, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);
  float t = f.time * 0.42 * f.speed;

  vec3 col = vec3(0.0);

  
  float a1 = a + t * 0.6;
  float pet1 = cos(5.0 * a1);
  float r1 = 0.18 + 0.08 * pet1 + bass * 0.06;
  float d1 = abs(r - r1);
  float edge1 = 0.012 / (d1 + 0.012);
  vec3 col1 = mix(vec3(1.0, 0.85, 0.2), vec3(1.0, 0.25, 0.6), 0.5 + 0.5 * pet1);
  col = col + col1 * edge1 * 0.7;

  
  float a2 = a - t * 0.4;
  float pet2 = cos(8.0 * a2);
  float r2 = 0.35 + 0.12 * pet2 + beat * 0.08;
  float d2 = abs(r - r2);
  float edge2 = 0.015 / (d2 + 0.018);
  vec3 col2 = mix(vec3(0.2, 0.85, 1.0), vec3(0.9, 0.1, 0.7), 0.5 + 0.5 * pet2);
  col = col + col2 * edge2 * 0.65;

  
  float a3 = a + t * 0.25;
  float pet3 = cos(13.0 * a3);
  float r3 = 0.58 + 0.15 * pet3 + bass * 0.1;
  float d3 = abs(r - r3);
  float edge3 = 0.018 / (d3 + 0.022);
  vec3 col3 = mix(vec3(0.95, 0.3, 0.8), vec3(1.0, 0.7, 0.2), 0.5 + 0.5 * pet3);
  col = col + col3 * edge3 * 0.6;

  
  float a4 = a - t * 0.15;
  float pet4 = cos(21.0 * a4);
  float r4 = 0.82 + 0.14 * pet4 + beat * 0.06;
  float d4 = abs(r - r4);
  float edge4 = 0.012 / (d4 + 0.025);
  vec3 col4 = mix(vec3(0.4, 0.3, 1.0), vec3(0.2, 0.95, 0.8), 0.5 + 0.5 * pet4);
  col = col + col4 * edge4 * (0.4 + 0.3 * spark);

  
  float spiral1 = sin(log(r + 0.02) * 5.0 - a * 3.0 + t * 1.2);
  float spiral2 = sin(log(r + 0.02) * 5.0 + a * 3.0 - t * 1.2);
  float spiralGrid = smoothstep(0.85, 0.98, spiral1) + smoothstep(0.85, 0.98, spiral2);
  col = col + vec3(1.0, 0.8, 0.3) * spiralGrid * 0.35 * exp(-r * 1.8);

  
  float coreDist = r;
  float coreGlow = 0.04 / (coreDist * coreDist * 6.0 + 0.04);
  float corePulse = 1.0 + 0.4 * sin(t * 4.0) + bass * 0.8;
  vec3 coreColor = mix(vec3(1.0, 0.95, 0.5), vec3(1.0, 0.4, 0.1), clamp(r * 5.0, 0.0, 1.0));
  col = col + coreColor * coreGlow * corePulse * 1.2;

  
  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    float pAngle = fi * 1.047 + t * (0.8 + 0.2 * fi);
    float pRad = 0.25 + 0.15 * sin(fi * 2.1 + t * 1.5) + bass * 0.1;
    vec2 pPos = vec2(cos(pAngle), sin(pAngle)) * pRad;
    float pDist = length(p - pPos);
    float pGlow = 0.003 / (pDist * pDist * 25.0 + 0.003);
    col = col + vec3(1.0, 0.9, 0.4) * pGlow * (0.8 + 0.8 * spark);
  }

  
  col = col / (col + vec3(0.85));
  float vig = 1.0 - smoothstep(0.5, 1.5, r);
  col = col * vig * f.intensity * f.glow;

  
  float alpha = clamp(max(col.r, max(col.g, col.b)) * 1.6, 0.0, 1.0);
  return vec4(clamp(col, 0.0, 1.0), alpha);
}

vec4 creator_55_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_56_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_57_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec2 creator_58_rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float creator_58_getAngle(vec2 p) {
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


float creator_58_solarNoise(vec2 p, float t) {
  float n = 0.0;
  n = n + sin(p.x * 6.0 + t * 1.2) * cos(p.y * 6.0 - t * 0.9);
  n = n + sin(p.x * 14.0 - t * 1.8 + p.y * 5.0) * 0.5;
  n = n + cos(p.y * 24.0 + t * 3.1 - p.x * 10.0) * 0.25;
  n = n + sin((p.x + p.y) * 36.0 + t * 4.5) * 0.12;
  return n * 0.53;
}


vec3 creator_58_blackbody(float heat) {
  vec3 col = vec3(0.0);
  col = mix(col, vec3(0.65, 0.03, 0.0), smoothstep(0.0, 0.32, heat));
  col = mix(col, vec3(1.0, 0.32, 0.02), smoothstep(0.24, 0.62, heat));
  col = mix(col, vec3(1.0, 0.88, 0.18), smoothstep(0.52, 0.82, heat));
  col = mix(col, vec3(1.0, 1.0, 0.98), smoothstep(0.78, 1.05, heat));
  return col;
}

vec4 creator_58_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.2;

  float t = f.time * 0.55 * f.speed;
  float bass = clamp(f.bass, 0.0, 1.0);
  float beat = clamp(f.pulse, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);

  float r = length(p);
  float a = creator_58_getAngle(p);

  
  float coreRadius = 0.34 + bass * 0.09 + beat * 0.04;

  
  vec3 col = vec3(0.015, 0.003, 0.008) + vec3(0.14, 0.018, 0.0) * exp(-r * 1.6);

  
  float wavePhase = mod(r * 2.8 - t * 2.0, 2.0);
  float shock = exp(-abs(wavePhase - 1.0) * 14.0) * exp(-r * 0.9);
  col = col + vec3(1.0, 0.45, 0.08) * shock * (0.6 + 0.9 * bass);

  
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

  
  float rays = sin(a * 16.0 + t * 2.2 + sin(r * 6.0 - t * 3.5)) * 0.5 + 0.5;
  rays = rays * smoothstep(coreRadius * 0.8, 1.3, r) * exp(-r * 2.0);
  col = col + vec3(1.0, 0.55, 0.12) * rays * (0.8 + 0.8 * beat);

  
  for (int m = 0; m < 5; m++) {
    float fm = float(m);
    vec2 loopCenter = vec2(cos(fm * 1.256 + t * 0.35), sin(fm * 1.256 + t * 0.35)) * (coreRadius * 0.92);
    float dLoop = length(p - loopCenter);
    float loopRadius = 0.13 + 0.05 * sin(t * 1.6 + fm * 1.8);
    float loopRing = abs(dLoop - loopRadius);
    float loopGlow = 0.0035 / (loopRing * loopRing * 22.0 + 0.004);
    col = col + vec3(1.0, 0.75, 0.25) * loopGlow * (0.7 + 0.6 * spark);
  }

  
  if (r < coreRadius * 1.25) {
    vec2 surfCoord = creator_58_rotate2D(p, t * 0.18);
    float granulation = creator_58_solarNoise(surfCoord * 5.0, t * 1.5);
    
    
    float radialFactor = clamp((coreRadius - r) / coreRadius, 0.0, 1.0);
    float heat = radialFactor * 0.92 + granulation * 0.32 + bass * 0.35;
    vec3 sunSurface = creator_58_blackbody(clamp(heat, 0.0, 1.25));

    
    float diskAlpha = smoothstep(coreRadius + 0.02, coreRadius - 0.02, r);
    col = mix(col, sunSurface, diskAlpha);
  }

  
  float coreGlow = 0.06 / (r * r * 8.5 + 0.06);
  col = col + vec3(1.0, 0.92, 0.75) * coreGlow * (0.9 + 1.1 * bass);

  
  for (int s = 0; s < 8; s++) {
    float fs = float(s);
    float spAngle = fs * 0.785 + t * (1.3 + 0.25 * fs);
    float spRad = coreRadius + 0.10 + 0.28 * fract(sin(fs * 43.12) * 532.1 + t * 0.45);
    vec2 spPos = vec2(cos(spAngle), sin(spAngle)) * spRad;
    float spDist = length(p - spPos);
    float sparkGlow = 0.002 / (spDist * spDist * 32.0 + 0.002);
    col = col + vec3(1.0, 0.9, 0.4) * sparkGlow * (1.0 + 1.3 * spark);
  }

  
  col = col / (col + vec3(0.82));
  float vig = 1.0 - smoothstep(0.5, 1.5, r);
  col = col * vig * f.intensity * f.glow;

  return vec4(clamp(col, 0.0, 1.0), 1.0);
}

vec4 creator_59_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_60_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_61_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_62_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_63_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_64_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_65_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_66_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_67_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_68_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_69_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_70_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_71_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_72_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_73_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_74_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_75_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_76_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_77_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_78_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_79_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_80_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_81_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_82_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_83_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_84_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_85_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_86_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_87_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_88_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_89_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
float creator_90_liquidField(vec2 p, float t, float bass, float spark, float flow) {
  float r = length(p);
  
  float ripple = sin(r * (14.0 + 3.0 * flow) - t * 3.8) * (0.035 + 0.055 * bass);

  
  vec2 c1 = vec2(sin(t * 0.7) * 0.42, cos(t * 0.8) * 0.35);
  vec2 c2 = vec2(cos(t * 0.9 + 1.8) * 0.38, sin(t * 0.6) * 0.42);
  float wave1 = sin(length(p - c1) * 16.0 - t * 4.2) * (0.025 + 0.035 * bass);
  float wave2 = sin(length(p - c2) * 18.0 - t * 3.6) * (0.020 + 0.030 * spark);

  
  float sizzle = sin(p.x * 32.0 + t * 4.5) * cos(p.y * 32.0 + t * 4.0) * (0.006 + 0.018 * spark);

  
  float dome = exp(-r * r * 2.2) * 0.16;

  return dome + ripple + wave1 + wave2 + sizzle;
}

vec4 creator_90_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.1;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.48;

  
  float eps = 0.0035;
  float hC = creator_90_liquidField(p, t, bass, spark, flow);
  float hR = creator_90_liquidField(p + vec2(eps, 0.0), t, bass, spark, flow);
  float hU = creator_90_liquidField(p + vec2(0.0, eps), t, bass, spark, flow);

  vec3 normal = normalize(vec3((hC - hR) / eps, (hC - hU) / eps, 0.32));

  
  vec3 view = normalize(vec3(p * 0.22, 1.0));
  vec3 ref = reflect(-view, normal);

  
  float horizon = smoothstep(-0.25, 0.25, ref.y);
  float stripe = sin(ref.y * 12.0 + ref.x * 6.0 + t * 0.25);
  float studioStripe = smoothstep(0.35, 0.75, stripe);

  vec3 deepMetal = vec3(0.02, 0.035, 0.07);
  vec3 silver = vec3(0.85, 0.90, 0.98);
  vec3 neonCyan = vec3(0.20, 0.85, 1.0);
  vec3 neonMagenta = vec3(0.95, 0.20, 0.65);

  vec3 chrome = mix(deepMetal, silver, horizon * 0.8 + studioStripe * 0.25);

  
  vec3 lightDir1 = normalize(vec3(-0.45, 0.7, 0.6));
  float spec1 = pow(max(dot(ref, lightDir1), 0.0), 36.0) * (1.6 + 2.4 * spark);
  vec3 lightDir2 = normalize(vec3(0.55, -0.5, 0.55));
  float spec2 = pow(max(dot(ref, lightDir2), 0.0), 22.0) * (0.8 + 1.4 * bass);

  
  float fresnel = pow(1.0 - max(dot(normal, view), 0.0), 2.6);
  vec3 rimColor = mix(neonCyan, neonMagenta, 0.5 + 0.5 * sin(t * 0.35 + p.y * 2.2));

  
  vec3 surface = chrome + (spec1 + spec2) * vec3(1.0, 0.98, 0.93) + fresnel * rimColor * (0.65 + 0.85 * energy);

  
  float fluidAlpha = smoothstep(1.4, 0.85, length(p));
  vec3 bg = vec3(0.015, 0.02, 0.035) * (1.0 - 0.45 * length(p));
  vec3 finalColor = mix(bg, surface, fluidAlpha);

  return vec4(clamp(finalColor * f.intensity * f.glow, 0.0, 1.0), 1.0);
}

float creator_91_liquidField(vec2 p, float t, float bass, float spark, float flow) {
  float r = length(p);
  
  float ripple = sin(r * (14.0 + 3.0 * flow) - t * 3.8) * (0.035 + 0.055 * bass);

  
  vec2 c1 = vec2(sin(t * 0.7) * 0.42, cos(t * 0.8) * 0.35);
  vec2 c2 = vec2(cos(t * 0.9 + 1.8) * 0.38, sin(t * 0.6) * 0.42);
  float wave1 = sin(length(p - c1) * 16.0 - t * 4.2) * (0.025 + 0.035 * bass);
  float wave2 = sin(length(p - c2) * 18.0 - t * 3.6) * (0.020 + 0.030 * spark);

  
  float sizzle = sin(p.x * 32.0 + t * 4.5) * cos(p.y * 32.0 + t * 4.0) * (0.006 + 0.018 * spark);

  
  float dome = exp(-r * r * 2.2) * 0.16;

  return dome + ripple + wave1 + wave2 + sizzle;
}

vec4 creator_91_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.1;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.48;

  
  float eps = 0.0035;
  float hC = creator_91_liquidField(p, t, bass, spark, flow);
  float hR = creator_91_liquidField(p + vec2(eps, 0.0), t, bass, spark, flow);
  float hU = creator_91_liquidField(p + vec2(0.0, eps), t, bass, spark, flow);

  vec3 normal = normalize(vec3((hC - hR) / eps, (hC - hU) / eps, 0.32));

  
  vec3 view = normalize(vec3(p * 0.22, 1.0));
  vec3 ref = reflect(-view, normal);

  
  float horizon = smoothstep(-0.25, 0.25, ref.y);
  float stripe = sin(ref.y * 12.0 + ref.x * 6.0 + t * 0.25);
  float studioStripe = smoothstep(0.35, 0.75, stripe);

  vec3 deepMetal = vec3(0.02, 0.035, 0.07);
  vec3 silver = vec3(0.85, 0.90, 0.98);
  vec3 neonCyan = vec3(0.20, 0.85, 1.0);
  vec3 neonMagenta = vec3(0.95, 0.20, 0.65);

  vec3 chrome = mix(deepMetal, silver, horizon * 0.8 + studioStripe * 0.25);

  
  vec3 lightDir1 = normalize(vec3(-0.45, 0.7, 0.6));
  float spec1 = pow(max(dot(ref, lightDir1), 0.0), 36.0) * (1.6 + 2.4 * spark);
  vec3 lightDir2 = normalize(vec3(0.55, -0.5, 0.55));
  float spec2 = pow(max(dot(ref, lightDir2), 0.0), 22.0) * (0.8 + 1.4 * bass);

  
  float fresnel = pow(1.0 - max(dot(normal, view), 0.0), 2.6);
  vec3 rimColor = mix(neonCyan, neonMagenta, 0.5 + 0.5 * sin(t * 0.35 + p.y * 2.2));

  
  vec3 surface = chrome + (spec1 + spec2) * vec3(1.0, 0.98, 0.93) + fresnel * rimColor * (0.65 + 0.85 * energy);

  
  float fluidAlpha = smoothstep(1.35, 0.65, length(p));
  float alpha = fluidAlpha * smoothstep(0.04, 0.20, max(surface.r, max(surface.g, surface.b)));

  
  return vec4(clamp(surface * f.intensity * f.glow, 0.0, 1.0), alpha);
}

vec4 creator_92_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_93_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_94_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_95_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_96_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_97_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_98_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_99_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_100_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_101_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_102_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_103_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_104_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_105_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_106_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_107_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_108_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_109_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_110_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_111_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_112_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_113_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_114_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_115_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_116_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_117_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_118_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_119_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_120_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_121_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_122_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_123_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec2 creator_124_rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

vec3 creator_124_paletteCos(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
  return a + b * cos(6.28318 * (c * t + d));
}

vec4 creator_124_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.2;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.42;
  vec3 col = vec3(0.0);

  
  for (int ch = 0; ch < 3; ch++) {
    float dispersion = float(ch - 1) * (0.012 + 0.022 * spark);
    vec2 cp = p * (1.0 + dispersion);

    float r = length(cp);
    
    float z = 1.0 / (r + 0.06);
    float tunnelDepth = z * 0.55 - t * (1.1 + 0.9 * energy);

    
    vec2 q = creator_124_rotate2D(cp, t * 0.25 + z * 0.12 + bass * 0.35);

    
    float accum = 0.0;
    vec2 k = q * (1.8 + 0.4 * flow);
    for (int i = 0; i < 4; i++) {
      float fi = float(i);
      k = abs(k) - vec2(0.32 + 0.12 * sin(t * 0.6 + fi * 1.3), 0.22 + 0.08 * cos(t * 0.45));
      k = creator_124_rotate2D(k, 0.785398 + 0.25 * bass + fi * 0.3);
      accum += 1.0 / (length(k) * 22.0 + 1.0);
    }

    
    float ringPattern = abs(sin(tunnelDepth * 3.14159));
    float ringGlow = (0.025 + 0.035 * bass) / (ringPattern * ringPattern + 0.007);

    
    float core = (0.10 + 0.35 * bass) / (r * r * 18.0 + 0.12);

    
    vec3 pal = creator_124_paletteCos(
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

  
  col = col / (col + vec3(0.85));
  float vignette = 1.0 - smoothstep(0.45, 1.45, length(p));
  col *= vignette;

  return vec4(col, 1.0);
}

vec2 creator_125_rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

vec3 creator_125_paletteCos(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
  return a + b * cos(6.28318 * (c * t + d));
}

vec4 creator_125_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.2;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.42;
  vec3 col = vec3(0.0);

  
  for (int ch = 0; ch < 3; ch++) {
    float dispersion = float(ch - 1) * (0.012 + 0.022 * spark);
    vec2 cp = p * (1.0 + dispersion);

    float r = length(cp);
    
    float z = 1.0 / (r + 0.06);
    float tunnelDepth = z * 0.55 - t * (1.1 + 0.9 * energy);

    
    vec2 q = creator_125_rotate2D(cp, t * 0.25 + z * 0.12 + bass * 0.35);

    
    float accum = 0.0;
    vec2 k = q * (1.8 + 0.4 * flow);
    for (int i = 0; i < 4; i++) {
      float fi = float(i);
      k = abs(k) - vec2(0.32 + 0.12 * sin(t * 0.6 + fi * 1.3), 0.22 + 0.08 * cos(t * 0.45));
      k = creator_125_rotate2D(k, 0.785398 + 0.25 * bass + fi * 0.3);
      accum += 1.0 / (length(k) * 22.0 + 1.0);
    }

    
    float ringPattern = abs(sin(tunnelDepth * 3.14159));
    float ringGlow = (0.025 + 0.035 * bass) / (ringPattern * ringPattern + 0.007);

    
    float core = (0.10 + 0.35 * bass) / (r * r * 18.0 + 0.12);

    
    vec3 pal = creator_125_paletteCos(
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

  
  col = col / (col + vec3(0.85));
  float vignette = 1.0 - smoothstep(0.45, 1.45, length(p));
  col *= vignette;

  
  float alpha = clamp(max(col.r, max(col.g, col.b)) * 1.6, 0.0, 1.0);
  return vec4(clamp(col, 0.0, 1.0), alpha);
}

vec4 creator_126_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_127_paintVisual(vec2 uv, CreatorFrame f) {
  vec2 p = (uv - 0.5) * vec2(f.size.x / max(f.size.y, 1.0), 1.0);
  float radius = 0.27 + 0.015 * sin(f.time * f.speed) + 0.025 * f.bass;
  float distance = abs(length(p) - radius);
  float beam = exp(-distance * distance * 17000.0);
  float halo = exp(-distance * 24.0) * 0.25 * f.glow;
  float alpha = clamp((beam * 0.62 + halo) * f.intensity * (0.8 + 0.2 * f.pulse), 0.0, 1.0);
  vec3 ink = mix(f.color1.rgb, f.color2.rgb, 0.5 + 0.5 * sin(p.x * 7.0 + f.time * 0.2));
  return vec4(ink, alpha);
}

vec4 creator_128_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_129_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_130_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec2 creator_131_rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

vec4 creator_131_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.2;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.38;

  
  vec2 q = vec2(
    sin(p.x * 1.8 + t * 0.45 + bass * 0.2),
    cos(p.y * 1.8 + t * 0.38 + flow * 0.3)
  );

  vec2 r = vec2(
    sin(p.x * 2.8 + q.y * 2.4 + t * 0.52),
    cos(p.y * 2.8 + q.x * 2.4 + t * 0.44)
  );

  
  vec2 warpedP = p + r * (0.35 + 0.15 * flow);
  warpedP = creator_131_rotate2D(warpedP, t * 0.12 + bass * 0.2);

  float ribbon1 = sin(warpedP.y * 4.2 + warpedP.x * 2.1 + t * 1.2);
  float ribbon2 = cos(warpedP.y * 5.6 - warpedP.x * 2.8 - t * 0.95);
  float ribbon3 = sin(length(warpedP) * 5.0 - t * 1.6);

  float sheet1 = 1.0 / (abs(ribbon1) * 14.0 + 1.0);
  float sheet2 = 1.0 / (abs(ribbon2) * 16.0 + 1.0);
  float sheet3 = 1.0 / (abs(ribbon3) * 12.0 + 1.0);

  
  vec3 deepNavy = vec3(0.008, 0.024, 0.070);
  vec3 bioEmerald = vec3(0.08, 0.96, 0.60);
  vec3 bioCyan = vec3(0.15, 0.85, 1.0);
  vec3 bioViolet = vec3(0.62, 0.10, 0.95);
  vec3 warmSparkle = vec3(1.0, 0.95, 0.80);

  
  vec3 col = deepNavy;
  col += bioCyan * sheet1 * (0.75 + 0.55 * bass);
  col += bioEmerald * sheet2 * (0.65 + 0.65 * energy);
  col += bioViolet * sheet3 * (0.55 + 0.45 * flow);

  
  float sporeGrid = sin(warpedP.x * 32.0 + t * 4.0) * cos(warpedP.y * 32.0 - t * 3.5);
  float spores = smoothstep(0.72, 0.98, sporeGrid) * (sheet1 + sheet2);
  col += warmSparkle * spores * (0.4 + 2.2 * spark);

  
  float rays = sin(p.x * 6.0 + p.y * 3.0 + t * 0.8) * 0.5 + 0.5;
  col += bioCyan * rays * 0.12 * (1.0 + bass * 0.6);

  
  col = col / (col + vec3(0.9));
  float vignette = 1.0 - smoothstep(0.5, 1.45, length(p));
  col *= vignette;

  return vec4(clamp(col * f.intensity * f.glow, 0.0, 1.0), 1.0);
}

vec4 creator_132_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_133_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_134_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_135_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_136_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_137_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_138_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_139_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_140_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_141_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_142_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_143_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_144_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_145_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_146_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_147_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_148_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_149_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_150_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_151_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_152_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_153_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_154_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_155_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_156_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_157_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_158_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_159_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_160_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_161_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_162_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_163_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_164_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_165_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_166_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_167_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_168_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_169_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_170_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_171_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_172_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_173_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec2 creator_174_rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float creator_174_hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 creator_174_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.3;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.44;

  float r = length(p);
  float eventHorizon = 0.26 + 0.05 * bass;

  
  vec2 lensP = p;
  if (r > eventHorizon) {
    float defl = (eventHorizon * eventHorizon) / (r * r + 0.001);
    lensP = p * (1.0 - defl * 0.42);
  }

  
  vec2 diskP = lensP;
  diskP.y *= 2.35; 
  diskP = creator_174_rotate2D(diskP, 0.38);

  float diskR = length(diskP);
  
  float diskAngle = atan(diskP.y / (diskP.x + 0.00001)) + (diskP.x < 0.0 ? 3.14159 : 0.0);

  
  float spiral = diskAngle * 2.0 - log(diskR + 0.001) * 3.4 - t * (2.2 + 1.4 * flow + 1.8 * energy);
  float arm1 = sin(spiral) * 0.5 + 0.5;
  float arm2 = sin(spiral * 2.0 + 1.3) * 0.5 + 0.5;
  float arms = arm1 * 0.7 + arm2 * 0.3;

  
  float diskMask = smoothstep(eventHorizon * 0.88, eventHorizon * 1.32, diskR) *
                   smoothstep(1.65, eventHorizon * 1.5, diskR);

  
  float doppler = 1.0 - clamp(diskP.x * 0.65, -0.65, 0.65);

  
  float photonDist = abs(r - eventHorizon);
  float photonRing = (0.012 + 0.025 * bass) / (photonDist * photonDist + 0.0028);

  
  vec3 hotOrange = vec3(1.0, 0.45, 0.12);
  vec3 electricCyan = vec3(0.25, 0.85, 1.0);
  vec3 pureWhite = vec3(1.0, 0.98, 0.92);

  vec3 diskColor = mix(hotOrange, electricCyan, arms * 0.5 + energy * 0.45);
  diskColor = mix(diskColor, pureWhite, pow(arms, 3.0) * (0.45 + spark * 0.8));

  vec3 col = diskColor * arms * diskMask * doppler * (1.6 + bass * 0.85);
  col += vec3(0.28, 0.72, 1.0) * photonRing * (0.85 + energy * 0.65);

  
  vec2 starGrid = floor(lensP * 28.0);
  float starHash = creator_174_hash21(starGrid);
  if (starHash > 0.962) {
    if (r > eventHorizon * 1.15) {
      vec2 starFrac = fract(lensP * 28.0) - 0.5;
      float starDist = length(starFrac);
      float starTwinkle = 0.5 + 0.5 * sin(t * 3.0 + starHash * 30.0);
      float starBright = (0.018 * starTwinkle + 0.028 * spark) / (starDist * starDist * 60.0 + 0.05);
      col += vec3(0.85, 0.92, 1.0) * starBright;
    }
  }

  
  float shadow = smoothstep(eventHorizon * 0.85, eventHorizon * 1.05, r);
  col *= shadow;

  
  float jetY = abs(p.y);
  float jetX = abs(p.x);
  float jet = exp(-jetX * 36.0) * smoothstep(0.18, 1.25, jetY) * (0.15 + 0.85 * bass);
  col += electricCyan * jet * 0.55;

  
  col = col / (col + vec3(0.92));
  float vignette = 1.0 - smoothstep(0.55, 1.45, length(p));
  col *= vignette;

  return vec4(clamp(col * f.intensity * f.glow, 0.0, 1.0), 1.0);
}

vec2 creator_175_rotate2D(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float creator_175_hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 creator_175_paintVisual(vec2 uv, CreatorFrame f) {
  float aspect = max(f.size.x, 1.0) / max(f.size.y, 1.0);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 2.3;

  float bass = clamp(f.bass, 0.0, 1.0);
  float energy = clamp(f.energy, 0.0, 1.0);
  float spark = clamp(f.spark, 0.0, 1.0);
  float flow = clamp(f.flow, 0.0, 1.0);

  float t = f.time * f.speed * 0.44;

  float r = length(p);
  float eventHorizon = 0.26 + 0.05 * bass;

  
  vec2 lensP = p;
  if (r > eventHorizon) {
    float defl = (eventHorizon * eventHorizon) / (r * r + 0.001);
    lensP = p * (1.0 - defl * 0.42);
  }

  
  vec2 diskP = lensP;
  diskP.y *= 2.35; 
  diskP = creator_175_rotate2D(diskP, 0.38);

  float diskR = length(diskP);
  
  float diskAngle = atan(diskP.y / (diskP.x + 0.00001)) + (diskP.x < 0.0 ? 3.14159 : 0.0);

  
  float spiral = diskAngle * 2.0 - log(diskR + 0.001) * 3.4 - t * (2.2 + 1.4 * flow + 1.8 * energy);
  float arm1 = sin(spiral) * 0.5 + 0.5;
  float arm2 = sin(spiral * 2.0 + 1.3) * 0.5 + 0.5;
  float arms = arm1 * 0.7 + arm2 * 0.3;

  
  float diskMask = smoothstep(eventHorizon * 0.88, eventHorizon * 1.32, diskR) *
                   smoothstep(1.65, eventHorizon * 1.5, diskR);

  
  float doppler = 1.0 - clamp(diskP.x * 0.65, -0.65, 0.65);

  
  float photonDist = abs(r - eventHorizon);
  float photonRing = (0.012 + 0.025 * bass) / (photonDist * photonDist + 0.0028);

  
  vec3 hotOrange = vec3(1.0, 0.45, 0.12);
  vec3 electricCyan = vec3(0.25, 0.85, 1.0);
  vec3 pureWhite = vec3(1.0, 0.98, 0.92);

  vec3 diskColor = mix(hotOrange, electricCyan, arms * 0.5 + energy * 0.45);
  diskColor = mix(diskColor, pureWhite, pow(arms, 3.0) * (0.45 + spark * 0.8));

  vec3 col = diskColor * arms * diskMask * doppler * (1.6 + bass * 0.85);
  col += vec3(0.28, 0.72, 1.0) * photonRing * (0.85 + energy * 0.65);

  
  vec2 starGrid = floor(lensP * 28.0);
  float starHash = creator_175_hash21(starGrid);
  if (starHash > 0.962) {
    if (r > eventHorizon * 1.15) {
      vec2 starFrac = fract(lensP * 28.0) - 0.5;
      float starDist = length(starFrac);
      float starTwinkle = 0.5 + 0.5 * sin(t * 3.0 + starHash * 30.0);
      float starBright = (0.018 * starTwinkle + 0.028 * spark) / (starDist * starDist * 60.0 + 0.05);
      col += vec3(0.85, 0.92, 1.0) * starBright;
    }
  }

  
  float shadow = smoothstep(eventHorizon * 0.85, eventHorizon * 1.05, r);
  col *= shadow;

  
  float jetY = abs(p.y);
  float jetX = abs(p.x);
  float jet = exp(-jetX * 36.0) * smoothstep(0.18, 1.25, jetY) * (0.15 + 0.85 * bass);
  col += electricCyan * jet * 0.55;

  
  col = col / (col + vec3(0.92));
  float vignette = 1.0 - smoothstep(0.55, 1.45, length(p));
  col *= vignette;

  float alpha = clamp(max(col.r, max(col.g, col.b)) * 1.8, 0.0, 1.0);
  
  return vec4(clamp(col * f.intensity * f.glow, 0.0, 1.0), alpha);
}

vec4 creator_176_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_177_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_178_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
vec4 creator_179_paintVisual(vec2 uv, CreatorFrame f) { return vec4(0.0); }
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
  if (abs(uVisualIndex - 1.0) < 0.5) color=creator_1_paintVisual(uv,f);
  if (abs(uVisualIndex - 2.0) < 0.5) color=creator_2_paintVisual(uv,f);
  if (abs(uVisualIndex - 3.0) < 0.5) color=creator_3_paintVisual(uv,f);
  if (abs(uVisualIndex - 4.0) < 0.5) color=creator_4_paintVisual(uv,f);
  if (abs(uVisualIndex - 5.0) < 0.5) color=creator_5_paintVisual(uv,f);
  if (abs(uVisualIndex - 6.0) < 0.5) color=creator_6_paintVisual(uv,f);
  if (abs(uVisualIndex - 7.0) < 0.5) color=creator_7_paintVisual(uv,f);
  if (abs(uVisualIndex - 8.0) < 0.5) color=creator_8_paintVisual(uv,f);
  if (abs(uVisualIndex - 9.0) < 0.5) color=creator_9_paintVisual(uv,f);
  if (abs(uVisualIndex - 10.0) < 0.5) color=creator_10_paintVisual(uv,f);
  if (abs(uVisualIndex - 11.0) < 0.5) color=creator_11_paintVisual(uv,f);
  if (abs(uVisualIndex - 12.0) < 0.5) color=creator_12_paintVisual(uv,f);
  if (abs(uVisualIndex - 13.0) < 0.5) color=creator_13_paintVisual(uv,f);
  if (abs(uVisualIndex - 14.0) < 0.5) color=creator_14_paintVisual(uv,f);
  if (abs(uVisualIndex - 15.0) < 0.5) color=creator_15_paintVisual(uv,f);
  if (abs(uVisualIndex - 16.0) < 0.5) color=creator_16_paintVisual(uv,f);
  if (abs(uVisualIndex - 17.0) < 0.5) color=creator_17_paintVisual(uv,f);
  if (abs(uVisualIndex - 18.0) < 0.5) color=creator_18_paintVisual(uv,f);
  if (abs(uVisualIndex - 19.0) < 0.5) color=creator_19_paintVisual(uv,f);
  if (abs(uVisualIndex - 20.0) < 0.5) color=creator_20_paintVisual(uv,f);
  if (abs(uVisualIndex - 21.0) < 0.5) color=creator_21_paintVisual(uv,f);
  if (abs(uVisualIndex - 22.0) < 0.5) color=creator_22_paintVisual(uv,f);
  if (abs(uVisualIndex - 23.0) < 0.5) color=creator_23_paintVisual(uv,f);
  if (abs(uVisualIndex - 24.0) < 0.5) color=creator_24_paintVisual(uv,f);
  if (abs(uVisualIndex - 25.0) < 0.5) color=creator_25_paintVisual(uv,f);
  if (abs(uVisualIndex - 26.0) < 0.5) color=creator_26_paintVisual(uv,f);
  if (abs(uVisualIndex - 27.0) < 0.5) color=creator_27_paintVisual(uv,f);
  if (abs(uVisualIndex - 28.0) < 0.5) color=creator_28_paintVisual(uv,f);
  if (abs(uVisualIndex - 29.0) < 0.5) color=creator_29_paintVisual(uv,f);
  if (abs(uVisualIndex - 30.0) < 0.5) color=creator_30_paintVisual(uv,f);
  if (abs(uVisualIndex - 31.0) < 0.5) color=creator_31_paintVisual(uv,f);
  if (abs(uVisualIndex - 32.0) < 0.5) color=creator_32_paintVisual(uv,f);
  if (abs(uVisualIndex - 33.0) < 0.5) color=creator_33_paintVisual(uv,f);
  if (abs(uVisualIndex - 34.0) < 0.5) color=creator_34_paintVisual(uv,f);
  if (abs(uVisualIndex - 35.0) < 0.5) color=creator_35_paintVisual(uv,f);
  if (abs(uVisualIndex - 36.0) < 0.5) color=creator_36_paintVisual(uv,f);
  if (abs(uVisualIndex - 37.0) < 0.5) color=creator_37_paintVisual(uv,f);
  if (abs(uVisualIndex - 38.0) < 0.5) color=creator_38_paintVisual(uv,f);
  if (abs(uVisualIndex - 39.0) < 0.5) color=creator_39_paintVisual(uv,f);
  if (abs(uVisualIndex - 40.0) < 0.5) color=creator_40_paintVisual(uv,f);
  if (abs(uVisualIndex - 41.0) < 0.5) color=creator_41_paintVisual(uv,f);
  if (abs(uVisualIndex - 42.0) < 0.5) color=creator_42_paintVisual(uv,f);
  if (abs(uVisualIndex - 43.0) < 0.5) color=creator_43_paintVisual(uv,f);
  if (abs(uVisualIndex - 44.0) < 0.5) color=creator_44_paintVisual(uv,f);
  if (abs(uVisualIndex - 45.0) < 0.5) color=creator_45_paintVisual(uv,f);
  if (abs(uVisualIndex - 46.0) < 0.5) color=creator_46_paintVisual(uv,f);
  if (abs(uVisualIndex - 47.0) < 0.5) color=creator_47_paintVisual(uv,f);
  if (abs(uVisualIndex - 48.0) < 0.5) color=creator_48_paintVisual(uv,f);
  if (abs(uVisualIndex - 49.0) < 0.5) color=creator_49_paintVisual(uv,f);
  if (abs(uVisualIndex - 50.0) < 0.5) color=creator_50_paintVisual(uv,f);
  if (abs(uVisualIndex - 51.0) < 0.5) color=creator_51_paintVisual(uv,f);
  if (abs(uVisualIndex - 52.0) < 0.5) color=creator_52_paintVisual(uv,f);
  if (abs(uVisualIndex - 53.0) < 0.5) color=creator_53_paintVisual(uv,f);
  if (abs(uVisualIndex - 54.0) < 0.5) color=creator_54_paintVisual(uv,f);
  if (abs(uVisualIndex - 55.0) < 0.5) color=creator_55_paintVisual(uv,f);
  if (abs(uVisualIndex - 56.0) < 0.5) color=creator_56_paintVisual(uv,f);
  if (abs(uVisualIndex - 57.0) < 0.5) color=creator_57_paintVisual(uv,f);
  if (abs(uVisualIndex - 58.0) < 0.5) color=creator_58_paintVisual(uv,f);
  if (abs(uVisualIndex - 59.0) < 0.5) color=creator_59_paintVisual(uv,f);
  if (abs(uVisualIndex - 60.0) < 0.5) color=creator_60_paintVisual(uv,f);
  if (abs(uVisualIndex - 61.0) < 0.5) color=creator_61_paintVisual(uv,f);
  if (abs(uVisualIndex - 62.0) < 0.5) color=creator_62_paintVisual(uv,f);
  if (abs(uVisualIndex - 63.0) < 0.5) color=creator_63_paintVisual(uv,f);
  if (abs(uVisualIndex - 64.0) < 0.5) color=creator_64_paintVisual(uv,f);
  if (abs(uVisualIndex - 65.0) < 0.5) color=creator_65_paintVisual(uv,f);
  if (abs(uVisualIndex - 66.0) < 0.5) color=creator_66_paintVisual(uv,f);
  if (abs(uVisualIndex - 67.0) < 0.5) color=creator_67_paintVisual(uv,f);
  if (abs(uVisualIndex - 68.0) < 0.5) color=creator_68_paintVisual(uv,f);
  if (abs(uVisualIndex - 69.0) < 0.5) color=creator_69_paintVisual(uv,f);
  if (abs(uVisualIndex - 70.0) < 0.5) color=creator_70_paintVisual(uv,f);
  if (abs(uVisualIndex - 71.0) < 0.5) color=creator_71_paintVisual(uv,f);
  if (abs(uVisualIndex - 72.0) < 0.5) color=creator_72_paintVisual(uv,f);
  if (abs(uVisualIndex - 73.0) < 0.5) color=creator_73_paintVisual(uv,f);
  if (abs(uVisualIndex - 74.0) < 0.5) color=creator_74_paintVisual(uv,f);
  if (abs(uVisualIndex - 75.0) < 0.5) color=creator_75_paintVisual(uv,f);
  if (abs(uVisualIndex - 76.0) < 0.5) color=creator_76_paintVisual(uv,f);
  if (abs(uVisualIndex - 77.0) < 0.5) color=creator_77_paintVisual(uv,f);
  if (abs(uVisualIndex - 78.0) < 0.5) color=creator_78_paintVisual(uv,f);
  if (abs(uVisualIndex - 79.0) < 0.5) color=creator_79_paintVisual(uv,f);
  if (abs(uVisualIndex - 80.0) < 0.5) color=creator_80_paintVisual(uv,f);
  if (abs(uVisualIndex - 81.0) < 0.5) color=creator_81_paintVisual(uv,f);
  if (abs(uVisualIndex - 82.0) < 0.5) color=creator_82_paintVisual(uv,f);
  if (abs(uVisualIndex - 83.0) < 0.5) color=creator_83_paintVisual(uv,f);
  if (abs(uVisualIndex - 84.0) < 0.5) color=creator_84_paintVisual(uv,f);
  if (abs(uVisualIndex - 85.0) < 0.5) color=creator_85_paintVisual(uv,f);
  if (abs(uVisualIndex - 86.0) < 0.5) color=creator_86_paintVisual(uv,f);
  if (abs(uVisualIndex - 87.0) < 0.5) color=creator_87_paintVisual(uv,f);
  if (abs(uVisualIndex - 88.0) < 0.5) color=creator_88_paintVisual(uv,f);
  if (abs(uVisualIndex - 89.0) < 0.5) color=creator_89_paintVisual(uv,f);
  if (abs(uVisualIndex - 90.0) < 0.5) color=creator_90_paintVisual(uv,f);
  if (abs(uVisualIndex - 91.0) < 0.5) color=creator_91_paintVisual(uv,f);
  if (abs(uVisualIndex - 92.0) < 0.5) color=creator_92_paintVisual(uv,f);
  if (abs(uVisualIndex - 93.0) < 0.5) color=creator_93_paintVisual(uv,f);
  if (abs(uVisualIndex - 94.0) < 0.5) color=creator_94_paintVisual(uv,f);
  if (abs(uVisualIndex - 95.0) < 0.5) color=creator_95_paintVisual(uv,f);
  if (abs(uVisualIndex - 96.0) < 0.5) color=creator_96_paintVisual(uv,f);
  if (abs(uVisualIndex - 97.0) < 0.5) color=creator_97_paintVisual(uv,f);
  if (abs(uVisualIndex - 98.0) < 0.5) color=creator_98_paintVisual(uv,f);
  if (abs(uVisualIndex - 99.0) < 0.5) color=creator_99_paintVisual(uv,f);
  if (abs(uVisualIndex - 100.0) < 0.5) color=creator_100_paintVisual(uv,f);
  if (abs(uVisualIndex - 101.0) < 0.5) color=creator_101_paintVisual(uv,f);
  if (abs(uVisualIndex - 102.0) < 0.5) color=creator_102_paintVisual(uv,f);
  if (abs(uVisualIndex - 103.0) < 0.5) color=creator_103_paintVisual(uv,f);
  if (abs(uVisualIndex - 104.0) < 0.5) color=creator_104_paintVisual(uv,f);
  if (abs(uVisualIndex - 105.0) < 0.5) color=creator_105_paintVisual(uv,f);
  if (abs(uVisualIndex - 106.0) < 0.5) color=creator_106_paintVisual(uv,f);
  if (abs(uVisualIndex - 107.0) < 0.5) color=creator_107_paintVisual(uv,f);
  if (abs(uVisualIndex - 108.0) < 0.5) color=creator_108_paintVisual(uv,f);
  if (abs(uVisualIndex - 109.0) < 0.5) color=creator_109_paintVisual(uv,f);
  if (abs(uVisualIndex - 110.0) < 0.5) color=creator_110_paintVisual(uv,f);
  if (abs(uVisualIndex - 111.0) < 0.5) color=creator_111_paintVisual(uv,f);
  if (abs(uVisualIndex - 112.0) < 0.5) color=creator_112_paintVisual(uv,f);
  if (abs(uVisualIndex - 113.0) < 0.5) color=creator_113_paintVisual(uv,f);
  if (abs(uVisualIndex - 114.0) < 0.5) color=creator_114_paintVisual(uv,f);
  if (abs(uVisualIndex - 115.0) < 0.5) color=creator_115_paintVisual(uv,f);
  if (abs(uVisualIndex - 116.0) < 0.5) color=creator_116_paintVisual(uv,f);
  if (abs(uVisualIndex - 117.0) < 0.5) color=creator_117_paintVisual(uv,f);
  if (abs(uVisualIndex - 118.0) < 0.5) color=creator_118_paintVisual(uv,f);
  if (abs(uVisualIndex - 119.0) < 0.5) color=creator_119_paintVisual(uv,f);
  if (abs(uVisualIndex - 120.0) < 0.5) color=creator_120_paintVisual(uv,f);
  if (abs(uVisualIndex - 121.0) < 0.5) color=creator_121_paintVisual(uv,f);
  if (abs(uVisualIndex - 122.0) < 0.5) color=creator_122_paintVisual(uv,f);
  if (abs(uVisualIndex - 123.0) < 0.5) color=creator_123_paintVisual(uv,f);
  if (abs(uVisualIndex - 124.0) < 0.5) color=creator_124_paintVisual(uv,f);
  if (abs(uVisualIndex - 125.0) < 0.5) color=creator_125_paintVisual(uv,f);
  if (abs(uVisualIndex - 126.0) < 0.5) color=creator_126_paintVisual(uv,f);
  if (abs(uVisualIndex - 127.0) < 0.5) color=creator_127_paintVisual(uv,f);
  if (abs(uVisualIndex - 128.0) < 0.5) color=creator_128_paintVisual(uv,f);
  if (abs(uVisualIndex - 129.0) < 0.5) color=creator_129_paintVisual(uv,f);
  if (abs(uVisualIndex - 130.0) < 0.5) color=creator_130_paintVisual(uv,f);
  if (abs(uVisualIndex - 131.0) < 0.5) color=creator_131_paintVisual(uv,f);
  if (abs(uVisualIndex - 132.0) < 0.5) color=creator_132_paintVisual(uv,f);
  if (abs(uVisualIndex - 133.0) < 0.5) color=creator_133_paintVisual(uv,f);
  if (abs(uVisualIndex - 134.0) < 0.5) color=creator_134_paintVisual(uv,f);
  if (abs(uVisualIndex - 135.0) < 0.5) color=creator_135_paintVisual(uv,f);
  if (abs(uVisualIndex - 136.0) < 0.5) color=creator_136_paintVisual(uv,f);
  if (abs(uVisualIndex - 137.0) < 0.5) color=creator_137_paintVisual(uv,f);
  if (abs(uVisualIndex - 138.0) < 0.5) color=creator_138_paintVisual(uv,f);
  if (abs(uVisualIndex - 139.0) < 0.5) color=creator_139_paintVisual(uv,f);
  if (abs(uVisualIndex - 140.0) < 0.5) color=creator_140_paintVisual(uv,f);
  if (abs(uVisualIndex - 141.0) < 0.5) color=creator_141_paintVisual(uv,f);
  if (abs(uVisualIndex - 142.0) < 0.5) color=creator_142_paintVisual(uv,f);
  if (abs(uVisualIndex - 143.0) < 0.5) color=creator_143_paintVisual(uv,f);
  if (abs(uVisualIndex - 144.0) < 0.5) color=creator_144_paintVisual(uv,f);
  if (abs(uVisualIndex - 145.0) < 0.5) color=creator_145_paintVisual(uv,f);
  if (abs(uVisualIndex - 146.0) < 0.5) color=creator_146_paintVisual(uv,f);
  if (abs(uVisualIndex - 147.0) < 0.5) color=creator_147_paintVisual(uv,f);
  if (abs(uVisualIndex - 148.0) < 0.5) color=creator_148_paintVisual(uv,f);
  if (abs(uVisualIndex - 149.0) < 0.5) color=creator_149_paintVisual(uv,f);
  if (abs(uVisualIndex - 150.0) < 0.5) color=creator_150_paintVisual(uv,f);
  if (abs(uVisualIndex - 151.0) < 0.5) color=creator_151_paintVisual(uv,f);
  if (abs(uVisualIndex - 152.0) < 0.5) color=creator_152_paintVisual(uv,f);
  if (abs(uVisualIndex - 153.0) < 0.5) color=creator_153_paintVisual(uv,f);
  if (abs(uVisualIndex - 154.0) < 0.5) color=creator_154_paintVisual(uv,f);
  if (abs(uVisualIndex - 155.0) < 0.5) color=creator_155_paintVisual(uv,f);
  if (abs(uVisualIndex - 156.0) < 0.5) color=creator_156_paintVisual(uv,f);
  if (abs(uVisualIndex - 157.0) < 0.5) color=creator_157_paintVisual(uv,f);
  if (abs(uVisualIndex - 158.0) < 0.5) color=creator_158_paintVisual(uv,f);
  if (abs(uVisualIndex - 159.0) < 0.5) color=creator_159_paintVisual(uv,f);
  if (abs(uVisualIndex - 160.0) < 0.5) color=creator_160_paintVisual(uv,f);
  if (abs(uVisualIndex - 161.0) < 0.5) color=creator_161_paintVisual(uv,f);
  if (abs(uVisualIndex - 162.0) < 0.5) color=creator_162_paintVisual(uv,f);
  if (abs(uVisualIndex - 163.0) < 0.5) color=creator_163_paintVisual(uv,f);
  if (abs(uVisualIndex - 164.0) < 0.5) color=creator_164_paintVisual(uv,f);
  if (abs(uVisualIndex - 165.0) < 0.5) color=creator_165_paintVisual(uv,f);
  if (abs(uVisualIndex - 166.0) < 0.5) color=creator_166_paintVisual(uv,f);
  if (abs(uVisualIndex - 167.0) < 0.5) color=creator_167_paintVisual(uv,f);
  if (abs(uVisualIndex - 168.0) < 0.5) color=creator_168_paintVisual(uv,f);
  if (abs(uVisualIndex - 169.0) < 0.5) color=creator_169_paintVisual(uv,f);
  if (abs(uVisualIndex - 170.0) < 0.5) color=creator_170_paintVisual(uv,f);
  if (abs(uVisualIndex - 171.0) < 0.5) color=creator_171_paintVisual(uv,f);
  if (abs(uVisualIndex - 172.0) < 0.5) color=creator_172_paintVisual(uv,f);
  if (abs(uVisualIndex - 173.0) < 0.5) color=creator_173_paintVisual(uv,f);
  if (abs(uVisualIndex - 174.0) < 0.5) color=creator_174_paintVisual(uv,f);
  if (abs(uVisualIndex - 175.0) < 0.5) color=creator_175_paintVisual(uv,f);
  if (abs(uVisualIndex - 176.0) < 0.5) color=creator_176_paintVisual(uv,f);
  if (abs(uVisualIndex - 177.0) < 0.5) color=creator_177_paintVisual(uv,f);
  if (abs(uVisualIndex - 178.0) < 0.5) color=creator_178_paintVisual(uv,f);
  if (abs(uVisualIndex - 179.0) < 0.5) color=creator_179_paintVisual(uv,f);
  if (any(isnan(color)) || any(isinf(color))) color=vec4(0.0);
  color=clamp(color,0.0,1.0);
  fragColor=vec4(color.rgb*color.a,color.a);
}
