// Rorschach Demonio — lo que ves en la mancha te devuelve la mirada.
// La tinta forma una cabeza con cuernos que se curvan hacia arriba, ojos
// rasgados que arden como brasas y una boca de colmillos. Respira despacio,
// se queda quieto acechando o convulsiona. Con cada golpe de la música
// abre la boca en un rugido y le arden los ojos; los graves la hinchan y
// los agudos hacen saltar chispas. Puede verse sobre papel o sobre sangre.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('cuernos', 'Cuernos', min: 0, max: 1, value: .7),
  CreatorModifier.choice('acecho', 'Acecho', options: ['Respira', 'Quieto', 'Convulsiona']),
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
  CreatorModifier.slider('brasas', 'Brasas', min: 0, max: 1, value: .5),
  CreatorModifier.toggle('sangre', 'Papel de sangre', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Bestia', {'cuernos': 1, 'acecho': 'Convulsiona', 'brasas': 1, 'sangre': true}),
  CreatorVariation('Sonrisa', {'cuernos': .25, 'acecho': 'Quieto', 'pulso': 'Graves'}),
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
    u.insert(u.end(), {std::clamp(g.cuernos, 0.0f, 1.0f), std::clamp(g.brasas, 0.0f, 1.0f), std::clamp(g.sangre, 0.0f, 1.0f), f.detail});
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
      const float conv = g.acecho.weight(2);
      const float jx = conv * 0.012f * std::sin(lt * 37.0f) * std::sin(lt * 5.3f);
      const float jy = conv * 0.01f * std::cos(lt * 29.0f);
      const float breath = g.acecho.weight(0) * 0.04f * std::sin(lt * 1.6f);
      u.insert(u.end(), {jx, jy, breath, g.pulso.weight(0)});
      u.insert(u.end(), {g.pulso.weight(1), g.pulso.weight(2), 0.0f, 0.0f});
    }
    u.insert(u.end(), {pulse, std::max(-0.2f, spread) * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("inkblot_demon", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_demon': r"""
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

float seg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p0 = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  float clk = uD.w;
  vec2 p = (p0 - uX.xy) * (1.0 - uX.z);
  vec2 q = vec2(abs(p.x), p.y);
  float roar = clamp(uP.x * uX.w * 1.3, 0.0, 1.0);
  vec2 w;
  float n;
  float F = blot(q, t, 0.1 + 0.12 * uA.y * uY.x + 0.1 * uP.y, w, n);
  // La cabeza siempre tiene tinta.
  F = max(F, (0.25 - length((q - vec2(0.0, -0.04)) / vec2(0.85, 1.0))) * 3.0);
  // Cuernos: curvas gruesas en la base que suben y se abren.
  float hk = uB.x;
  vec2 b0 = vec2(0.12, -0.24);
  vec2 b1 = vec2(0.2, -0.5 - 0.12 * hk);
  vec2 b2 = vec2(0.36 + 0.1 * hk, -0.52 - 0.28 * hk);
  float horn = -1.0;
  vec2 prev = b0;
  bool hornZone = q.y < -0.18 && q.y > -0.95 && q.x < 0.62 && hk > 0.02;
  for (int i = 1; i <= 8; i++) {
    if (!hornZone) break;
    float s = float(i) / 8.0;
    vec2 cur = mix(mix(b0, b1, s), mix(b1, b2, s), s);
    float wdt = 0.055 * (1.0 - s * 0.92) * (0.4 + 0.6 * hk);
    horn = max(horn, (wdt - seg(q, prev, cur)) * 6.0);
    prev = cur;
  }
  F = max(F, horn * step(0.02, hk));
  float aa = 0.007;
  float ink = smoothstep(-aa, aa, F);
  vec3 pap = paper(frag, p0);
  pap = mix(pap, uC2 * 0.4 + uC1 * 0.2, uB.z);
  float rim = smoothstep(0.1, 0.0, F);
  vec3 inkCol = mix(uC1, uC2 * 0.5, rim * 0.8);
  vec3 col = mix(pap, inkCol, ink);
  float cover = ink;
  // Ojos rasgados que arden.
  vec2 ed = q - vec2(0.11, -0.1);
  float ca = cos(0.4);
  float sa = sin(0.4);
  vec2 e = vec2(ca * ed.x + sa * ed.y, -sa * ed.x + ca * ed.y) / vec2(0.075, 0.028 + 0.012 * roar);
  float el = length(e);
  float eye = smoothstep(1.05, 0.95, el);
  float slit = smoothstep(0.22, 0.12, abs(e.x)) * eye;
  float flick = 1.0 + 0.6 * uD.z * uY.y * (0.5 + 0.5 * sin(clk * 40.0));
  vec3 eyeCol = mix(uC3, uC2, clamp(el, 0.0, 1.0)) * (1.2 + roar) * flick;
  col = mix(col, eyeCol, eye);
  col = mix(col, uC1, slit * 0.9);
  col += uC2 * exp(-el * 1.3) * 0.3 * uD.x * flick;
  // Boca: una sonrisa de colmillos que se abre en un rugido.
  float mw = 0.22;
  float mx = clamp(q.x / mw, 0.0, 1.0);
  float my = 0.17 - 0.05 * mx * mx;
  float o = 0.03 + 0.07 * roar + 0.01 * sin(clk * 2.0);
  float inMouth = step(q.x, mw) * smoothstep(o * (1.0 - mx * mx) + 0.004, o * (1.0 - mx * mx) - 0.004, abs(q.y - my));
  float tooth = 1.0 - abs(fract(q.x * 18.0) * 2.0 - 1.0);
  float upper = step(q.y, my - o + o * 1.4 * tooth) * step(my - o - 0.01, q.y);
  float lower = step(my + o - o * 1.2 * tooth, q.y) * step(q.y, my + o + 0.01);
  vec3 throat = mix(uC1, uC2, 0.35 + 0.5 * roar) * (0.5 + 0.7 * (1.0 - abs(q.y - my) / max(o, 0.001))) + uC3 * 0.25 * roar;
  col = mix(col, throat, inMouth);
  col = mix(col, mix(pap, uC3, 0.15) * 0.95, clamp(upper + lower, 0.0, 1.0) * inMouth);
  cover = max(cover, max(eye, inMouth));
  // Brasas que suben alrededor.
  vec2 bg = p0 * vec2(14.0, 8.0) + vec2(0.0, clk * 0.6);
  vec2 bc = floor(bg);
  float bh = hash12(bc);
  float ember = step(1.0 - 0.1 * uB.y, bh) * smoothstep(0.25, 0.0, length(fract(bg) - 0.5 - (vec2(hash12(bc + 3.1), hash12(bc + 5.7)) - 0.5) * 0.5));
  col += mix(uC2, uC3, bh) * ember * (0.6 + 0.4 * sin(clk * 9.0 + bh * 30.0)) * (1.0 + uD.z * uY.y);
  cover = max(cover, ember * uB.y);
  col = mix(col, uC2, uD.y * 0.05);
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
