// Rorschach Ojos — la mancha te está mirando.
// Dentro de la tinta se abren ojos, muchos o uno solo gigante, con su
// blanco lleno de venillas, el iris rojo y la pupila negra. Parpadean cada
// uno a su ritmo y, lo peor, todos miran hacia el mismo sitio y lo siguen;
// o se mueven nerviosos a saltos, o cada uno se pierde por su lado. Con
// cada golpe de la música todos se cierran a la vez; los graves dilatan
// las pupilas y los agudos encienden los iris.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('ojos', 'Ojos', options: ['Muchos', 'Pocos y grandes', 'Uno gigante']),
  CreatorModifier.choice('mirada', 'Mirada', options: ['Te sigue', 'Nerviosa', 'Perdida']),
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
  CreatorModifier.slider('venas', 'Venas', min: 0, max: 1, value: .5),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Te Observan', {'ojos': 'Muchos', 'mirada': 'Te sigue', 'venas': .9}),
  CreatorVariation('Cíclope', {'ojos': 'Uno gigante', 'mirada': 'Nerviosa', 'pulso': 'Graves'}),
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
    if (!mu.active && sinceIdle > 2.6) {
      sinceIdle -= 2.6;
      sinceBeat = sinceIdle;
      beatPower = 0.7f;
      beats++;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    spreadVel += (-spread * 18.0f - spreadVel * 5.0f) * dt;
    spread += spreadVel * dt;
    clock += f.delta * f.speed;
    morph += f.delta * f.speed * (0.14 + 0.35 * drive) * 0.7;

  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    float amp = f.intensity;
    float t = float(std::fmod(morph, 1000.0));
    float pulse = sinceBeat < 2.0 ? beatPower * float(std::exp(-sinceBeat * 3.0)) : 0.0f;
    std::vector<float> u;
    u.reserve(56);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {g.ojos.weight(0), g.ojos.weight(1), g.ojos.weight(2), std::clamp(g.venas, 0.0f, 1.0f)});
    u.insert(u.end(), {f.glow, flash * amp, spark * amp, float(std::fmod(clock, 1000.0))});
    // Lóbulos de la mancha: cinco manchas grandes que derivan despacio.
    static const float lx[5] = {0.12f, 0.24f, 0.2f, 0.32f, 0.08f};
    static const float ly[5] = {-0.32f, -0.12f, 0.1f, 0.3f, 0.5f};
    static const float lr[5] = {0.15f, 0.16f, 0.15f, 0.13f, 0.11f};
    for (int k = 0; k < 5; k++) {
      float fk = float(k);
      u.insert(u.end(), {lx[k] + 0.07f * std::sin(t * 0.7f + fk * 1.9f), ly[k] + 0.07f * std::cos(t * 0.5f + fk * 2.7f), lr[k], 0.0f});
    }
    {
      // A dónde miran: un punto que pasea, saltos nerviosos o cada uno a lo suyo.
      const float lt = float(std::fmod(clock, 1000.0));
      const float jump = std::floor(lt * 3.0f);
      const float tx = 0.6f * std::sin(lt * 0.7f) * g.mirada.weight(0) + 0.8f * std::sin(jump * 7.13f) * g.mirada.weight(1);
      const float ty = 0.5f * std::cos(lt * 0.53f) * g.mirada.weight(0) + 0.7f * std::cos(jump * 5.31f) * g.mirada.weight(1);
      u.insert(u.end(), {tx, ty, g.mirada.weight(2), 0.75f + 0.25f * f.detail});
      u.insert(u.end(), {g.pulso.weight(0), g.pulso.weight(1), g.pulso.weight(2), 0.0f});
    }
    u.insert(u.end(), {pulse, std::max(-0.2f, spread) * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("inkblot_eyes", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_eyes': r"""
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
uniform vec4 uY;   // más datos de la variante
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
  vec2 q = vec2(abs(p.x), p.y);
  vec2 w;
  float n;
  float F = blot(q, t, 0.12 + 0.08 * uA.y + 0.15 * uP.y, w, n);
  vec3 col = paper(frag, p);
  float aa = 0.008;
  float ink = smoothstep(-aa, aa, F);
  col = mix(col, uC1 + (uC2 - uC1) * 0.12 * n, ink);
  float cover = ink;
  // Ojos en una rejilla dentro de la tinta; o uno solo gigante en el centro.
  float giant = step(0.5, uB.z);
  float cs = (uB.x * 0.13 + uB.y * 0.24 + uB.z * 0.24) / uX.w;
  vec2 cell = floor(q / cs);
  cell = mix(cell, vec2(0.0), giant);
  vec2 h = vec2(hash12(cell + 7.3), hash12(cell + 19.1));
  vec2 c = mix((cell + 0.5 + (h - 0.5) * 0.25) * cs, vec2(0.0, -0.02), giant);
  float er = mix(cs * 0.42, 0.3, giant);
  vec2 e = (q - c) / er;
  float present = smoothstep(0.05, 0.25, F) * max(step(hash12(cell + 3.7), 0.8), giant);
  // Parpadeo: cada ojo a su ritmo; los golpes los cierran todos.
  float bl = fract(clk * (0.18 + 0.1 * h.x) + h.y);
  float open = (1.0 - exp(-sq((bl - 0.5) / 0.025))) * (1.0 - 0.95 * uP.x * uY.x);
  float lid = open * 0.62 * max(1.0 - e.x * e.x, 0.0);
  float eyeMask = smoothstep(lid + 0.05, lid - 0.05, abs(e.y)) * step(abs(e.x), 1.0) * present;
  // La mirada: los de la izquierda miran al mismo punto de la pantalla.
  if (present * step(abs(e.y), 0.75) * step(abs(e.x), 1.0) > 0.0) {
  vec2 look = clamp(uX.xy, -1.0, 1.0) * 0.45;
  vec2 lost = (vec2(hash12(cell + 1.0), hash12(cell + 2.0)) - 0.5) * 0.9 * vec2(sin(clk * 0.3 + h.x * 6.0), cos(clk * 0.25 + h.y * 6.0));
  look = mix(look, lost, uX.z);
  look.x *= p.x < 0.0 ? -1.0 : 1.0;
  vec2 ie = e - look;
  float iris = smoothstep(0.45, 0.39, length(ie));
  float pupilR = 0.17 * (1.0 + 0.9 * uA.y * uY.y);
  float pupil = smoothstep(pupilR + 0.02, pupilR - 0.02, length(ie));
  vec3 sclera = uC3 * (0.95 - 0.25 * length(e));
  float vein = smoothstep(0.06, 0.0, abs(noise(e * 6.0 + cell * 3.0) - 0.5)) * smoothstep(0.3, 1.0, length(e));
  sclera = mix(sclera, uC2 * 0.85, vein * uB.w);
  vec3 irisCol = uC2 * (0.55 + 0.6 * noise(vec2(atan(ie.y, ie.x) * 3.0, length(ie) * 8.0))) * (1.0 + 1.6 * uD.z * uY.z);
  vec3 eye = mix(sclera, irisCol, iris);
  eye = mix(eye, uC1 * 0.3, pupil);
  eye += uC3 * smoothstep(0.09, 0.0, length(ie - vec2(-0.13, -0.15))) * 0.9;
  float lidLine = smoothstep(0.07, 0.0, abs(abs(e.y) - lid)) * step(abs(e.x), 1.0) * present;
  col = mix(col, eye, eyeMask);
  col = mix(col, uC1, lidLine * 0.85);
  cover = max(cover, eyeMask);
  }
  col = mix(col, uC2, uD.y * 0.04);
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
