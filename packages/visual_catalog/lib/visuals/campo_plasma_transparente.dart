// Campo de Plasma Transparente — versión overlay con alfa por onda.
const nativeSource = r'''
class Visual final : public Scene {
  float plasmaTime = 0.0f;
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    plasmaTime = 0.0f;
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 6.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 8.0));

    // En silencio reposa en un flujo suave y relajante (~0.09f).
    // Con música acelera vigorosamente con los ritmos y bombos.
    float audioDrive = 0.09f + smoothEnergy * 0.76f + smoothBass * 0.35f;
    plasmaTime += dt * f.speed * audioDrive;
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float uEnergy = std::clamp(smoothEnergy * f.intensity, 0.0f, 1.0f);
    c.material("plasma", {0, 0, w, h}, {plasmaTime, std::clamp(smoothBass, 0.0f, 1.0f), uEnergy});
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
uniform float uEnergy;
out vec4 fragColor;
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = (uv - 0.5) * vec2(uSize.x / uSize.y, 1.0);
  float t = uTime;
  float bassMod = 1.0 + clamp(uBass, 0.0, 1.0) * 0.85;
  float v = sin(p.x * 6.0 + t * 0.9) + sin(p.y * 5.0 - t * 1.1)
    + sin((p.x + p.y) * 4.0 + t * 0.6) + sin(length(p) * 8.0 - t * 1.6) * bassMod;
  float k = clamp((v + 3.0 + bassMod) / (6.0 + 2.0 * bassMod), 0.0, 1.0);
  vec3 col = mix(vec3(0.0, 0.07, 0.12), vec3(0.0, 0.76, 0.70), smoothstep(0.0, 0.4, k));
  col = mix(col, vec3(1.0, 0.85, 0.24), smoothstep(0.4, 0.7, k));
  col = mix(col, vec3(1.0, 0.18, 0.73), smoothstep(0.7, 1.0, k));
  col = col * (0.80 + 0.35 * uEnergy);
  float alpha = smoothstep(0.40, 0.70, k);
  fragColor = vec4(clamp(col * alpha, 0.0, 1.0), alpha);
}
""",
};
