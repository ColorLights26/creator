// Tinta en Agua — puerto de la galería FLUX/10 al motor nativo.
// Doce metaballs fundiéndose: el campo escalar se evalúa por píxel en un
// material de la GPU y Dart sólo escribe 38 uniformes por fotograma.
const nativeSource = r'''
class Visual final : public Scene {
  static const int nb = 12;
  struct Blob { float ang, spd, rad; };
  std::vector<Blob> blobs;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    blobs.clear(); blobs.reserve(nb);
    for (int i = 0; i < nb; i++) {
      Blob b;
      b.ang = rng.unit() * 6.2831853f;
      b.spd = 0.12f + rng.unit() * 0.3f;
      b.rad = 0.06f + rng.unit() * 0.12f;
      blobs.push_back(b);
    }
  }
  void update(const Frame& f) override { (void)f; }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    float time = t * 6.2831853f;
    float pull = 1.0f + f.music.energy * 0.9f + f.music.bass * 0.5f;
    std::vector<float> u;
    u.reserve(40);
    u.push_back(time);
    u.push_back(pull);
    for (int i = 0; i < nb; i++) {
      const Blob& b = blobs[i];
      float a = b.ang + time * b.spd * (i % 2 == 0 ? 1.0f : -1.0f);
      float rr = b.rad * (1.0f + 0.28f * std::sin(time * 0.6f + float(i)));
      u.push_back(w * (0.5f + std::cos(a) * (0.26f + rr)));
      u.push_back(h * (0.5f + std::sin(a * 1.27f + float(i)) * (0.3f + rr)));
      u.push_back(rr * (1.0f + (pull - 1.0f) * 0.22f) * std::min(w, h));
    }
    c.material("ink", {0, 0, w, h}, u);
  }
};
''';

const shaderSources = <String, String>{
  'ink': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uPull;
uniform vec2 uB0;
uniform vec2 uB1;
uniform vec2 uB2;
uniform vec2 uB3;
uniform vec2 uB4;
uniform vec2 uB5;
uniform vec2 uB6;
uniform vec2 uB7;
uniform vec2 uB8;
uniform vec2 uB9;
uniform vec2 uB10;
uniform vec2 uB11;
uniform float uR0;
uniform float uR1;
uniform float uR2;
uniform float uR3;
uniform float uR4;
uniform float uR5;
uniform float uR6;
uniform float uR7;
uniform float uR8;
uniform float uR9;
uniform float uR10;
uniform float uR11;
out vec4 fragColor;
float field(vec2 d, float r) { return (r * r) / (dot(d, d) + 0.0006); }
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize.xy;
  float aspect = uSize.x / uSize.y;
  vec2 p = vec2(uv.x * aspect, uv.y);
  float f = 0.0;
  f += field(p - uB0, uR0);
  f += field(p - uB1, uR1);
  f += field(p - uB2, uR2);
  f += field(p - uB3, uR3);
  f += field(p - uB4, uR4);
  f += field(p - uB5, uR5);
  f += field(p - uB6, uR6);
  f += field(p - uB7, uR7);
  f += field(p - uB8, uR8);
  f += field(p - uB9, uR9);
  f += field(p - uB10, uR10);
  f += field(p - uB11, uR11);
  float k = clamp((f * (0.02 * uPull) - 0.55) * 1.5, 0.0, 1.0);
  float veins = 0.5 + 0.5 * sin(f * 26.0 + uTime * 1.4);
  vec3 deep = vec3(0.02, 0.05, 0.11);
  vec3 midc = vec3(0.05, 0.55, 0.62);
  vec3 bright = vec3(0.55, 0.95, 0.94);
  vec3 col = mix(mix(deep, midc, smoothstep(0.0, 0.55, k)), bright, smoothstep(0.6, 1.0, k));
  col *= 0.82 + 0.18 * veins;
  float edge = smoothstep(0.42, 0.6, k) * (1.0 - smoothstep(0.6, 0.82, k));
  col += vec3(0.9, 1.0, 1.0) * edge * 0.25;
  fragColor = vec4(col, 1.0);
}
""",
};
