// Deriva de Julia Transparente — versión overlay con alfa en el fractal.
const nativeSource = r'''
class Visual final : public Scene {
  float phase = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothBass = 0.0f;
  float smoothSpark = 0.0f;
 public:
  void reset(uint32_t seed) override {
    (void)seed;
    phase = 0.0f;
    smoothEnergy = 0.0f;
    smoothBass = 0.0f;
    smoothSpark = 0.0f;
  }
  void update(const Frame& f) override {
    float dt = float(f.delta);
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    float targetSpark = f.music.active ? f.music.spark : 0.0f;
    smoothEnergy += (targetEnergy - smoothEnergy) * float(1.0 - std::exp(-dt * 6.0));
    smoothBass += (targetBass - smoothBass) * float(1.0 - std::exp(-dt * 8.0));
    smoothSpark += (targetSpark - smoothSpark) * float(1.0 - std::exp(-dt * 12.0));

    // En silencio reposa en un planeo zen majestuoso (~0.08f).
    // Con música la velocidad responde en tiempo real a la energía y bombos.
    float audioDrive = 0.08f + smoothEnergy * 0.72f + smoothBass * 0.35f;
    phase += dt * f.speed * audioDrive;
  }
  void render(const Frame& f, Canvas& c) const override {
    float w = f.width, h = f.height;
    float time = phase * 6.2831853f;

    // Deformación del atractor de Julia según el bajo rítmico
    float bassDeform = smoothBass * 0.075f;
    float cx = 0.7885f * std::cos(time * 0.17f) + bassDeform * std::sin(time * 0.45f);
    float cy = 0.7885f * std::sin(time * 0.23f) - bassDeform * std::cos(time * 0.45f);

    // Zoom pulsante ante bombos y sub-graves
    float baseZoom = 1.32f + std::sin(time * 0.06f) * 0.04f;
    float zoomPulse = smoothBass * 0.28f;
    float currentZoom = baseZoom * (1.0f - zoomPulse);

    // Iteraciones adaptativas: menos pasos cuanto más densa es la pantalla.
    float px = w * h;
    float maxIter = px > 3.0e6f ? 48.0f : (px > 1.0e6f ? 72.0f : 96.0f);

    float uAudio = std::clamp((smoothEnergy * 0.7f + smoothBass * 0.5f) * f.intensity, 0.0f, 1.0f);
    float uSpark = std::clamp(smoothSpark * f.intensity, 0.0f, 1.0f);

    std::vector<float> u;
    u.reserve(8);
    u.push_back(cx);
    u.push_back(cy);
    u.push_back(time);
    u.push_back(currentZoom);
    u.push_back(maxIter);
    u.push_back(uAudio);
    u.push_back(uSpark);
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
uniform float uAudio;
uniform float uSpark;
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
    fragColor = vec4(0.0);
    return;
  }
  float sl = i - log2(max(1e-4, log2(max(1.0001, m2))));
  vec3 col = palette(sl * 0.012 + uTime * 0.02);

  // Realce reactivo al audio: filamentos interiores y resplandor de chispas
  float filament = exp(-abs(sl - 14.0) * 0.28) * uAudio * 0.65;
  vec3 glowColor = vec3(0.4, 0.85, 1.0) * filament;
  float sparkShimmer = exp(-abs(sl - 28.0) * 0.35) * uSpark * 0.5;
  vec3 sparkColor = vec3(1.0, 0.75, 0.3) * sparkShimmer;
  col = col * (0.85 + 0.30 * uAudio) + glowColor + sparkColor;

  float d = length(uv - 0.5);
  float alpha = smoothstep(1.5, 8.0, sl) * smoothstep(0.95, 0.25, d);
  fragColor = vec4(clamp(pow(col, vec3(0.85)), 0.0, 1.0) * alpha, alpha);
}
""",
};
