// Rorschach Mercurio — la mancha hecha de metal líquido.
// En vez de tinta, mercurio: la mancha brilla como cromo, abombada, y
// refleja lo que la rodea (fuego, focos de estudio o un horizonte), con un
// borde que se oscurece como el metal de verdad. Unas gotas sueltas orbitan
// y se funden con ella. Cada golpe de la música manda una onda por la
// superficie, los graves la hinchan y los agudos la hacen centellear.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('gotas', 'Gotas sueltas', min: 0, max: 8, value: 4),
  CreatorModifier.slider('viscosidad', 'Viscosidad', min: 0, max: 1, value: .4),
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
  CreatorModifier.choice('entorno', 'Reflejos', options: ['Fuego', 'Estudio', 'Horizonte']),
  CreatorModifier.toggle('cuatro', 'Cuatro espejos', value: false),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Mercurio Puro', {'entorno': 'Estudio', 'gotas': 6, 'viscosidad': .2}),
  CreatorVariation('Metal Fundido', {'entorno': 'Fuego', 'viscosidad': .9, 'pulso': 'Graves', 'cuatro': true}),
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
    if (!mu.active && sinceIdle > 2.2) {
      sinceIdle -= 2.2;
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
    float amp = f.intensity;
    float t = float(std::fmod(morph, 1000.0));
    float pulse = sinceBeat < 2.0 ? beatPower * float(std::exp(-sinceBeat * 3.0)) : 0.0f;
    std::vector<float> u;
    u.reserve(56);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {g.gotas, std::clamp(g.viscosidad, 0.0f, 1.0f), std::clamp(g.cuatro, 0.0f, 1.0f), f.detail});
    u.insert(u.end(), {f.glow, flash * amp, spark * amp, float(std::fmod(clock, 1000.0))});
    // Lóbulos de la mancha: cinco manchas grandes que derivan despacio.
    static const float lx[5] = {0.12f, 0.24f, 0.2f, 0.32f, 0.08f};
    static const float ly[5] = {-0.32f, -0.12f, 0.1f, 0.3f, 0.5f};
    static const float lr[5] = {0.15f, 0.16f, 0.15f, 0.13f, 0.11f};
    for (int k = 0; k < 5; k++) {
      float fk = float(k);
      u.insert(u.end(), {lx[k] + 0.07f * std::sin(t * 0.7f + fk * 1.9f), ly[k] + 0.07f * std::cos(t * 0.5f + fk * 2.7f), lr[k], 0.0f});
    }
    u.insert(u.end(), {g.entorno.weight(0), g.entorno.weight(1), g.entorno.weight(2), sinceBeat < 3.0 ? float(sinceBeat) : 3.0f});
    u.insert(u.end(), {g.pulso.weight(0), g.pulso.weight(1), g.pulso.weight(2), 0.0f});
    u.insert(u.end(), {pulse, std::max(-0.2f, spread) * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("inkblot_mercury", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'inkblot_mercury': r"""
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

vec3 lobeG(vec2 q, vec4 L) {
  vec2 d = q - L.xy;
  float e = exp(-dot(d, d) / (L.z * L.z));
  return vec3(e, -2.0 * d / (L.z * L.z) * e);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  float clk = uD.w;
  vec2 q = vec2(abs(p.x), p.y);
  q.y = mix(q.y, abs(q.y), step(0.5, uB.z));
  // Campo suave con su gradiente exacto: la forma del metal.
  vec2 w = vec2(noise(q * 2.2 + vec2(t * 0.6, 0.0)), noise(q * 2.2 + vec2(4.3, -t * 0.5))) - 0.5;
  vec2 qw = q + w * 0.08 * (1.2 - uB.y);
  vec3 env = lobeG(qw, uL0) + lobeG(qw, uL1) + lobeG(qw, uL2) + lobeG(qw, uL3) + lobeG(qw, uL4);
  float axis = 0.9 * exp(-q.x * q.x / 0.004) * (1.0 - smoothstep(0.55, 0.95, abs(q.y)));
  env += vec3(axis, -2.0 * q.x / 0.004 * axis, 0.0);
  // Gotas sueltas que orbitan y se funden con la mancha.
  for (int k = 0; k < 8; k++) {
    float fk = float(k);
    if (fk >= uB.x) break;
    float a = clk * (0.25 + 0.05 * fk) + fk * 2.4;
    vec2 c = vec2(0.18 + 0.2 * fract(fk * 0.37), 0.0) + vec2(0.12 * cos(a), 0.55 * sin(a * 0.7 + fk));
    env += lobeG(q, vec4(c, 0.045 + 0.012 * fract(fk * 0.61), 0.0)) * 0.9;
  }
  float grow = 0.06 + 0.14 * uA.y * uY.y + 0.15 * uP.y;
  float fine = (noise(q * 7.0 + w * 2.0 + vec2(0.0, t * 0.3)) - 0.5) * 0.12 * (1.0 - uB.y);
  float F = env.x * 0.8 - 0.5 + grow + fine;
  vec2 grad = env.yz * 0.8;
  grad.x *= p.x < 0.0 ? -1.0 : 1.0;
  float aa = 1.5 / scale * 4.0;
  float mask = smoothstep(-aa * 0.25, aa * 0.25, F);
  // Fondo oscuro con la sombra del metal.
  vec3 col = uC0 * (1.0 + 0.5 * (1.0 - length(p * vec2(0.9, 0.6))));
  col *= 1.0 - 0.6 * exp(-max(-F, 0.0) * 10.0);
  if (mask > 0.0) {
  float depth = clamp(F / 0.25, 0.0, 1.0);
  vec2 dir = grad / (length(grad) + 1e-4);
  vec3 nrm = normalize(vec3(dir * (1.0 - depth) * 1.4 + grad * 0.04, 0.35 + depth));
  // Golpes: una onda recorre la superficie.
  float rr = length(p);
  float ripple = sin(rr * 40.0 - uX.w * 12.0) * exp(-uX.w * 2.0) * uY.x * uP.x;
  nrm = normalize(nrm + vec3(p / (rr + 1e-3) * ripple * 0.4, 0.0));
  vec3 r = reflect(vec3(0.0, 0.0, -1.0), nrm);
  vec3 fire = mix(uC1, uC3, smoothstep(-0.6, 0.8, -r.y)) + uC2 * smoothstep(0.8, 1.0, sin(r.x * 3.0 + clk * 0.5)) * 0.6;
  vec3 studio = uC0 * 0.6 + uC3 * (smoothstep(0.12, 0.0, abs(r.x - 0.35)) + smoothstep(0.08, 0.0, abs(r.y + 0.5))) * 1.1 + uC2 * 0.15 * (0.5 + 0.5 * r.y);
  vec3 horizon = r.y < 0.0 ? mix(uC2, uC3, smoothstep(0.0, -0.8, r.y)) : uC1 * 0.25 * (1.0 - r.y);
  horizon += uC3 * exp(-abs(r.y) * 30.0);
  vec3 metal = fire * uX.x + studio * uX.y + horizon * uX.z;
  metal += uC3 * pow(max(1.0 - nrm.z, 0.0), 3.0) * 0.5;
  // Agudos: destellos sobre el metal.
  float glint = step(0.97, hash12(floor(p * 90.0) + floor(clk * 10.0))) * sq(max(r.z, 0.0));
  metal += uC3 * glint * uD.z * uY.z * 1.5;
  metal *= 1.0 + 0.15 * uA.z;
  col = mix(col, metal, mask);
  }
  col = mix(col, uC2, uD.y * 0.04);
  float cover = mask;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
