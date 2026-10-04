// Estrella de Neón Transparente — caleidoscopio de seis puntas con láseres y mármol.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Estrellas de seis puntas de neón dorado nacen en el centro y crecen hacia
// fuera una tras otra; seis láseres azules salen de las puntas y cruzan la
// pantalla. Entre las puntas, un mármol líquido rojo y naranja plegado en
// espejo se enciende con la música: casi apagado en calma, ardiendo en el
// drop. Cada golpe acelera las estrellas y enciende los láseres, los graves
// avivan el mármol y los agudos lo hacen girar.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double travel = 0, clock = 0, swirl = 0;
  float boost = 0, laser = 0, fire = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    travel = rng.unit() * 10.0;
    clock = rng.unit() * 50.0;
    swirl = rng.unit() * 6.2831853;
    boost = laser = fire = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) {
      boost = std::max(boost, hit);
      laser = std::max(laser, hit);
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    boost *= std::exp(-dt * 3.0f);
    laser *= std::exp(-dt * 2.0f);
    // El mármol arde con la energía sostenida de la canción.
    fire = follow(fire, 0.15f + 0.85f * drive + 0.3f * bass, 2.0f, 0.6f, dt);
    travel += f.delta * f.speed * (0.3 + 0.5 * drive + 1.3 * boost);
    clock += f.delta * f.speed;
    swirl += f.delta * f.speed * (0.06 + 0.3 * spark + 0.1 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(std::fmod(travel, 1000.0)), f.glow, spark * amp, flash * amp});
    u.insert(u.end(), {std::min(1.2f, fire * amp), (0.3f + laser) * amp, float(std::fmod(swirl, 6.2831853)), 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("neon_star", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'neon_star': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // avance de las estrellas, glow, agudos, destello
uniform vec4 uF;   // fuego del mármol, fuerza de los láseres, giro del mármol
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float PI = 3.14159265;

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

// Distancia con signo a una estrella de seis puntas de radio r (iq).
float sdStar6(vec2 p, float r) {
  const float an = PI / 6.0;
  const float en = PI / 3.0;
  vec2 acs = vec2(cos(an), sin(an));
  vec2 ecs = vec2(cos(en), sin(en));
  float bn = mod(atan(p.x, p.y), 2.0 * an) - an;
  p = length(p) * vec2(cos(bn), abs(sin(bn)));
  p -= r * acs;
  p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
  return length(p) * sign(p.x);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float r = length(p) + 1e-4;
  float a = atan(p.x, p.y);
  float t = uA.x;
  float kick = uA.z;

  // Pliegue en espejo de seis sectores para el mármol y los láseres.
  float sector = PI / 3.0;
  float fa = abs(mod(a, sector) - 0.5 * sector);
  vec2 k = vec2(cos(fa), sin(fa)) * r;

  // Mármol líquido rojo y naranja con remolinos.
  vec2 m = k * 3.0;
  float cs = cos(uF.z);
  float sn = sin(uF.z);
  m = vec2(cs * m.x - sn * m.y, sn * m.x + cs * m.y);
  float w1 = noise(m * 1.3 + vec2(t * 0.08, 0.0));
  float w2 = noise(m * 1.3 + vec2(5.2, -t * 0.07));
  vec2 mm = m + 2.2 * vec2(w1, w2);
  float veins = sin(mm.x * 5.0 + noise(mm * 1.7) * 6.0 + t * 0.4);
  float marble = smoothstep(-0.2, 1.0, veins);
  vec3 marbleCol = mix(uC3 * 0.55, mix(uC3, uC2, 0.6), marble) + vec3(1.0, 0.9, 0.5) * pow(marble, 8.0) * 0.6;
  // Oscuro cerca de las puntas (donde van los láseres) y fundido en el centro.
  float wedge = smoothstep(0.0, 0.25, fa);
  // En el overlay sólo quedan las vetas brillantes del mármol.
  vec3 col = uC0 + mix(uC1 * 0.12 * marble, marbleCol, clamp(uF.x, 0.0, 1.0)) * wedge * smoothstep(0.05, 0.3, r) *
             (0.55 + 0.6 * uA.y) * smoothstep(0.55, 0.95, marble);

  // Estrellas de neón dorado que salen del centro.
  for (int i = 0; i < 5; i++) {
    float ph = fract(uB.x * 0.32 + float(i) * 0.2);
    float s = 0.04 * exp(ph * 3.6);
    float sd = sdStar6(p, s);
    float d = abs(sd);
    float w = 0.003 + 0.012 * s;
    float fade = smoothstep(0.0, 0.1, ph) * smoothstep(1.0, 0.75, ph);
    vec3 gold = mix(uC2, vec3(1.0, 0.95, 0.75), exp(-d / (w * 0.3)));
    col += gold * (exp(-d / (w * 0.5)) + 0.45 * exp(-d / (w * 2.5))) * fade * uB.y;
    // Contorno interior azul, como en el doble trazo del neón.
    float d2 = abs(sd + 0.045 * s);
    col += uC1 * exp(-d2 / (w * 0.35)) * fade * 0.6;
  }

  // Láseres azules desde las puntas de la estrella.
  float beamD = sin(fa) * r;
  float width = 0.004 + 0.045 * r;
  float beam = (exp(-beamD / width) * 0.7 + exp(-beamD / (width * 0.3))) * smoothstep(0.05, 0.25, r);
  col += mix(uC1, vec3(0.65, 0.97, 1.0), exp(-beamD / (width * 0.35))) * beam * uF.y * 1.2;

  // Brillo central y destello.
  col += mix(uC2, vec3(1.0), 0.5) * (0.0015 + 0.004 * kick) / (r * r + 0.002);
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.85) {
    float e = (peak - 0.85) / 0.15;
    col *= (0.85 + 0.15 * e / (1.0 + e)) / peak;
  }
  // Fondo transparente: color premultiplicado y opacidad según el brillo; la
  // luz muy tenue se vuelve transparente del todo para no dejar velo.
  col = clamp(col, 0.0, 1.0);
  float veilPeak = max(col.r, max(col.g, col.b));
  float clearCut = smoothstep(0.04, 0.12, veilPeak);
  col *= clearCut;
  float alpha = clamp(veilPeak * 1.25, 0.0, 1.0) * clearCut;
  fragColor = vec4(col, alpha);
}
""",
};
