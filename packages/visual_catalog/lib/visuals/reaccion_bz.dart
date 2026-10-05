// Reacción BZ — la química que se enciende sola en ondas y espirales.
// La reacción de Belousov-Zhabotinsky es una mezcla química que oscila: en
// una placa de Petri se forman ondas de color que avanzan, chocan y se anulan,
// y espirales que giran sin parar como relojes químicos. Aquí varias espirales
// ocupan la placa y, de vez en cuando (o con cada golpe de la música), nace
// un nuevo foco que lanza anillos concéntricos y le roba terreno a las
// espirales. Donde dos frentes se encuentran se funden en picos y se apagan,
// igual que en la reacción real.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: brazos de cada espiral.
  CreatorModifier.steps('brazos', 'Brazos', min: 1, max: 4, value: 1),
  // MOVIMIENTO: cómo se mueve el líquido bajo la reacción.
  CreatorModifier.choice(
    'deriva',
    'Corriente',
    options: ['Quieta', 'Remolino', 'Turbulenta'],
  ),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Energía'],
  ),
  // ATMÓSFERA: frentes finos y nítidos o bandas anchas que brillan.
  CreatorModifier.slider('frente', 'Frente de onda', min: 0, max: 1, value: .35),
  // MODO: dentro de una placa de Petri o a pantalla completa.
  CreatorModifier.toggle('placa', 'Placa de Petri', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Placa', {
    'placa': true,
    'brazos': 1,
    'deriva': 'Quieta',
    'frente': .2,
  }),
  CreatorVariation('Tormenta Química', {
    'brazos': 3,
    'deriva': 'Turbulenta',
    'frente': 1,
    'pulso': 'Energía',
    'speed': 1.4,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kSpirals = 3;
  static constexpr int kTargets = 4;
  float bass = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la placa sin música es idéntica a 30 y 60 FPS.
  double chem = 0, sinceIdle = 0, sinceSpawn = 10;
  std::array<float, kSpirals> sx{}, sy{}, sphase{};
  std::array<float, kTargets> tx{}, ty{};
  std::array<double, kTargets> tBirth{};
  std::array<bool, kTargets> tActive{};
  int nextTarget = 0;
  uint32_t spawns = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  // Un foco nuevo lanza anillos desde un punto de la placa.
  void spawn(double carry) {
    const uint32_t k = spawns++;
    tx[size_t(nextTarget)] = (hashU(k * 2654435761u + 17u) - 0.5f) * 0.8f;
    ty[size_t(nextTarget)] = (hashU(k * 2246822519u + 91u) - 0.5f) * 1.4f;
    tBirth[size_t(nextTarget)] = chem - carry;
    tActive[size_t(nextTarget)] = true;
    nextTarget = (nextTarget + 1) % kTargets;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = energy = slowBass = kick = flash = drive = 0;
    chem = 30.0 + double(rng.unit()) * 20.0;
    sinceIdle = 0;
    sinceSpawn = 10;
    const float bx[kSpirals] = {-0.2f, 0.22f, -0.12f};
    const float by[kSpirals] = {-0.5f, 0.02f, 0.52f};
    for (int i = 0; i < kSpirals; i++) {
      sx[size_t(i)] = bx[i] + (rng.unit() - 0.5f) * 0.12f;
      sy[size_t(i)] = by[i] + (rng.unit() - 0.5f) * 0.12f;
      sphase[size_t(i)] = rng.unit();
    }
    tActive.fill(false);
    tBirth.fill(0.0);
    nextTarget = 0;
    spawns = seed * 7u;
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    const bool fresh = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // Energía: la música acelera la química.
    const double rate = 1.0 + (m.pulso == 2 ? 1.6 : 0.3) * double(drive * f.intensity);
    chem += f.delta * f.speed * rate;
    sinceSpawn += f.delta;
    // Golpes: cada golpe hace nacer un foco nuevo.
    if (m.pulso == 0 && fresh && sinceSpawn > 0.4) {
      spawn(0.0);
      sinceSpawn = 0;
    }
    // Sin música nace un foco cada 4,5 s; con música, cada 9 s.
    const double period = mu.active ? 9.0 : 4.5;
    sinceIdle += f.delta * f.speed;
    if (sinceIdle >= period) {
      sinceIdle -= period;
      spawn(sinceIdle);
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    const float amp = f.intensity;
    const float t = float(std::fmod(chem, 100000.0));
    std::vector<float> u;
    u.reserve(64);
    u.insert(u.end(), {t, std::min(bass * amp, 1.5f), std::min(kick * amp, 1.0f), std::min(flash * amp, 1.0f)});
    // Velocidad de la onda, periodo, ancho del frente y brazos.
    // Detalle: ondas más juntas (periodo más corto).
    u.insert(u.end(), {0.11f, 2.6f / (0.55f + 0.45f * f.detail), 0.05f + 0.16f * g.frente, float(m.brazos)});
    u.insert(u.end(), {g.deriva.weight(1), g.deriva.weight(2), g.placa, g.pulso.weight(1)});
    u.insert(u.end(), {f.glow, float(f.width / std::min(f.width, f.height)), float(f.height / std::min(f.width, f.height)), 0.0f});
    for (int i = 0; i < kSpirals; i++) {
      const float drift = float(std::sin(chem * 0.03 + double(i) * 2.1));
      const float sign = i % 2 == 0 ? 1.0f : -1.0f;
      u.insert(u.end(), {sx[size_t(i)] + 0.04f * drift, sy[size_t(i)] + 0.03f * float(std::cos(chem * 0.025 + double(i))), sign, sphase[size_t(i)]});
    }
    for (int i = 0; i < kTargets; i++) {
      const float age = tActive[size_t(i)] ? float(std::min(chem - tBirth[size_t(i)], 1000.0)) : -1.0f;
      u.insert(u.end(), {tx[size_t(i)], ty[size_t(i)], age, tActive[size_t(i)] ? 1.0f : 0.0f});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("bz_reaction", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'bz_reaction': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo químico, graves, golpe, destello
uniform vec4 uB;   // velocidad de onda, periodo, ancho del frente, brazos
uniform vec4 uM;   // remolino, turbulenta, placa, peso de graves
uniform vec4 uV;   // glow, ancho y alto en unidades
uniform vec4 uS0;  // espirales: x, y, giro, desfase
uniform vec4 uS1;
uniform vec4 uS2;
uniform vec4 uT0;  // focos: x, y, edad, activo
uniform vec4 uT1;
uniform vec4 uT2;
uniform vec4 uT3;
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

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
             mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Fase de una fuente en p, su llegada (segundos) y la distancia.
vec3 source(vec2 p, vec2 c, float arms, float offset, float time, float v, float T) {
  vec2 d = p - c;
  float dist = sqrt(dot(d, d) + 0.0004);
  float phase = (time - dist / v) / T + arms * atan(d.y, d.x) / TAU + offset;
  return vec3(phase, dist / v, dist);
}

vec2 wave(float phase) {
  return vec2(cos(phase * TAU), sin(phase * TAU));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  vec2 p0 = p;
  // Corriente: el líquido gira o se agita bajo la reacción.
  if (uM.x > 0.001) {
    float ang = uM.x * 0.9 * exp(-length(p) * 1.6) * sin(t * 0.07);
    float cs = cos(ang);
    float sn = sin(ang);
    p = vec2(cs * p.x - sn * p.y, sn * p.x + cs * p.y);
  }
  if (uM.y > 0.001) {
    vec2 w = vec2(noise(p * 3.0 + vec2(t * 0.05, 0.0)), noise(p * 3.0 + vec2(4.7, -t * 0.04))) - 0.5;
    p += w * 0.09 * uM.y;
  }
  float v = uB.x;
  float T = uB.y;
  vec3 s0 = source(p, uS0.xy, uB.w * uS0.z, uS0.w, t, v, T);
  vec3 s1 = source(p, uS1.xy, uB.w * uS1.z, uS1.w, t, v, T);
  vec3 s2 = source(p, uS2.xy, uB.w * uS2.z, uS2.w, t, v, T);
  vec3 q0 = source(p, uT0.xy, 0.0, 0.0, uT0.z, v, T);
  vec3 q1 = source(p, uT1.xy, 0.0, 0.0, uT1.z, v, T);
  vec3 q2 = source(p, uT2.xy, 0.0, 0.0, uT2.z, v, T);
  vec3 q3 = source(p, uT3.xy, 0.0, 0.0, uT3.z, v, T);
  // Un foco nuevo sólo alcanza hasta donde llegó su primer anillo.
  float r0 = uT0.w * smoothstep(0.0, 0.03, uT0.z * v - q0.z);
  float r1 = uT1.w * smoothstep(0.0, 0.03, uT1.z * v - q1.z);
  float r2 = uT2.w * smoothstep(0.0, 0.03, uT2.z * v - q2.z);
  float r3 = uT3.w * smoothstep(0.0, 0.03, uT3.z * v - q3.z);
  // Gana el frente que llega antes: los focos, cerca de su centro.
  float a0 = mix(1e3, q0.y - 0.6, step(0.001, r0));
  float a1 = mix(1e3, q1.y - 0.6, step(0.001, r1));
  float a2 = mix(1e3, q2.y - 0.6, step(0.001, r2));
  float a3 = mix(1e3, q3.y - 0.6, step(0.001, r3));
  float best = min(min(min(s0.y, s1.y), min(s2.y, a0)), min(min(a1, a2), a3));
  float w0 = exp(-(s0.y - best) * 3.0);
  float w1 = exp(-(s1.y - best) * 3.0);
  float w2 = exp(-(s2.y - best) * 3.0);
  float w3 = exp(-(a0 - best) * 3.0) * r0;
  float w4 = exp(-(a1 - best) * 3.0) * r1;
  float w5 = exp(-(a2 - best) * 3.0) * r2;
  float w6 = exp(-(a3 - best) * 3.0) * r3;
  // Las fases se mezclan como vectores: donde chocan dos frentes se anulan.
  vec2 z = w0 * wave(s0.x) + w1 * wave(s1.x) + w2 * wave(s2.x) + w3 * wave(q0.x) +
           w4 * wave(q1.x) + w5 * wave(q2.x) + w6 * wave(q3.x);
  float wsum = w0 + w1 + w2 + w3 + w4 + w5 + w6;
  float coherence = clamp(length(z) / max(wsum, 1e-4), 0.0, 1.0);
  float phase = atan(z.y, z.x) / TAU;
  // Tiempo desde que pasó el último frente.
  float tau = fract(phase) * T;
  float width = uB.z * T * (1.0 + 0.9 * uA.y * uM.w);
  float front = exp(-tau / max(width * 0.35, 0.01));
  float body = exp(-tau / max(width * 1.4, 0.02));
  float rest = smoothstep(0.3 * T, T, tau);
  vec3 ready = mix(uC0, uC1, 0.55);
  vec3 col = mix(uC0 * 0.7, ready, rest);
  col = mix(col, uC1, body * coherence * 0.8);
  col = mix(col, uC2, smoothstep(0.15, 0.6, body) * coherence);
  col = mix(col, uC3, front * coherence);
  // Brillo de los frentes.
  col += uC2 * front * coherence * 0.25 * uV.x;
  // Textura del gel.
  col *= 0.94 + 0.06 * noise(p0 * 40.0);
  col *= 1.0 + 0.2 * uA.z + 0.15 * uA.w;
  // Placa de Petri: la reacción queda dentro de un círculo de cristal.
  if (uM.z > 0.001) {
    float r = length(p0);
    float R = 0.47 * min(uV.y, uV.z);
    float inside = smoothstep(R + 0.004, R - 0.004, r);
    float rim = exp(-abs(r - R) * 90.0);
    vec3 outside = uC0 * 0.4 * (1.0 - 0.3 * smoothstep(R, R + 0.6, r));
    vec3 dish = mix(outside, col, inside) + uC3 * rim * 0.35;
    col = mix(col, dish, uM.z);
  }
  col *= 1.0 - 0.25 * smoothstep(0.6, 1.4, length(p0 * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
