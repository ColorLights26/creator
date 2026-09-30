// Campo de Plasma — port de la galería immersive a escena nativa.
// Niebla de color en movimiento continuo mediante material GLSL.
const nativeSource = r'''
class Visual final : public Scene {
  float smoothBass = 0.0f;
 public:
  void reset(uint32_t seed) override { (void)seed; smoothBass = 0.0f; }
  void update(const Frame& f) override {
    smoothBass += (f.music.bass - smoothBass) * float(1.0 - std::exp(-f.delta * 8.0));
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    c.material("plasma", {0, 0, w, h}, {float(f.time) * f.speed, smoothBass});
    Paint shade = Paint::radial({w * 0.5f, h * 0.5f}, h * 0.75f,
      {{0, 0, 0, 0}, {0, 0, 0, 0.6f}}, {0, 1.0f});
    c.rect({0, 0, w, h}, shade);
  }
};
''';

const shaderSources = <String, String>{
  'plasma': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uBass;
out vec4 fragColor;
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = (uv - 0.5) * vec2(uSize.x / uSize.y, 1.0);
  float t = uTime;
  float bassMod = 1.0 + clamp(uBass, 0.0, 1.0) * 0.45;
  float v = sin(p.x * 6.0 + t * 0.9) + sin(p.y * 5.0 - t * 1.1)
    + sin((p.x + p.y) * 4.0 + t * 0.6) + sin(length(p) * 8.0 - t * 1.6) * bassMod;
  float k = clamp((v + 3.0 + bassMod) / (6.0 + 2.0 * bassMod), 0.0, 1.0);
  vec3 col = mix(vec3(0.0, 0.07, 0.12), vec3(0.0, 0.76, 0.70), smoothstep(0.0, 0.4, k));
  col = mix(col, vec3(1.0, 0.85, 0.24), smoothstep(0.4, 0.7, k));
  col = mix(col, vec3(1.0, 0.18, 0.73), smoothstep(0.7, 1.0, k));
  fragColor = vec4(col, 1.0);
}
""",
};
