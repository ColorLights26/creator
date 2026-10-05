// Anillos de Humo — aros de humo que salen disparados hacia ti.
// Un cañón de aire lanza anillos de vórtice: aros de humo que giran sobre sí
// mismos (el humo rueda alrededor del tubo) y avanzan creciendo hasta
// deshacerse. Aquí salen desde abajo, iluminados por un foco de escenario,
// y con cada golpe de la música dispara un anillo nuevo. Los graves los
// hinchan y la energía los lanza más rápido; en la sala queda una bruma
// que el foco atraviesa.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: hacia dónde se disparan los anillos.
  CreatorModifier.choice(
    'disparo',
    'Disparo',
    options: ['Centro', 'Abanico', 'Espiral'],
  ),
  // MOVIMIENTO: anillos firmes o que ruedan y se retuercen.
  CreatorModifier.slider('remolino', 'Remolino', min: 0, max: 1, value: .5),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Ráfaga'],
  ),
  // ATMÓSFERA: la bruma de la sala y el foco que la atraviesa.
  CreatorModifier.slider('bruma', 'Bruma', min: 0, max: 1, value: .45),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Cañón', {
    'disparo': 'Centro',
    'pulso': 'Golpes',
    'remolino': 1,
  }),
  CreatorVariation('Sueño', {
    'disparo': 'Espiral',
    'bruma': 1,
    'remolino': .3,
    'speed': .6,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kRings = 6;
  float bass = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double clock = 0, sinceIdle = 0, sinceShot = 10;
  std::array<double, kRings> birth{};
  std::array<float, kRings> power{}, angle{}, spin{};
  int nextRing = 0;
  uint32_t shots = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  static int slots(float detail) { return std::clamp(int(std::lround(3.0f + 1.5f * detail)), 3, kRings); }
  // Dispara un anillo; carry es el tiempo que ya pasó desde el disparo.
  void fire(int pattern, float strength, double carry, int limit) {
    const uint32_t k = shots++;
    const int slot = nextRing % limit;
    float a = (hashU(k * 2654435761u + 1u) - 0.5f) * 0.12f;
    if (pattern == 1) a = (k % 2u == 0 ? 1.0f : -1.0f) * (0.25f + 0.2f * hashU(k * 3266489917u + 4u));
    if (pattern == 2) a = 0.5f * std::sin(float(k) * 0.9f);
    birth[size_t(slot)] = clock - carry;
    power[size_t(slot)] = strength;
    angle[size_t(slot)] = a;
    spin[size_t(slot)] = (hashU(k * 2246822519u + 2u) < 0.5f ? -1.0f : 1.0f) * (1.0f + float(k % 7u));
    nextRing = (slot + 1) % limit;
  }

 public:
  void reset(uint32_t seed) override {
    bass = energy = slowBass = kick = flash = drive = 0;
    clock = 0;
    sinceIdle = 0;
    sinceShot = 10;
    birth.fill(-1000.0);
    power.fill(1.0f);
    angle.fill(0.0f);
    spin.fill(1.0f);
    nextRing = 0;
    shots = seed * 5u;
    for (int i = 0; i < 3; i++) fire(0, 1.0f, 0.4 + 1.3 * double(i), kRings);
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
    const double step = f.delta * f.speed;
    clock += step;
    sinceShot += f.delta;
    const int limit = slots(f.detail);
    // Golpes: cada golpe dispara un anillo, más grande cuanto más fuerte.
    if (m.pulso == 0 && fresh && sinceShot > 0.25) {
      fire(m.disparo, 0.8f + 0.5f * hit * f.intensity, 0.0, limit);
      sinceShot = 0;
    }
    // A su ritmo dispara uno cada 1,3 s; en Ráfaga, la energía lo acelera.
    double period = 1.3;
    if (mu.active && m.pulso == 0) period = 3.9;
    if (m.pulso == 2) period = 1.3 / (1.0 + 1.8 * double(drive * f.intensity));
    sinceIdle += step;
    while (sinceIdle >= period) {
      sinceIdle -= period;
      fire(m.disparo, 1.0f, sinceIdle, limit);
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    const float side = std::min(f.width, f.height);
    std::vector<float> u;
    u.reserve(56);
    const float rush = g.pulso.weight(2) * std::min(drive * amp, 1.0f);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), std::min(bass * amp, 1.5f) * g.pulso.weight(1), std::min(kick * amp, 1.0f), rush});
    u.insert(u.end(), {std::clamp(g.remolino, 0.0f, 1.0f), std::clamp(g.bruma, 0.0f, 1.0f), f.glow, std::min(flash * amp, 1.0f)});
    u.insert(u.end(), {0.5f * f.height / side, 0.5f * f.width / side, 0.0f, 0.0f});
    for (int i = 0; i < kRings; i++) {
      const float age = float(std::min(clock - birth[size_t(i)], 1000.0));
      u.insert(u.end(), {age, power[size_t(i)], angle[size_t(i)], spin[size_t(i)]});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("smoke_rings", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'smoke_rings': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, graves, golpe, ráfaga
uniform vec4 uB;   // remolino, bruma, glow, destello
uniform vec4 uE;   // media altura, medio ancho
uniform vec4 uR0;  // anillos: edad, fuerza, ángulo, giro
uniform vec4 uR1;
uniform vec4 uR2;
uniform vec4 uR3;
uniform vec4 uR4;
uniform vec4 uR5;
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

// Densidad de un anillo y cuánto de su lado cercano se ve aquí.
float ring(vec2 p, vec4 Rg, float halfH, out float near) {
  near = 0.0;
  float age = Rg.x;
  if (age < 0.0 || age > 9.0) return 0.0;
  vec2 dir = vec2(sin(Rg.z), -cos(Rg.z));
  vec2 start = vec2(0.0, halfH * 0.8);
  // El anillo sube y a la vez viene hacia ti: crece mucho mientras avanza.
  float travel = (0.75 * (1.0 - exp(-age / 1.4)) + 0.04 * age) * (1.0 + 0.6 * uA.w);
  vec2 c = start + dir * travel * halfH * 1.15;
  float R = Rg.y * (0.06 + 0.16 * (1.0 - exp(-age / 1.6)) + 0.09 * age * age * 0.25) * (1.0 + 0.15 * uA.y);
  vec2 d = p - c;
  vec2 ax = vec2(-dir.y, dir.x);
  vec2 l = vec2(dot(d, ax), dot(d, dir));
  float e = 0.42;
  // Lejos del tubo de humo no hay nada: se descarta antes del atan y el ruido.
  float s0 = length(vec2(l.x, l.y / e)) - R;
  if (abs(s0) > R * 0.6 + 0.02) return 0.0;
  float th = atan(l.y / e, l.x);
  // Remolino: el aro se retuerce y el humo rueda más rápido.
  float Rw = R * (1.0 + 0.09 * uB.x * sin(th * 2.0 + age * 3.0 + Rg.w));
  float s = length(vec2(l.x, l.y / e)) - Rw;
  float w = R * (0.12 + 0.1 * min(age / 3.0, 1.0));
  float tube = exp(-(s * s) / (w * w));
  if (tube < 0.002) return 0.0;
  float roll = noise(vec2(th * 9.0 + Rg.w * 7.0, s / w * 2.2 - age * (2.0 + 4.0 * uB.x) * sign(Rg.w)));
  near = smoothstep(-0.2, 0.6, sin(th));
  return tube * (0.35 + 0.95 * roll) * exp(-age / 2.6) * smoothstep(0.0, 0.12, age);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  float halfH = uE.x;
  // Bruma de la sala atravesada por un foco que sube desde abajo.
  float rise = halfH - p.y;
  float beam = exp(-abs(p.x) / (0.08 + rise * 0.22)) * smoothstep(-0.1, 0.4, rise);
  float haze = noise(p * 2.2 + vec2(0.0, t * 0.08)) * 0.6 + noise(p * 5.0 + vec2(t * 0.05, t * 0.12)) * 0.4;
  vec3 col = uC0 + uC1 * (0.05 + 0.3 * beam * haze) * uB.y * uB.z;
  col += uC2 * 0.06 * exp(-length(p - vec2(0.0, halfH)) * 4.0) * (1.0 + uA.z);
  float n0;
  float n1;
  float n2;
  float n3;
  float n4;
  float n5;
  float d0 = ring(p, uR0, halfH, n0);
  float d1 = ring(p, uR1, halfH, n1);
  float d2 = ring(p, uR2, halfH, n2);
  float d3 = ring(p, uR3, halfH, n3);
  float d4 = ring(p, uR4, halfH, n4);
  float d5 = ring(p, uR5, halfH, n5);
  float acc = d0 + d1 + d2 + d3 + d4 + d5;
  float near = (d0 * n0 + d1 * n1 + d2 * n2 + d3 * n3 + d4 * n4 + d5 * n5) / max(acc, 1e-4);
  // El humo toma la luz del foco: más claro por delante y donde pasa el haz.
  float light = 0.55 + 0.6 * beam + 0.3 * uB.w;
  vec3 smoke = mix(uC1, mix(uC2, uC3, 0.45), 0.25 + 0.6 * near) * light;
  col = mix(col, smoke * 1.25, 1.0 - exp(-acc * 2.4));
  col += uC2 * acc * 0.12 * uB.z;
  col *= 1.0 + 0.12 * uA.z;
  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)) / max(uE.y * 2.0, 0.5));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.9) col *= (0.9 + 0.1 * (peak - 0.9) / (peak - 0.8)) / peak;
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
