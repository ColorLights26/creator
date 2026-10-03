// Cristales Polarizados — cristalización vista al microscopio con luz polarizada.
// Los cristales nacen en puntos repartidos, crecen en abanicos de fibras hasta
// chocar con sus vecinos y cada uno se tiñe con los colores de interferencia
// de su espesor; la cruz oscura de extinción gira con el polarizador. La
// energía de la música acelera el crecimiento, los graves desplazan los
// colores, cada golpe gira el polarizador y en el drop el campo se funde y
// vuelve a cristalizar desde cero.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double growth = 0, angle = 0, shift = 0, sinceCycle = 0;
  float spin = 0, spinVel = 0, melt = 0, seed = 0;
  int cycle = 0;
  bool melting = false;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void startMelt() {
    if (!melting) {
      melting = true;
      melt = 0;
    }
  }

 public:
  void reset(uint32_t s) override {
    Random rng(s);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    growth = 0.25;
    angle = rng.unit() * 3.14159265;
    shift = 0;
    sinceCycle = 0;
    spin = spinVel = 0;
    melt = 0;
    melting = false;
    cycle = 0;
    seed = rng.unit() * 40.0f;
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
      spinVel += 1.6f * hit;
      // Drop: con el campo ya cristalizado, se funde y vuelve a empezar.
      if (hit > 0.7f && drive > 0.4f && growth > 1.25 && sinceCycle > 8.0) startMelt();
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // Giro del polarizador: lento y continuo, con un empujón amortiguado en cada golpe.
    spinVel *= std::exp(-dt * 2.5f);
    angle += f.delta * (0.08 + 0.12 * drive) * f.speed + double(spinVel) * f.delta;
    shift += f.delta * (0.02 + 0.05 * energy);
    growth += f.delta * f.speed * (0.07 + 0.16 * drive);
    sinceCycle += f.delta;
    // Al completarse el campo, se funde solo tras unos segundos de contemplación.
    if (growth > 1.6) startMelt();
    if (melting) {
      melt = std::min(1.0f, melt + dt * 1.5f);
      if (melt >= 1.0f) {
        melting = false;
        melt = 0;
        growth = 0.12;
        cycle++;
        seed = std::fmod(seed + 17.31f, 97.0f);
        sinceCycle = 0;
      }
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float fade = melting ? 1.0f - melt * melt : 1.0f;
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(growth), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(std::fmod(angle, 6.2831853)), float(std::fmod(shift, 100.0)) + 0.25f * bass * amp, seed, fade});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, std::clamp(f.detail, 0.25f, 2.0f)});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("polarized", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'polarized': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // crecimiento, graves, golpe, energía
uniform vec4 uB;   // ángulo del polarizador, desplazamiento de color, semilla, fundido
uniform vec4 uD;   // glow, agudos, destello, detalle
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

vec2 hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
             mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = frag / scale;
  float cells = 3.2 + 1.2 * uD.w;
  vec2 g = p * cells;
  vec2 gi = floor(g);
  vec2 gf = fract(g);
  float seed = uB.z;

  // Teselado de crecimiento: cada cristal nace en su momento y crece a la
  // misma velocidad; el píxel pertenece al que llegó primero.
  float best = 1e9;
  float second = 1e9;
  vec2 rel = vec2(0.0);
  float id = 0.0;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 cell = gi + vec2(float(i), float(j));
      vec2 hc = hash22(cell + seed);
      vec2 nucleus = vec2(float(i), float(j)) + 0.15 + 0.7 * hc;
      vec2 d = gf - nucleus;
      float birth = fract(hc.x * 7.31 + hc.y * 3.17) * 0.55;
      float arrival = birth + length(d) * 0.5;
      if (arrival < best) {
        second = best;
        best = arrival;
        rel = d;
        id = fract(hc.x * 13.7 + hc.y * 5.31);
      } else if (arrival < second) {
        second = arrival;
      }
    }
  }
  float grown = uA.x - best;
  vec3 col = uC0;
  // Líquido sin cristalizar: oscuro con un reflejo frío muy tenue.
  col += uC2 * 0.015 * noise(p * 6.0 + uA.x);
  if (grown > 0.0) {
    float r = length(rel);
    vec2 dir = rel / max(r, 1e-4);
    float theta = atan(rel.y, rel.x);
    // Fibras radiales: ruido según la dirección (sin costura) y anillos.
    float fib = noise(dir * 14.0 + id * 31.0);
    float rings = sin(r * 26.0 + id * 40.0) * 0.5 + 0.5;
    // Espesor -> colores de interferencia de Michel-Lévy (luz blanca).
    float thick = 0.35 + 1.1 * id + 0.35 * fib + 0.12 * rings + 0.25 * r + uB.y;
    vec3 lam = vec3(0.65, 0.55, 0.45);
    vec3 interf = sin(3.14159265 * thick / lam);
    interf *= interf;
    // Cruz de extinción: oscuro donde las fibras se alinean con el polarizador.
    float ext = sin(2.0 * (theta - uB.x));
    ext *= ext;
    float I = ext * (0.6 + 0.5 * fib) * (0.85 + 0.35 * uA.y + 0.4 * uA.z);
    col = interf * I * 1.15 * uD.x;
    // Frente de crecimiento brillante y bordes de grano oscuros.
    col += mix(uC1, vec3(1.0), 0.5) * exp(-grown * 40.0) * 0.5;
    col *= smoothstep(0.0, 0.025, second - best);
    // Destellos en las fibras con los agudos.
    float tw = step(0.993 - 0.01 * uD.y, hash12(floor(frag * 0.5) + floor(uA.x * 20.0)));
    col += vec3(1.0) * tw * I * uD.y * 0.8;
  }
  col *= uB.w;
  col += mix(uC1, uC3, 0.5) * uD.z * 0.05;
  col *= 1.0 - 0.35 * smoothstep(0.6, 1.4, length((frag - 0.5 * uSize) / scale * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
