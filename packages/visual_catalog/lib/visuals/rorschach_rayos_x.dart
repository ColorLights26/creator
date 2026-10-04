// Rorschach Rayos X — la mancha como la radiografía de algo vivo.
// En negativo: el fondo es negro y la mancha brilla, más en el borde, como
// la silueta de un órgano en una radiografía. Por dentro la recorren venas
// ramificadas que se encienden con cada latido; en el centro late un
// corazón que golpea con los graves y con cada beat la mancha entera se
// hincha. Una franja de escáner sube y baja iluminando lo que toca.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.5, value: 1),
  CreatorModifier.slider('latido', 'Fuerza del latido', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('escaneo', 'Franja de escáner', value: true),
  CreatorModifier.choice('color', 'Película', options: ['Rojo', 'Blanco', 'Ámbar']),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double morph = 0, clock = 0, aux = 0, sinceBeat = 100, sinceIdle = 0;
  float spread = 0, spreadVel = 0, beatPower = 0;
  int beats = 0;


  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float hashf(int n) {
    uint32_t x = uint32_t(n) * 2654435761u;
    x ^= x >> 15;
    x *= 2246822519u;
    x ^= x >> 13;
    return float(x & 0xffffff) / 16777216.0f;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    morph = rng.unit() * 40.0;
    clock = 0;
    aux = 0;
    sinceBeat = 100;
    sinceIdle = 0;
    spread = spreadVel = beatPower = 0;
    beats = 0;

  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    sinceBeat += f.delta;
    sinceIdle += f.delta;
    if (hit > kick + 0.2f) {
      spreadVel += 2.2f * hit;
      sinceBeat = 0;
      beatPower = hit;
      beats++;
      sinceIdle = 0;
    }
    // Sin música también hay un sobresalto cada pocos segundos.
    if (!mu.active && sinceIdle > 1.1) {
      sinceIdle -= 1.1;
      sinceBeat = sinceIdle;
      beatPower = 0.7f;
      beats++;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    spreadVel += (-spread * 18.0f - spreadVel * 5.0f) * dt;
    spread += spreadVel * dt;
    clock += f.delta * f.speed;
    morph += f.delta * f.speed * (0.14 + 0.35 * drive) * 0.8;

  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    float t = float(std::fmod(morph, 1000.0));
    float pulse = sinceBeat < 2.0 ? beatPower * float(std::exp(-sinceBeat * 3.0)) : 0.0f;
    std::vector<float> u;
    u.reserve(56);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {m.latido, m.tamano, m.escaneo ? 1.0f : 0.0f, float(m.color)});
    u.insert(u.end(), {f.glow, flash * amp, spark * amp, float(std::fmod(clock, 1000.0))});
    // Lóbulos de la mancha: cinco manchas grandes que derivan despacio.
    static const float lx[5] = {0.1f, 0.26f, 0.16f, 0.28f, 0.07f};
    static const float ly[5] = {-0.5f, -0.2f, 0.12f, 0.4f, 0.55f};
    static const float lr[5] = {0.14f, 0.16f, 0.18f, 0.14f, 0.12f};
    for (int k = 0; k < 5; k++) {
      float fk = float(k);
      u.insert(u.end(), {lx[k] + 0.07f * std::sin(t * 0.7f + fk * 1.9f), ly[k] + 0.07f * std::cos(t * 0.5f + fk * 2.7f), lr[k], 0.0f});
    }
    u.insert(u.end(), {float(std::fmod(clock * 0.25, 1.0)), 0.0f, 0.0f, 0.0f});
    u.insert(u.end(), {pulse, std::max(-0.2f, spread) * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("inkblot_xray", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_xray': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // cambio, graves, golpe, energía
uniform vec4 uB;   // ajustes de la variante
uniform vec4 uD;   // glow, destello, agudos, reloj real
uniform vec4 uL0;  // lóbulos: x, y, radio
uniform vec4 uL1;
uniform vec4 uL2;
uniform vec4 uL3;
uniform vec4 uL4;
uniform vec4 uX;   // datos propios de la variante
uniform vec4 uP;   // sobresalto, expansión
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

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    v += noise(p) * a;
    p = p * 2.03 + vec2(1.7, 9.2);
    a *= 0.5;
  }
  return v / 0.875;
}

float lobe(vec2 q, vec4 L) {
  vec2 d = q - L.xy;
  return exp(-dot(d, d) / (L.z * L.z));
}

// Campo de tinta: positivo dentro de la mancha. q ya viene reflejado.
float blot(vec2 q, float t, float grow, out vec2 w, out float n) {
  w = vec2(noise(q * 2.2 + vec2(t * 0.6, 0.0)), noise(q * 2.2 + vec2(4.3, -t * 0.5))) - 0.5;
  n = fbm(q * 3.6 + w * 1.4 + vec2(0.0, t * 0.25));
  vec2 qw = q + w * 0.08;
  float env = lobe(qw, uL0) + lobe(qw, uL1) + lobe(qw, uL2) + lobe(qw, uL3) + lobe(qw, uL4);
  env += 0.9 * exp(-q.x * q.x / 0.004) * (1.0 - smoothstep(0.55, 0.95, abs(q.y)));
  return env * 0.8 + (n - 0.5) * 1.1 - 0.5 + grow;
}

vec3 paper(vec2 frag, vec2 p) {
  float fiber = hash12(floor(frag * vec2(0.5, 0.08))) * 0.6 + noise(frag * 0.05) * 0.4;
  vec3 col = uC0 * (0.93 + 0.07 * fiber);
  return col * (1.0 - 0.16 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65))));
}

vec3 tint() {
  if (uB.w < 0.5) return uC1;
  if (uB.w < 1.5) return vec3(0.85, 0.9, 1.0);
  return uC2;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  float beat = uB.x * (uP.x * 0.12 + uA.y * 0.05);
  vec2 q = vec2(abs(p.x), p.y) / (uB.y * (1.0 + beat));
  vec2 w;
  float n;
  float F = blot(q, t, 0.05 + 0.15 * uP.y, w, n);
  float inside = smoothstep(-0.01, 0.01, F);
  // Densidad de radiografía: más brillo cerca del borde.
  float rim = exp(-abs(F) * 9.0);
  // Venas: crestas de ruido que se ramifican.
  float v1 = 1.0 - abs(noise(q * 9.0 + w * 3.0) * 2.0 - 1.0);
  float v2 = 1.0 - abs(noise(q * 18.0 - w * 4.0 + 3.1) * 2.0 - 1.0);
  float veins = pow(v1, 8.0) * 0.8 + pow(v2, 10.0) * 0.5;
  vec3 c = tint();
  vec3 col = uC0;
  col += c * rim * 0.9 * (0.7 + 0.5 * uA.y);
  col += c * inside * (0.12 + 0.18 * n);
  col += mix(c, uC3, 0.4) * veins * inside * (0.35 + 1.2 * uP.x * uB.x + 0.3 * uA.y);
  // Corazón que late en el centro.
  float dh = length((p / uB.y) * vec2(1.0, 1.3) - vec2(0.0, -0.05));
  float heart = exp(-dh * (14.0 - 6.0 * uP.x * uB.x));
  col += mix(c, uC3, 0.5) * heart * (0.5 + 1.5 * uP.x * uB.x + 0.4 * uA.y);
  // Franja del escáner.
  if (uB.z > 0.5) {
    float halfH = 0.5 * uSize.y / scale;
    float sy = -halfH + abs(fract(uX.x) * 2.0 - 1.0) * 2.0 * halfH;
    float band = exp(-abs(p.y - sy) * 40.0);
    col += uC3 * band * (0.15 + 0.6 * inside);
  }
  // Grano de placa.
  col += vec3(hash12(floor(frag * 0.7) + floor(uD.w * 24.0)) - 0.5) * 0.04;
  col += c * uD.y * 0.05;
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.9) col *= (0.9 + 0.1 * (peak - 0.9) / (peak - 0.8)) / peak;
  float cover = inside;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
