// Rorschach Estrobo — la mancha en una discoteca.
// Cada golpe de la música es un corte seco: la mancha cambia de forma de
// golpe, salta de dos espejos a cuatro, ocho o seis, y el blanco y el
// negro se invierten. Un eco rojo dibuja su contorno por dentro y la
// pantalla tiembla. También puede fundirse de una forma a la siguiente en
// vez de cortar. Los graves la empujan hacia ti y los agudos la hacen
// parpadear (sin pasar de tres destellos por segundo).
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('simetria', 'Simetría', options: ['Cambiante', 'Espejo', 'Caleidoscopio']),
  CreatorModifier.choice('corte', 'Corte', options: ['Seco', 'Fundido']),
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
  CreatorModifier.slider('temblor', 'Temblor', min: 0, max: 1, value: .5),
  CreatorModifier.toggle('invertir', 'Inversión', value: true),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Club', {'simetria': 'Cambiante', 'corte': 'Seco', 'pulso': 'Golpes', 'temblor': 1}),
  CreatorVariation('Trance', {'simetria': 'Caleidoscopio', 'corte': 'Fundido', 'invertir': false, 'pulso': 'Graves'}),
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
    if (!mu.active && sinceIdle > 0.9) {
      sinceIdle -= 0.9;
      sinceBeat = sinceIdle;
      beatPower = 0.7f;
      beats++;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    spreadVel += (-spread * 18.0f - spreadVel * 5.0f) * dt;
    spread += spreadVel * dt;
    clock += f.delta * f.speed;
    morph += f.delta * f.speed * (0.14 + 0.35 * drive) * 0.5;

  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    // Cada golpe es un corte; con graves o agudos, uno cada cuatro.
    const int cut = m.pulso == 0 ? beats : beats / 4;
    const float blend = 1.0f - g.corte.weight(1) * (1.0f - std::clamp(float(sinceBeat) / 0.25f, 0.0f, 1.0f));
    static const float orders[4] = {2.0f, 4.0f, 8.0f, 6.0f};
    const float order = g.simetria.weight(0) * orders[cut % 4] + g.simetria.weight(1) * 2.0f + g.simetria.weight(2) * 6.0f;
    float amp = f.intensity;
    float t = float(std::fmod(morph, 1000.0));
    float pulse = sinceBeat < 2.0 ? beatPower * float(std::exp(-sinceBeat * 3.0)) : 0.0f;
    std::vector<float> u;
    u.reserve(56);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(cut % 97), float((cut + 96) % 97), blend, order});
    u.insert(u.end(), {f.glow, flash * amp, spark * amp, float(std::fmod(clock, 1000.0))});
    // Lóbulos de la mancha: cinco manchas grandes que derivan despacio.
    static const float lx[5] = {0.12f, 0.24f, 0.2f, 0.32f, 0.08f};
    static const float ly[5] = {-0.32f, -0.12f, 0.1f, 0.3f, 0.5f};
    static const float lr[5] = {0.15f, 0.16f, 0.15f, 0.13f, 0.11f};
    for (int k = 0; k < 5; k++) {
      float fk = float(k);
      u.insert(u.end(), {lx[k] + 0.07f * std::sin(t * 0.7f + fk * 1.9f), ly[k] + 0.07f * std::cos(t * 0.5f + fk * 2.7f), lr[k], 0.0f});
    }
    u.insert(u.end(), {std::clamp(g.invertir, 0.0f, 1.0f) * float(cut % 2), std::clamp(g.temblor, 0.0f, 1.0f), g.pulso.weight(1), g.pulso.weight(2)});
    u.insert(u.end(), {pulse, std::max(-0.2f, spread) * amp, f.detail, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("inkblot_strobe", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_strobe': r"""
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
  float t = uA.x;
  float clk = uD.w;
  // Temblor con cada golpe; los graves empujan la mancha hacia ti.
  float sh = uX.y * (uP.x * 0.03 + uA.z * 0.01);
  p += sh * vec2(sin(clk * 97.0), cos(clk * 83.0));
  p *= 1.0 - 0.12 * uA.y * uX.z;
  float r = length(p);
  float N = max(uB.w, 2.0);
  float sector = 6.2831853 / N;
  float phi = atan(p.x, -p.y);
  float fold = abs(mod(phi + sector * 0.5, sector) - sector * 0.5);
  vec2 qk = vec2(sin(fold), -cos(fold)) * r;
  vec2 q = mix(vec2(abs(p.x), p.y), qk, smoothstep(2.0, 3.0, N));
  // El corte: otra forma de golpe (o fundida con la anterior).
  float seed = mix(uB.y, uB.x, uB.z);
  q = q * (0.85 + 0.3 * fract(sin(seed * 12.9) * 43.7)) + vec2(0.0, 0.08 * sin(seed * 1.7));
  vec2 w;
  float n;
  float F = blot(q, t * 0.2 + seed * 7.3, 0.1 + 0.15 * uP.y, w, n);
  float aa = 0.006;
  float ink = smoothstep(-aa, aa, F);
  float echo = exp(-sq((F - 0.18) / 0.012)) + exp(-sq((F - 0.36) / 0.012)) * step(1.0, uP.z);
  vec3 pap = paper(frag, p);
  vec3 col = mix(pap, uC1, ink);
  col = mix(col, uC2, echo * 0.9);
  // Inversión en los cortes; con agudos, parpadeo de como mucho 2,5 Hz.
  float flick = step(0.5, fract(clk * 2.5)) * step(0.5, uD.z * uX.w);
  float inv = clamp(uX.x + flick, 0.0, 1.0);
  vec3 inverted = mix(uC1, pap, ink);
  inverted = mix(inverted, uC3, echo * 0.9);
  col = mix(col, inverted, inv);
  col = mix(col, uC3, uD.y * 0.06);
  float cover = mix(max(ink, echo), 1.0 - ink * (1.0 - echo), inv);
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
