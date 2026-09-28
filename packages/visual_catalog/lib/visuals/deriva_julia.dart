// Deriva de Julia — puerto de la galería FLUX/10 al motor nativo.
// El conjunto se itera por píxel en la GPU: el fotograma de la escena sólo
// escribe seis uniformes. Zoom e iteraciones se adaptan a la densidad.
const nativeSource = r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t seed) override { (void)seed; }
  void update(const Frame& f) override { (void)f; }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float t = float(f.time) * f.speed;
    float time = t * 6.2831853f;
    float pull = f.music.energy;
    std::vector<float> u;
    u.reserve(8);
    u.push_back(0.7885f * std::cos(time * 0.17f) + pull * 0.09f);
    u.push_back(0.7885f * std::sin(time * 0.23f) - pull * 0.09f);
    u.push_back(time);
    u.push_back(1.35f + std::sin(time * 0.11f) * 0.22f);
    // Iteraciones adaptativas: menos pasos cuanto más densa es la pantalla.
    float px = w * h;
    u.push_back(px > 3.0e6f ? 48.0f : (px > 1.0e6f ? 72.0f : 96.0f));
    c.material("julia", {0, 0, w, h}, u);
  }
};
''';

const shaderSources = <String, String>{
  'julia': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uC;
uniform float uTime;
uniform float uZoom;
uniform float uMaxIter;
out vec4 fragColor;
vec3 palette(float t) {
  return 0.5 + 0.5 * cos(6.28318 * (vec3(1.0, 0.9, 0.8) * t + vec3(0.02, 0.18, 0.34)));
}
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize.xy;
  float aspect = uSize.x / uSize.y;
  vec2 z = (uv * 2.0 - 1.0) * vec2(uZoom * aspect, uZoom);
  float i = 0.0;
  float m2 = 0.0;
  for (int k = 0; k < 96; k++) {
    if (float(k) >= uMaxIter || m2 > 6.0) break;
    z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + uC;
    m2 = dot(z, z);
    i += 1.0;
  }
  if (i >= uMaxIter) {
    fragColor = vec4(0.02, 0.015, 0.04, 1.0);
    return;
  }
  float sl = i - log2(max(1e-4, log2(max(1.0, m2))));
  vec3 col = palette(sl * 0.012 + uTime * 0.02);
  float d = length(uv - 0.5);
  col *= smoothstep(0.95, 0.25, d);
  fragColor = vec4(pow(col, vec3(0.85)), 1.0);
}
""",
};
