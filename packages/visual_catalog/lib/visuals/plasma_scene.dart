// Campo de Plasma: síntesis procedural acelerada por GPU y modulada por audio.
// Metadata en el archivo compañero plasma_scene_metadata.dart.
const nativeSource = r'''
class Visual final : public Scene {
  float smoothBass = 0.0f;
  float smoothEnergy = 0.0f;
  float smoothSpark = 0.0f;
  float plasmaTime = 0.0f;
  float ripplePhase = 0.0f;
  float colorPhase = 0.0f;

 public:
  void reset(uint32_t) override {
    smoothBass = 0.0f;
    smoothEnergy = 0.0f;
    smoothSpark = 0.0f;
    plasmaTime = 0.0f;
    ripplePhase = 0.0f;
    colorPhase = 0.0f;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (dt > 0.1f) dt = 0.1f;

    // Filtro exponencial asimétrico para respuesta musical orgánica sin tirones
    float targetBass = f.music.active ? f.music.bass : 0.0f;
    float targetEnergy = f.music.active ? f.music.energy : 0.0f;
    float targetSpark = f.music.active ? f.music.spark : 0.0f;

    float bassRate = targetBass > smoothBass ? 16.0f : 4.5f;
    smoothBass += (targetBass - smoothBass) * (1.0f - std::exp(-dt * bassRate));
    smoothEnergy += (targetEnergy - smoothEnergy) * (1.0f - std::exp(-dt * 5.0f));
    smoothSpark += (targetSpark - smoothSpark) * (1.0f - std::exp(-dt * 10.0f));

    // Integración continua: la música modula la velocidad de flujo, nunca resetea la fase
    float speedMod = (1.0f + smoothEnergy * 0.75f + smoothBass * 0.5f) * f.speed;
    plasmaTime += dt * speedMod * 0.85f;
    ripplePhase += dt * (1.2f + smoothBass * 2.8f);
    colorPhase += dt * (0.04f + smoothBass * 0.10f + smoothEnergy * 0.06f);
  }

  void render(const Frame& f, Canvas& c) const override {
    c.material("plasma", {0, 0, f.width, f.height},
               {plasmaTime, ripplePhase, colorPhase, smoothBass, smoothEnergy, smoothSpark});
  }
};
''';

const shaderSources = <String, String>{
  'plasma': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uRipple;
uniform float uColorPhase;
uniform float uBass;
uniform float uEnergy;
uniform float uSpark;
out vec4 fragColor;

vec3 plasmaColor(float x) {
  float s = fract(x) * 8.0;
  int i = int(floor(s));
  float f = fract(s);
  f = f * f * (3.0 - 2.0 * f);

  vec3 c0 = vec3(0.005, 0.040, 0.120);
  vec3 c1 = vec3(0.000, 0.380, 0.580);
  vec3 c2 = vec3(0.000, 0.880, 0.760);
  vec3 c3 = vec3(0.500, 1.000, 0.380);
  vec3 c4 = vec3(1.000, 0.860, 0.220);
  vec3 c5 = vec3(1.000, 0.320, 0.300);
  vec3 c6 = vec3(0.960, 0.120, 0.680);
  vec3 c7 = vec3(0.240, 0.030, 0.380);

  vec3 colA = c0;
  vec3 colB = c1;
  if (i == 1) { colA = c1; colB = c2; }
  else if (i == 2) { colA = c2; colB = c3; }
  else if (i == 3) { colA = c3; colB = c4; }
  else if (i == 4) { colA = c4; colB = c5; }
  else if (i == 5) { colA = c5; colB = c6; }
  else if (i == 6) { colA = c6; colB = c7; }
  else if (i == 7) { colA = c7; colB = c0; }

  return mix(colA, colB, f);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float aspect = uSize.x / uSize.y;
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0) * 6.5;

  vec2 c1 = vec2(sin(uTime * 0.45), cos(uTime * 0.38)) * 1.5;
  vec2 c2 = vec2(cos(uTime * 0.33 + 1.8), sin(uTime * 0.52)) * 1.4;

  float d1 = length(p - c1);
  float d2 = length(p - c2);

  float w1 = sin(p.x * 1.8 + uTime * 1.1);
  float w2 = sin(p.y * 2.1 + uTime * 0.95);
  float w3 = sin((p.x + p.y) * 1.5 + uTime * 0.75);
  float w4 = sin(d1 * 2.8 - uRipple * 2.2);
  float w5 = sin(d2 * 2.4 - uRipple * 1.7);

  vec2 warp = vec2(w1 + w5 * 0.4, w2 + w4 * 0.4) * (0.45 + uBass * 0.25);
  float w6 = sin(length(p + warp) * 2.6 - uTime * 1.2);

  float v = (w1 + w2 + w3 + w4 + w5 * 0.8 + w6 * 1.1) / 5.7;

  float phase = v * 0.85 + uColorPhase;
  vec3 col = plasmaColor(phase);

  float crest = pow(max(0.0, sin(v * 3.14159 * 2.0)), 6.0);
  vec3 filamentColor = mix(vec3(0.4, 0.8, 1.0), vec3(1.0, 0.9, 0.5), smoothstep(0.0, 1.0, uBass));
  col += filamentColor * (crest * (0.35 + uBass * 0.45 + uSpark * 0.4));

  col = mix(col, col * col * 1.4, uEnergy * 0.25);

  float vig = 1.0 - smoothstep(0.55, 1.4, length(uv - 0.5) * 1.35);
  col *= vig;

  fragColor = vec4(col, 1.0);
}
''',
};
