// Rorschach Calavera — el hueco de la tinta tiene forma de calavera.
// En el centro de la mancha, el papel en blanco dibuja una calavera: el
// cráneo, los pómulos, las cuencas negras con dos brasas al fondo, la
// nariz y los dientes. La mandíbula castañea, habla o se queda quieta, y
// con cada golpe de la música se abre en una carcajada. Todo puede
// derretirse y gotear hacia abajo. En modo negativo, la calavera es de
// tinta sobre el papel.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('presencia', 'Presencia', min: 0, max: 1, value: .85),
  CreatorModifier.choice('mandibula', 'Mandíbula', options: ['Castañea', 'Habla', 'Quieta']),
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
  CreatorModifier.slider('derretir', 'Derretirse', min: 0, max: 1, value: .3),
  CreatorModifier.toggle('negativo', 'Calavera de tinta', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Memento Mori', {'presencia': 1, 'mandibula': 'Castañea', 'derretir': .15}),
  CreatorVariation('Derretida', {'derretir': 1, 'mandibula': 'Habla', 'pulso': 'Graves', 'negativo': true}),
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
    if (!mu.active && sinceIdle > 2.0) {
      sinceIdle -= 2.0;
      sinceBeat = sinceIdle;
      beatPower = 0.7f;
      beats++;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    spreadVel += (-spread * 18.0f - spreadVel * 5.0f) * dt;
    spread += spreadVel * dt;
    clock += f.delta * f.speed;
    morph += f.delta * f.speed * (0.14 + 0.35 * drive) * 0.6;

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
    u.insert(u.end(), {std::clamp(g.presencia, 0.0f, 1.0f), std::clamp(g.derretir, 0.0f, 1.0f), std::clamp(g.negativo, 0.0f, 1.0f), f.detail});
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
      const float lt = float(std::fmod(clock, 1000.0));
      const float chatter = std::max(0.0f, std::sin(lt * 14.0f)) * (0.5f + 0.5f * std::sin(lt * 1.3f));
      const float talk = 0.5f + 0.5f * std::sin(lt * 5.0f) * std::sin(lt * 1.7f + 1.0f);
      const float jaw = g.mandibula.weight(0) * chatter + g.mandibula.weight(1) * talk;
      u.insert(u.end(), {jaw, g.pulso.weight(0), g.pulso.weight(1), g.pulso.weight(2)});
      u.insert(u.end(), {std::min(spark * amp, 1.0f), 0.0f, 0.0f, 0.0f});
    }
    u.insert(u.end(), {pulse, std::max(-0.2f, spread) * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("inkblot_skull", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_skull': r"""
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
  // Derretirse: todo gotea hacia abajo.
  float melt = uB.y;
  vec2 pm = p;
  pm.y -= melt * 0.06 * (0.5 + 0.5 * sin(p.x * 23.0 + 1.3)) * smoothstep(-0.3, 0.6, p.y) * (0.6 + 0.4 * sin(clk * 0.7 + p.x * 9.0));
  vec2 q = vec2(abs(pm.x), pm.y);
  vec2 w;
  float n;
  float F = blot(q, t, 0.12 + 0.1 * uA.y * uX.z + 0.12 * uP.y, w, n);
  float pr = uB.x;
  // Calavera: cráneo, pómulos y mandíbula.
  float jaw = uX.x * 0.6 + uP.x * uX.y * 0.9;
  vec2 s = q / (0.95 + 0.08 * uA.y * uX.z);
  float cranium = length((s - vec2(0.0, -0.14)) / vec2(0.27, 0.25)) - 1.0;
  float cheek = length((s - vec2(0.0, 0.06)) / vec2(0.22, 0.14)) - 1.0;
  float jo = jaw * 0.05;
  float mandible = length((s - vec2(0.0, 0.2 + jo)) / vec2(0.16, 0.09)) - 1.0;
  float skull = min(min(cranium, cheek), mandible);
  float skullMask = smoothstep(0.03, -0.03, skull) * pr;
  // La tinta siempre rodea la calavera.
  F = max(F, (0.18 - max(skull, 0.0) * 0.6) * pr);
  float aa = 0.007;
  float ink = smoothstep(-aa, aa, F);
  // Cuencas, nariz, dientes y la boca abierta: huecos.
  float socket = smoothstep(0.05, -0.05, length((s - vec2(0.1, -0.07)) / vec2(0.075, 0.065)) - 1.0);
  float nose = smoothstep(0.004, -0.004, max(max(0.02 - s.y, s.y - 0.1), s.x - (s.y - 0.02) * 0.5));
  float mouth = step(s.x, 0.11) * step(0.17, s.y) * step(s.y, 0.17 + jo);
  float upperTeeth = step(s.x, 0.11) * step(0.13, s.y) * step(s.y, 0.17);
  float lowerTeeth = step(s.x, 0.11) * step(0.17 + jo, s.y) * step(s.y, 0.21 + jo);
  float gaps = step(fract(s.x * 30.0), 0.14) * (upperTeeth + lowerTeeth);
  float holes = clamp(socket + nose + mouth + gaps, 0.0, 1.0) * skullMask;
  vec3 pap = paper(frag, p);
  vec3 inkCol = uC1 + (uC2 - uC1) * 0.15 * n;
  // Normal: hueso de papel dentro de la tinta. Negativo: hueso de tinta.
  vec3 bone = mix(pap * 0.97, inkCol, uB.z);
  vec3 hole = mix(inkCol, pap, uB.z);
  vec3 col = mix(pap, inkCol, ink);
  col = mix(col, bone, skullMask);
  col = mix(col, hole, holes);
  // Dos brasas al fondo de las cuencas.
  float ember = exp(-length((s - vec2(0.1, -0.07)) / 0.025));
  float flicker = 0.7 + 0.3 * sin(clk * 9.0) + 1.2 * uY.x * uX.w;
  col += mix(uC2, uC3, ember) * ember * flicker * pr * (0.8 + 0.4 * uD.x);
  // Gotas que caen de la tinta al derretirse.
  float colx = fract(q.x * 12.0);
  float dropLen = melt * 0.35 * hash12(vec2(floor(q.x * 12.0), 3.0));
  float drip = smoothstep(0.12, 0.0, abs(colx - 0.5)) * step(0.3, pm.y) * step(pm.y, 0.3 + dropLen) * step(-0.12, F) * step(q.x, 0.32);
  col = mix(col, inkCol, drip);
  float cover = max(max(ink, skullMask), drip);
  col = mix(col, uC2, uD.y * 0.04);
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
