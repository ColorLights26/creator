// Patrones de Turing — manchas, rayas y laberintos que crecen y mutan.
// Los patrones de reacción-difusión (los que pintan las manchas de los
// animales) se aproximan sumando seis ondas de la misma longitud en distintas
// direcciones sobre un espacio retorcido: según el umbral salen manchas,
// laberintos o el negativo de las manchas. El umbral recorre esas fases sin
// parar; cada golpe da un salto de mutación con un muelle, la energía acelera
// el crecimiento y los graves encienden los bordes.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double grow = 0, phaseClock = 0;
  float mutate = 0, mutateVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    grow = rng.unit() * 50.0;
    phaseClock = rng.unit() * 6.2831853;
    mutate = mutateVel = 0;
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
    if (hit > kick + 0.2f) mutateVel += 1.6f * hit;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    mutateVel += (-mutate * 18.0f - mutateVel * 4.5f) * dt;
    mutate += mutateVel * dt;
    grow += f.delta * f.speed * (0.25 + 0.9 * drive);
    phaseClock += f.delta * f.speed * (0.05 + 0.12 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    // Umbral: manchas -> laberinto -> manchas en negativo -> laberinto...
    float threshold = 0.32f * float(std::sin(phaseClock)) + 0.18f * mutate;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(grow, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {threshold, f.glow, spark * amp, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("turing", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'turing': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // crecimiento, graves, golpe, energía
uniform vec4 uB;   // umbral, glow, agudos, destello
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
             mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  // Espacio retorcido: el patrón deja de ser una red regular y se vuelve orgánico.
  vec2 q = p + 0.22 * vec2(noise(p * 2.2 + t * 0.05) - 0.5, noise(p * 2.2 + 7.3 - t * 0.04) - 0.5);
  const float K = 30.0;
  float field = 0.0;
  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    float ang = fi * 0.5235988 + 0.15 * sin(t * 0.07 + fi);
    vec2 k = K * vec2(cos(ang), sin(ang));
    field += cos(dot(k, q) + t * (0.3 + 0.13 * fi) + fi * 1.7);
  }
  field /= 6.0;
  float v = field - uB.x;
  float aa = 0.08;
  float on = smoothstep(-aa, aa, v);
  float edge = exp(-abs(v) * 14.0);
  // Interior naranja que se aclara hacia el centro de cada mancha; fuera,
  // turquesa oscuro; el borde brilla con los graves.
  vec3 inside = mix(uC1, mix(uC1, uC3, 0.6), smoothstep(0.1, 0.6, v)) * (0.85 + 0.3 * uA.y + 0.35 * uA.z);
  vec3 outside = mix(uC0, uC2 * 0.32, smoothstep(-0.1, -0.6, v));
  vec3 col = mix(outside, inside, on);
  col += uC3 * edge * (0.25 + 0.5 * uA.y + 0.6 * uA.z) * uB.y;
  // Destellos en los bordes con los agudos.
  float tw = step(0.992 - 0.01 * uB.z, hash12(floor(frag * 0.5) + floor(t * 6.0)));
  col += uC3 * tw * edge * uB.z;
  col += uC1 * uB.w * 0.06;
  col *= 1.0 - 0.35 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
