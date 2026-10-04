// Rorschach Glitch Transparente — la mancha como una señal que se corrompe.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// La mancha de tinta cambia de forma rápido y se rompe: franjas de la imagen
// se desplazan a los lados, aparecen copias fantasma desplazadas en rojo y
// amarillo y, con cada golpe, la imagen se invierte en negativo un instante.
// Bloques de ruido y líneas de barrido completan la avería. Cuanta más
// energía, más se rompe.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.5, value: 1),
  CreatorModifier.slider('rasgado', 'Rasgado', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('inversion', 'Negativo con golpes', value: true),
  CreatorModifier.toggle('fantasmas', 'Copias fantasma', value: true),
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
    if (!mu.active && sinceIdle > 1.5) {
      sinceIdle -= 1.5;
      sinceBeat = sinceIdle;
      beatPower = 0.7f;
      beats++;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    spreadVel += (-spread * 18.0f - spreadVel * 5.0f) * dt;
    spread += spreadVel * dt;
    clock += f.delta * f.speed;
    morph += f.delta * f.speed * (0.14 + 0.35 * drive) * 2.2;

  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    float t = float(std::fmod(morph, 1000.0));
    float pulse = sinceBeat < 2.0 ? beatPower * float(std::exp(-sinceBeat * 3.0)) : 0.0f;
    std::vector<float> u;
    u.reserve(56);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {m.rasgado, m.tamano, m.inversion ? 1.0f : 0.0f, m.fantasmas ? 1.0f : 0.0f});
    u.insert(u.end(), {f.glow, flash * amp, spark * amp, float(std::fmod(clock, 1000.0))});
    // Lóbulos de la mancha: cinco manchas grandes que derivan despacio.
    static const float lx[5] = {0.1f, 0.26f, 0.16f, 0.28f, 0.07f};
    static const float ly[5] = {-0.5f, -0.2f, 0.12f, 0.4f, 0.55f};
    static const float lr[5] = {0.14f, 0.16f, 0.18f, 0.14f, 0.12f};
    for (int k = 0; k < 5; k++) {
      float fk = float(k);
      u.insert(u.end(), {lx[k] + 0.07f * std::sin(t * 0.7f + fk * 1.9f), ly[k] + 0.07f * std::cos(t * 0.5f + fk * 2.7f), lr[k], 0.0f});
    }
    float invert = m.inversion && sinceBeat < 0.12 ? 1.0f : 0.0f;
    u.insert(u.end(), {float(beats % 97), std::clamp((0.15f + 0.6f * drive + 1.2f * pulse) * m.rasgado, 0.0f, 2.0f), invert, 0.02f + 0.05f * pulse + 0.02f * energy});
    u.insert(u.end(), {pulse, std::max(-0.2f, spread) * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("inkblot_glitch", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_glitch': r"""
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

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  // Rasgado: franjas horizontales que saltan a los lados.
  float band = floor(frag.y / 14.0);
  float h = hash12(vec2(band, uX.x + floor(uD.w * 8.0)));
  float shift = step(0.72, h) * (h - 0.72) * 3.5 * uX.y * 0.25;
  vec2 ps = p + vec2(shift, 0.0);
  vec2 q = vec2(abs(ps.x), ps.y) / uB.y;
  vec2 w;
  float n;
  float F = blot(q, t, 0.1 * uA.y + 0.2 * uP.y, w, n);
  float aa = 0.008;
  float ink = smoothstep(-aa, aa, F);
  vec3 col = paper(frag, p);
  col = mix(col, uC1, ink);
  float cover = ink;
  // Copias fantasma desplazadas en rojo y amarillo.
  if (uB.w > 0.5) {
    vec2 o = vec2(uX.w, 0.0);
    // El fantasma reutiliza la textura de la tinta y desplaza sólo su contorno.
    vec2 qg = vec2(abs(ps.x + o.x), ps.y + o.x * 0.3) / uB.y + w * 0.08;
    float envG = lobe(qg, uL0) + lobe(qg, uL1) + lobe(qg, uL2) + lobe(qg, uL3) + lobe(qg, uL4);
    envG += 0.9 * exp(-qg.x * qg.x / 0.004) * (1.0 - smoothstep(0.55, 0.95, abs(qg.y)));
    float Fg = envG * 0.8 + (n - 0.5) * 1.1 - 0.5 + 0.1 * uA.y;
    float g1 = smoothstep(-aa, aa, Fg) * (1.0 - ink);
    // Contorno amarillo desdoblado alrededor de la mancha.
    float g2 = smoothstep(0.0, -0.05, F) * smoothstep(-0.14, -0.07, F) * (1.0 - g1);
    col = mix(col, uC2, g1 * 0.85);
    col = mix(col, uC3, g2 * 0.85);
    cover = max(cover, max(g1, g2) * 0.85);
  }
  // Bloques de ruido digital.
  vec2 blk = floor(frag / vec2(24.0, 10.0));
  float bh = hash12(blk + floor(uD.w * 12.0));
  float block = step(0.985 - 0.05 * uX.y, bh);
  col = mix(col, vec3(hash12(blk * 1.3), hash12(blk * 2.1), hash12(blk * 3.7)) * vec3(1.0, 0.4, 0.2), block * 0.7);
  cover = max(cover, block * 0.7);
  // Negativo con el golpe.
  if (uX.z > 0.5) col = vec3(1.0) - col;
  col *= 0.9 + 0.1 * step(0.5, fract(frag.y / 3.0));
  col = mix(col, uC2, uD.y * 0.04);
  // Fondo transparente: el papel desaparece y sólo queda lo pintado.
  float inkAlpha = clamp(cover, 0.0, 1.0);
  fragColor = vec4(clamp(col, 0.0, 1.0) * inkAlpha, inkAlpha);
}
""",
};
