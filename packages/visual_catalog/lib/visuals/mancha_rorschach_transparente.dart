// Mancha de Rorschach Transparente — tinta simétrica que respira sobre papel.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Un campo de ruido fractal deformado se refleja en espejo a ambos lados del
// eje vertical (o en cuatro, con la simetría cuádruple) y donde supera un
// umbral se pinta tinta. Como la tinta real, se acumula más oscura en los
// bordes y es más fina por dentro; una segunda tinta roja ocupa sus propias
// zonas. El papel crema tiene fibras. La mancha cambia de forma despacio;
// los graves la hacen crecer, cada golpe la expande de golpe y deja
// salpicaduras de gotas alrededor del borde.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('simetria', 'Simetría', options: ['Espejo', 'Cuádruple']),
  CreatorModifier.slider('tamano', 'Tamaño de la mancha', min: .6, max: 1.5, value: 1),
  CreatorModifier.slider('cambio', 'Velocidad de cambio', min: .2, max: 2, value: 1),
  CreatorModifier.toggle('roja', 'Tinta roja', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double morph = 0;
  float spread = 0, spreadVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    morph = rng.unit() * 40.0;
    spread = spreadVel = 0;
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
    if (hit > kick + 0.2f) spreadVel += 2.2f * hit;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // Muelle: la mancha se expande de golpe y vuelve despacio.
    spreadVel += (-spread * 18.0f - spreadVel * 5.0f) * dt;
    spread += spreadVel * dt;
    morph += f.delta * f.speed * m.cambio * (0.12 + 0.3 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    float t = float(std::fmod(morph, 1000.0));
    std::vector<float> u;
    u.reserve(48);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(m.simetria), m.tamano, m.roja ? 1.0f : 0.0f, std::max(-0.2f, spread) * amp});
    u.insert(u.end(), {f.glow, flash * amp, spark * amp, 0.0f});
    // Lóbulos de la mancha: cinco manchas grandes que derivan despacio.
    static const float lx[5] = {0.1f, 0.26f, 0.16f, 0.28f, 0.07f};
    static const float ly[5] = {-0.55f, -0.2f, 0.12f, 0.42f, 0.55f};
    static const float lr[5] = {0.14f, 0.16f, 0.18f, 0.14f, 0.12f};
    for (int k = 0; k < 5; k++) {
      float fk = float(k);
      u.insert(u.end(), {lx[k] + 0.07f * std::sin(t * 0.7f + fk * 1.9f), ly[k] + 0.07f * std::cos(t * 0.5f + fk * 2.7f), lr[k], 0.0f});
    }
    // Dos lóbulos de tinta roja.
    u.insert(u.end(), {0.24f + 0.05f * std::sin(t * 0.4f), -0.42f + 0.06f * std::cos(t * 0.3f), 0.3f, 0.38f + 0.05f * std::sin(t * 0.5f)});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("inkblot", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // cambio, graves, golpe, energía
uniform vec4 uB;   // simetría, tamaño, tinta roja, expansión
uniform vec4 uD;   // glow, destello, agudos
uniform vec4 uL0;  // lóbulos: x, y, radio
uniform vec4 uL1;
uniform vec4 uL2;
uniform vec4 uL3;
uniform vec4 uL4;
uniform vec4 uR;   // lóbulos rojos: centro 1 (x, y), centro 2 (x, y)
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

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  // Espejo: la tinta se dobla sobre el eje como al plegar el papel.
  vec2 q = vec2(abs(p.x), p.y);
  if (uB.x > 0.5) q.y = abs(q.y);
  q /= uB.y;
  // Deformación lenta del campo para que la mancha cambie de forma.
  float w1 = noise(q * 2.2 + vec2(t * 0.6, 0.0));
  vec2 w = vec2(w1, noise(q * 2.2 + vec2(4.3, -t * 0.5))) - 0.5;
  float n = fbm(q * 3.6 + w * 1.4 + vec2(0.0, t * 0.25));
  float grow = 0.1 * uA.y + 0.2 * uB.w;
  vec2 qw = q + w * 0.08;
  float env = lobe(qw, uL0) + lobe(qw, uL1) + lobe(qw, uL2) + lobe(qw, uL3) + lobe(qw, uL4);
  // El eje central siempre tiene tinta, como al plegar el papel.
  env += 0.9 * exp(-q.x * q.x / 0.004) * (1.0 - smoothstep(0.55, 0.95, abs(q.y)));
  float F = env * 0.8 + (n - 0.5) * 1.1 - 0.5 + grow;
  // Tinta roja: dos lóbulos propios, con bordes del mismo ruido.
  vec2 r1 = q - uR.xy;
  vec2 r2 = q - vec2(uR.z, uR.w);
  float redEnv = exp(-dot(r1, r1) / 0.03) + 0.8 * exp(-dot(r2, r2) / 0.02);
  float R = (redEnv * 0.8 + (n - 0.5) * 1.0 - 0.45 + grow) * uB.z;

  // Papel crema con fibras.
  float fiber = hash12(floor(frag * vec2(0.5, 0.08))) * 0.6 + w1 * 0.4;
  vec3 col = uC0 * (0.93 + 0.07 * fiber);
  col *= 1.0 - 0.16 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  float aa = 0.008;
  // Aureola: el papel absorbe un poco de tinta alrededor del borde.
  col *= 1.0 - 0.12 * smoothstep(-0.12, 0.0, F);
  // Tinta negra: densidad suave por dentro y más oscura en el borde.
  float ink = smoothstep(-aa, aa, F);
  float rim = smoothstep(0.12, 0.0, F);
  float density = 0.75 + 0.25 * smoothstep(0.3, 0.7, w1 + 0.3 * n);
  vec3 inkCol = uC1 + (uC0 - uC1) * 0.12 * (1.0 - density) * (1.0 - rim);
  col = mix(col, inkCol, ink);
  // Tinta roja encima, con su borde más oscuro.
  float red = smoothstep(-aa, aa, R);
  float redRim = smoothstep(0.1, 0.0, R);
  vec3 redCol = mix(uC2 * (0.9 + 0.2 * n), uC3, redRim * 0.75);
  col = mix(col, redCol * (1.0 + 0.25 * uA.z), red);
  float cover = max(ink, red);
  // Salpicaduras: gotas al azar cerca del borde, de tamaños distintos.
  if (F > -0.22 && F < -0.02) {
    vec2 g = q * 34.0;
    vec2 cell = floor(g);
    float hs = hash12(cell);
    vec2 off = vec2(hash12(cell + 3.1), hash12(cell + 7.7)) - 0.5;
    float rad = 0.08 + 0.22 * hash12(cell + 11.3);
    float dropShape = 1.0 - smoothstep(rad - 0.04, rad, length(fract(g) - 0.5 - off * 0.5));
    float drop = step(0.86 - 0.08 * uA.z - 0.05 * uD.z, hs) * dropShape;
    col = mix(col, uC1, drop);
    cover = max(cover, drop);
  }
  col = mix(col, uC2, uD.y * 0.03);
  // Fondo transparente: el papel desaparece y sólo queda la tinta.
  float inkAlpha = clamp(cover, 0.0, 1.0);
  fragColor = vec4(clamp(col, 0.0, 1.0) * inkAlpha, inkAlpha);
}
""",
};
