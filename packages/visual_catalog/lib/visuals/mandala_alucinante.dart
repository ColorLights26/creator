// Mandala Alucinante — mandala fractal psicodélico que se transforma.
// El plano se pliega en un caleidoscopio y cada punto recorre unas pocas
// iteraciones de un fractal (el conjunto de Kali), que dibuja ornamentos,
// filigranas y ojos de color. El parámetro del fractal viaja despacio, así que
// el mandala nunca se repite; los colores circulan por una paleta intensa.
// Los graves lo hacen respirar, cada dos golpes cambia la simetría (6, 8, 10 o
// 12 lados) y la energía acelera la transformación.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double morph = 0, spin = 0, hue = 0;
  float symA = 8, symB = 8, blend = 1;
  int beats = 0, symIndex = 1;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    morph = rng.unit() * 50.0;
    spin = rng.unit() * 6.2831853;
    hue = rng.unit();
    symA = symB = 8;
    blend = 1;
    beats = 0;
    symIndex = 1;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) {
      beats++;
      if (beats % 2 == 0) {
        static const float steps[4] = {6.0f, 8.0f, 10.0f, 12.0f};
        symIndex = (symIndex + 1) % 4;
        symA = symB;
        symB = steps[symIndex];
        blend = 0;
      }
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    blend = std::min(1.0f, blend + dt * 2.0f);
    morph += f.delta * f.speed * (0.05 + 0.15 * drive);
    spin += f.delta * f.speed * (0.06 + 0.15 * drive);
    hue += f.delta * (0.05 + 0.15 * energy) + 0.0;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float e = blend * blend * (3.0f - 2.0f * blend);
    // Parámetro del fractal: una curva lenta por una zona rica en ornamentos.
    float cx = 0.78f + 0.12f * float(std::sin(morph * 1.3));
    float cy = 0.55f + 0.12f * float(std::cos(morph * 0.9));
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {cx, cy, bass * amp, kick * amp});
    u.insert(u.end(), {float(std::fmod(spin, 6.2831853)), float(std::fmod(hue, 100.0)), f.glow, flash * amp});
    u.insert(u.end(), {symA, symB, e, energy});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("psy_mandala", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'psy_mandala': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // parámetro del fractal (x, y), graves, golpe
uniform vec4 uB;   // giro, ciclo de color, glow, destello
uniform vec4 uS;   // simetría actual, simetría siguiente, transición, energía
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float TAU = 6.2831853;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec3 psyPalette(float x) {
  float k = fract(x) * 4.0;
  vec3 c4 = vec3(0.7, 0.1, 1.0);
  vec3 a = k < 1.0 ? uC1 : (k < 2.0 ? uC2 : (k < 3.0 ? uC3 : c4));
  vec3 b = k < 1.0 ? uC2 : (k < 2.0 ? uC3 : (k < 3.0 ? c4 : uC1));
  return mix(a, b, smoothstep(0.0, 1.0, fract(k)));
}

vec3 mandala(vec2 p, float n) {
  float r = length(p);
  float a = atan(p.y, p.x) + uB.x;
  float sector = TAU / n;
  a = abs(mod(a, sector) - 0.5 * sector);
  vec2 z = vec2(cos(a), sin(a)) * r * (1.15 - 0.2 * uA.z);
  float trap = 10.0;
  float glow = 0.0;
  vec2 c = uA.xy;
  for (int i = 0; i < 6; i++) {
    z = abs(z) / max(dot(z, z), 0.02) - c;
    float l = length(z);
    trap = min(trap, l);
    glow += exp(-l * 3.0);
  }
  vec3 col = psyPalette(log(trap + 0.02) * 0.35 + glow * 0.08 + uB.y) * (0.35 + 0.4 * glow);
  col += vec3(1.0, 0.95, 0.9) * exp(-trap * 18.0) * 0.6;
  return col;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  vec3 col = mandala(p, uS.y);
  if (uS.z < 0.999) col = mix(mandala(p, uS.x), col, uS.z);
  col *= (0.8 + 0.4 * uA.z + 0.2 * uS.w) * uB.z;
  float r = length(p);
  col += psyPalette(uB.y + 0.5) * (0.003 + 0.01 * uA.w) / (r * r + 0.003);
  col += psyPalette(uB.y) * uB.w * 0.06;
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.85) {
    float e = (peak - 0.85) / 0.15;
    col *= (0.85 + 0.15 * e / (1.0 + e)) / peak;
  }
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
