// Cromo Líquido — port de la galería immersive a escena nativa.
// Campo escalar de metaballs resuelto por píxel en un material, con la misma
// LUT de siete paradas que la galería original.
const nativeSource = r'''
class Visual final : public Scene {
  struct Blob { float radius, p1, p2, sx, sy; };
  std::vector<Blob> blobs;
  float simTime = 0.0f;
  float energy = 0.0f;
  float smoothBass = 0.0f;
 public:
  void reset(uint32_t seed) override {
    Random rng(seed); blobs.clear(); simTime = 0.0f; energy = 0.0f; smoothBass = 0.0f;
    for (int i = 0; i < 7; i++)
      blobs.push_back({0.14f + rng.unit() * 0.13f,
        rng.unit() * 6.2831853f, rng.unit() * 6.2831853f,
        0.23f + float(i) * 0.045f, 0.19f + float(i) * 0.037f});
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    energy += (targetEnergy - energy) * float(1.0 - std::exp(-dt * 5.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 7.0));

    // En silencio reposa en un movimiento líquido pausado y zen (~0.09f).
    // Con música acelera la órbita de las metaballs y pulsa su volumen.
    float audioDrive = 0.09f + energy * 0.75f + smoothBass * 0.35f;
    simTime += dt * f.speed * audioDrive;
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = simTime;
    Paint bg; bg.color = Color::argb(0xff03000c);
    c.rect({0, 0, w, h}, bg);
    std::vector<float> u;
    u.reserve(64);
    u.push_back(t);
    u.push_back(std::clamp(smoothBass, 0.0f, 1.0f));
    u.push_back(std::clamp(energy * f.intensity, 0.0f, 1.0f));
    u.push_back(f.glow);
    float radiusExpansion = 1.0f + smoothBass * 0.38f + energy * 0.15f;
    for (const auto& b : blobs) {
      u.push_back(w * (0.5f + std::sin(t * b.sx + b.p1) * 0.33f));
      u.push_back(h * (0.5f + std::sin(t * b.sy + b.p2) * 0.36f));
      u.push_back(b.radius * w * radiusExpansion);
    }
    c.material("chrome", {0, 0, w, h}, u);
    Paint shade = Paint::radial({w * 0.5f, h * 0.5f}, std::max(w, h) * 0.75f,
      {{0, 0, 0, 0}, {0, 0, 0, 0.45f}}, {0.55f, 1.0f});
    c.rect({0, 0, w, h}, shade);
  }
};
''';

const shaderSources = <String, String>{
  'chrome': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uBass;
uniform float uEnergy;
uniform float uGlow;
uniform vec2 uBlob0;
uniform float uRad0;
uniform vec2 uBlob1;
uniform float uRad1;
uniform vec2 uBlob2;
uniform float uRad2;
uniform vec2 uBlob3;
uniform float uRad3;
uniform vec2 uBlob4;
uniform float uRad4;
uniform vec2 uBlob5;
uniform float uRad5;
uniform vec2 uBlob6;
uniform float uRad6;
out vec4 fragColor;
void main() {
  vec2 uv = FlutterFragCoord().xy;
  float f = 0.0;
  f += uRad0*uRad0 / (dot(uv-uBlob0, uv-uBlob0) + 24.0);
  f += uRad1*uRad1 / (dot(uv-uBlob1, uv-uBlob1) + 24.0);
  f += uRad2*uRad2 / (dot(uv-uBlob2, uv-uBlob2) + 24.0);
  f += uRad3*uRad3 / (dot(uv-uBlob3, uv-uBlob3) + 24.0);
  f += uRad4*uRad4 / (dot(uv-uBlob4, uv-uBlob4) + 24.0);
  f += uRad5*uRad5 / (dot(uv-uBlob5, uv-uBlob5) + 24.0);
  f += uRad6*uRad6 / (dot(uv-uBlob6, uv-uBlob6) + 24.0);
  f *= 0.55 * (1.0 + uBass * 0.35);
  float v = f / (1.0 + f);
  float k = clamp(v, 0.0, 1.0);
  vec3 col;
  if (k < 0.16) col = mix(vec3(0.012, 0.0, 0.047), vec3(0.078, 0.039, 0.227), k / 0.16);
  else if (k < 0.33) col = mix(vec3(0.078, 0.039, 0.227), vec3(0.231, 0.071, 0.627), (k-0.16)/0.17);
  else if (k < 0.50) col = mix(vec3(0.231, 0.071, 0.627), vec3(0.541, 0.169, 0.886), (k-0.33)/0.17);
  else if (k < 0.68) col = mix(vec3(0.541, 0.169, 0.886), vec3(1.0, 0.243, 0.647), (k-0.50)/0.18);
  else if (k < 0.86) col = mix(vec3(1.0, 0.243, 0.647), vec3(1.0, 0.820, 0.953), (k-0.68)/0.18);
  else col = mix(vec3(1.0, 0.820, 0.953), vec3(1.0), (k-0.86)/0.14);
  float spec = pow(max(0.0, k - 0.55) * 2.2, 3.0);
  col += vec3(0.55, 0.45, 0.60) * spec * uGlow;
  fragColor = vec4(clamp(col * (0.85 + 0.30 * uEnergy), 0.0, 1.0), 1.0);
}
""",
};
