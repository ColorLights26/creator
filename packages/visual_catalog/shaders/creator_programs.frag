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

vec4 creator_1_paintVisual(vec2 uv, CreatorFrame f) {
  vec2 p = (uv - 0.5) * vec2(f.size.x / max(f.size.y, 1.0), 1.0);
  float radius = 0.27 + 0.015 * sin(f.time * f.speed) + 0.025 * f.bass;
  float distance = abs(length(p) - radius);
  float beam = exp(-distance * distance * 17000.0);
  float halo = exp(-distance * 24.0) * 0.25 * f.glow;
  float alpha = clamp((beam * 0.62 + halo) * f.intensity * (0.8 + 0.2 * f.pulse), 0.0, 1.0);
  vec3 ink = mix(f.color1.rgb, f.color2.rgb, 0.5 + 0.5 * sin(p.x * 7.0 + f.time * 0.2));
  return vec4(ink, alpha);
}

vec4 creator_2_paintVisual(vec2 uv, CreatorFrame f) {
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
  if (any(isnan(color)) || any(isinf(color))) color=vec4(0.0);
  color=clamp(color,0.0,1.0);
  fragColor=vec4(color.rgb*color.a,color.a);
}
