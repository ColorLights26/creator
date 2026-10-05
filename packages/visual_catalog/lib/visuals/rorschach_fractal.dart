// Rorschach Fractal — una mancha con un borde infinito.
// La mancha es un conjunto de Julia: por mucho que te acerques, su borde
// sigue lleno de ramas, conejitos o espirales más pequeñas. La forma general
// sigue siendo la de una mancha simétrica, pero el fractal cambia sin
// parar, viaja acercándose o late. Los golpes le dan sacudidas de forma,
// los graves la hacen latir y los agudos aceleran las bandas de color
// que corren por el borde.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('familia', 'Familia', options: ['Dendritas', 'Conejo', 'Espirales']),
  CreatorModifier.choice('deriva', 'Movimiento', options: ['Lenta', 'Viaje', 'Latido']),
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
  CreatorModifier.slider('bandas', 'Bandas de color', min: 0, max: 1, value: .5),
  CreatorModifier.toggle('negativo', 'Negativo', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Dendritas', {'familia': 'Dendritas', 'bandas': 1, 'deriva': 'Viaje'}),
  CreatorVariation('Conejos', {'familia': 'Conejo', 'deriva': 'Latido', 'negativo': true}),
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
    if (!mu.active && sinceIdle > 2.4) {
      sinceIdle -= 2.4;
      sinceBeat = sinceIdle;
      beatPower = 0.7f;
      beats++;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    spreadVel += (-spread * 18.0f - spreadVel * 5.0f) * dt;
    spread += spreadVel * dt;
    clock += f.delta * f.speed;
    morph += f.delta * f.speed * (0.14 + 0.35 * drive) * 1.0;

  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    const float ct = float(std::fmod(morph, 1000.0));
    const float cx = g.familia.weight(0) * -0.8f + g.familia.weight(1) * -0.123f + g.familia.weight(2) * -0.7269f + 0.03f * std::cos(ct * 0.31f);
    const float cy = g.familia.weight(0) * 0.156f + g.familia.weight(1) * 0.745f + g.familia.weight(2) * 0.1889f + 0.03f * std::sin(ct * 0.23f);
    const float jolt = g.pulso.weight(0) * float(sinceBeat < 2.0 ? double(beatPower) * std::exp(-sinceBeat * 3.0) : 0.0);
    const float zoom = g.deriva.weight(0) + g.deriva.weight(1) * (1.6f + 0.6f * std::sin(ct * 0.17f)) +
                       g.deriva.weight(2) * (1.0f + 0.25f * std::min(bass * f.intensity, 1.0f) + 0.1f * std::sin(ct * 2.0f));
    float amp = f.intensity;
    float t = float(std::fmod(morph, 1000.0));
    float pulse = sinceBeat < 2.0 ? beatPower * float(std::exp(-sinceBeat * 3.0)) : 0.0f;
    std::vector<float> u;
    u.reserve(56);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {cx + 0.025f * jolt, cy - 0.02f * jolt, zoom, 0.1f * std::sin(ct * 0.11f)});
    u.insert(u.end(), {f.glow, flash * amp, spark * amp, float(std::fmod(clock, 1000.0))});
    // Lóbulos de la mancha: cinco manchas grandes que derivan despacio.
    static const float lx[5] = {0.12f, 0.24f, 0.2f, 0.32f, 0.08f};
    static const float ly[5] = {-0.32f, -0.12f, 0.1f, 0.3f, 0.5f};
    static const float lr[5] = {0.15f, 0.16f, 0.15f, 0.13f, 0.11f};
    for (int k = 0; k < 5; k++) {
      float fk = float(k);
      u.insert(u.end(), {lx[k] + 0.07f * std::sin(t * 0.7f + fk * 1.9f), ly[k] + 0.07f * std::cos(t * 0.5f + fk * 2.7f), lr[k], 0.0f});
    }
    u.insert(u.end(), {std::clamp(g.bandas, 0.0f, 1.0f), std::clamp(g.negativo, 0.0f, 1.0f), g.pulso.weight(2), 14.0f + 10.0f * f.detail});
    u.insert(u.end(), {pulse, std::max(-0.2f, spread) * amp, g.pulso.weight(1), 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("inkblot_julia", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_julia': r"""
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

float sq(float x) {
  return x * x;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  vec2 q = vec2(abs(p.x), p.y);
  // La silueta general sigue siendo la de una mancha.
  float env = lobe(q, uL0) + lobe(q, uL1) + lobe(q, uL2) + lobe(q, uL3) + lobe(q, uL4);
  float region = smoothstep(0.05, 0.4, env + 0.3 + 0.25 * uA.y * uP.z + 0.15 * uP.y);
  // Julia con el eje real vertical: el espejo es natural.
  float cs = cos(uB.w);
  float sn = sin(uB.w);
  vec2 z = vec2(q.y * 1.15, q.x) * 1.7 / uB.z;
  z = vec2(cs * z.x - sn * z.y, sn * z.x + cs * z.y);
  vec2 c = uB.xy;
  float it = 0.0;
  float m2 = 0.0;
  for (int i = 0; i < 40; i++) {
    if (float(i) >= uX.w) break;
    z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
    m2 = dot(z, z);
    if (m2 > 16.0) break;
    it += 1.0;
  }
  float smoothIt = it - log2(max(log2(max(m2, 1.0001)), 1e-4)) + 4.0;
  float inside = step(uX.w - 0.5, it);
  float edgeGlow = clamp(smoothIt / uX.w, 0.0, 1.0);
  float inkAmt = max(inside, smoothstep(0.25, 0.7, edgeGlow)) * region;
  vec3 pap = paper(frag, p);
  vec3 col = mix(pap, uC1, inkAmt);
  // Bandas de color que corren por el borde.
  float band = 0.5 + 0.5 * sin(smoothIt * 0.9 - uD.w * (1.0 + 4.0 * uD.z * uX.z));
  float halo = smoothstep(0.08, 0.5, edgeGlow) * (1.0 - inside) * region;
  col = mix(col, mix(uC2, uC3, band), (0.35 + 0.65 * uX.x) * halo);
  col *= 1.0 + 0.12 * uA.z;
  vec3 neg = mix(uC1, mix(pap, uC3, 0.25), inkAmt);
  neg = mix(neg, mix(uC2, uC3, band), uX.x * smoothstep(0.15, 0.6, edgeGlow) * (1.0 - inside) * region * 0.8);
  col = mix(col, neg, uX.y);
  col = mix(col, uC2, uD.y * 0.04);
  float cover = inkAmt;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
