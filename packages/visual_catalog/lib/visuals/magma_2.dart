// Magma 2 — corteza volcánica viva con grietas que se mueven.
// Como Magma, la pantalla es roca negra partida en placas con lava debajo,
// pero aquí todo se mueve: la corteza se deforma y se desplaza, así que las
// grietas se retuercen, se estiran y cambian de forma sin parar. Por cada
// grieta corren pulsos de roca fundida en su propio sentido, cada placa se
// calienta y se enfría a su ritmo y en los cruces de grietas burbujea la
// lava. Los graves ensanchan las grietas, la energía acelera el movimiento,
// cada golpe lanza desde un punto una onda de calor que abre y enciende las
// grietas a su paso y hace saltar brasas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('calor', 'Calor', min: .4, max: 2, value: 1),
  CreatorModifier.steps('placas', 'Tamaño de placas', min: 3, max: 10, value: 5),
  CreatorModifier.slider('flujo', 'Flujo de lava', min: .2, max: 2.5, value: 1),
  CreatorModifier.slider('movimiento', 'Movimiento de grietas', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('ondas', 'Ondas de calor', value: true),
  CreatorModifier.toggle('brasas', 'Brasas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double flow = 0, drift = 0, rise = 0, pulse = 0, warp = 0, waveAge = 100;
  float heat = 0, waveX = 0.5f, waveY = 0.5f, wavePower = 0;
  Random rng{1};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    flow = rng.unit() * 50.0;
    drift = rng.unit() * 50.0;
    rise = 0;
    pulse = rng.unit() * 10.0;
    warp = rng.unit() * 20.0;
    waveAge = 100;
    heat = 0;
    waveX = waveY = 0.5f;
    wavePower = 0;
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
    waveAge += f.delta;
    if (hit > kick + 0.2f) {
      heat = std::max(heat, hit);
      // Onda de calor nueva desde un punto distinto de la pantalla.
      if (waveAge > 0.25) {
        waveAge = 0;
        waveX = 0.15f + 0.7f * rng.unit();
        waveY = 0.15f + 0.7f * rng.unit();
        wavePower = hit;
      }
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    heat *= std::exp(-dt * 2.0f);
    flow += f.delta * f.speed * m.flujo * (0.3 + 0.8 * drive + 0.6 * heat);
    drift += f.delta * f.speed * m.movimiento * (0.06 + 0.12 * drive);
    rise += f.delta * f.speed * (0.35 + 0.8 * drive + 0.9 * heat);
    pulse += f.delta * f.speed * m.flujo * (0.6 + 1.4 * drive + 2.0 * heat);
    warp += f.delta * f.speed * m.movimiento * (0.25 + 0.5 * drive + 0.4 * heat);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    float side = std::min(f.width, f.height);
    float wave = m.ondas && waveAge < 1.8 ? wavePower * float(1.0 - waveAge / 1.8) * amp : 0.0f;
    std::vector<float> u;
    u.reserve(32);
    u.insert(u.end(), {float(std::fmod(flow, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {m.calor, float(m.placas), m.brasas ? 1.0f : 0.0f, flash * amp});
    u.insert(u.end(), {float(std::fmod(drift, 1000.0)), f.glow, heat * amp, float(std::fmod(rise, 1000.0))});
    // Centro de la onda en las mismas unidades que el shader (píxel / lado corto).
    u.insert(u.end(), {waveX * f.width / side, waveY * f.height / side, float(waveAge) * 1.1f, wave});
    u.insert(u.end(), {float(std::fmod(pulse, 1000.0)), float(std::fmod(warp, 1000.0)), m.movimiento, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("magma_alive", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'magma_alive': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // flujo de lava, graves, golpe, energía
uniform vec4 uB;   // calor, tamaño de placas, brasas, destello
uniform vec4 uD;   // deriva de las placas, glow, fogonazo de calor, subida de brasas
uniform vec4 uE;   // onda de calor: centro x, centro y, radio, fuerza
uniform vec4 uF;   // pulsos por las grietas, deformación, movimiento
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
  vec2 g = p * (12.0 / uB.y);
  // La corteza se deforma y se desplaza: las grietas se retuercen sin parar.
  float t = uF.y;
  float mv = uF.z;
  g += mv * vec2(0.42 * sin(g.y * 0.7 + t * 1.3) + 0.2 * sin(g.y * 1.9 - t * 2.1),
                 0.42 * sin(g.x * 0.8 - t * 1.1) + 0.2 * sin(g.x * 2.3 + t * 1.7));
  g += vec2(uD.x * 0.6, -uD.x * 0.35);
  vec2 gi = floor(g);
  vec2 gf = fract(g);
  float d1 = 8.0;
  float d2 = 8.0;
  vec2 o1 = vec2(0.0);
  vec2 o2 = vec2(0.0);
  vec2 c1 = vec2(0.0);
  vec2 c2 = vec2(0.0);
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 cell = gi + vec2(float(i), float(j));
      vec2 h = hash22(cell);
      vec2 o = vec2(float(i), float(j)) + 0.5 + 0.4 * sin(uA.x * (0.5 + h) + h * 6.2831);
      float d = length(gf - o);
      if (d < d1) {
        d2 = d1;
        o2 = o1;
        c2 = c1;
        d1 = d;
        o1 = o;
        c1 = cell;
      } else if (d < d2) {
        d2 = d;
        o2 = o;
        c2 = cell;
      }
    }
  }
  float edge = d2 - d1;
  // Dirección de la grieta, siempre orientada igual a ambos lados.
  vec2 nrm = normalize(o2 - o1 + 1e-5);
  vec2 tang = vec2(-nrm.y, nrm.x);
  if (tang.x < 0.0 || (tang.x == 0.0 && tang.y < 0.0)) tang = -tang;
  float pairId = hash12(c1 + c2 + 0.37);
  float along = dot(gi + gf, tang);
  // Pulsos de roca fundida que corren por cada grieta en su sentido.
  float dir = pairId > 0.5 ? 1.0 : -1.0;
  float run = 0.5 + 0.5 * sin(along * 3.2 - uF.x * 3.0 * dir + pairId * 40.0);
  float pulseLava = run * run * run;

  // Onda de calor del golpe.
  float ring = 0.0;
  if (uE.w > 0.0) {
    float rd = length(p - uE.xy) - uE.z;
    ring = exp(-abs(rd) * 9.0) * uE.w * smoothstep(0.0, 0.15, uE.z + 0.15);
  }

  // Grieta: más ancha y brillante con los graves, el calor, los pulsos y la onda.
  // El resplandor usa el ancho base: los pulsos cambian de una grieta a otra
  // y en la roca dejarían costuras.
  float widthBase = (0.035 + 0.05 * uA.y + 0.06 * uD.z) * uB.x * (1.0 + 1.6 * ring);
  float width = widthBase * (0.75 + 0.55 * pulseLava);
  float crack = smoothstep(width, width * 0.3, edge);
  float heatGlow = exp(-edge / (widthBase * 3.5));

  // Roca: textura oscura; cada placa se calienta y se enfría a su ritmo.
  float rock = noise(g * 3.0 + c1 * 7.0) * 0.7 + hash12(floor(frag * 0.5)) * 0.3;
  vec3 crust = uC0 + vec3(0.06, 0.04, 0.035) * rock;
  float plateId = hash12(c1);
  float plateHeat = (0.5 + 0.5 * sin(t * 1.7 + plateId * 30.0)) * 0.1 * (0.4 + uA.w);
  crust += uC1 * plateHeat * smoothstep(0.7, 0.1, d1);
  crust += uC1 * heatGlow * (0.3 + 0.5 * uA.y + 0.6 * uD.z + 0.6 * ring) * uB.x;
  crust += uC2 * ring * 0.12;
  vec3 col = crust;
  // Lava que fluye bajo la corteza: sólo se calcula dentro de las grietas.
  if (crack > 0.002) {
    vec2 lp = p * 3.0 + vec2(uA.x * 0.5, -uA.x * 0.3);
    float w = noise(lp * 0.7 + uA.x * 0.15);
    float lava = noise(lp + vec2(w * 2.0, 0.0)) * 0.6 + noise(lp * 2.3 - w) * 0.4;
    lava = clamp(lava + 0.35 * pulseLava + 0.4 * ring, 0.0, 1.0);
    vec3 lavaCol = mix(uC1, uC2, smoothstep(0.3, 0.7, lava));
    lavaCol = mix(lavaCol, uC3, smoothstep(0.65, 0.95, lava) * (0.6 + 0.6 * uA.y));
    col = mix(crust, lavaCol * (1.1 + 0.6 * uA.z + 0.5 * ring), crack);
  }
  // Burbujas de lava en los cruces de grietas.
  float junction = smoothstep(0.12, 0.0, edge) * smoothstep(0.65, 0.35, d1);
  col += uC3 * junction * (0.2 + 0.5 * pulseLava) * (0.5 + 0.8 * uA.y);

  // Brasas que suben meciéndose con el calor.
  if (uB.z > 0.5) {
    vec2 eg = vec2(p.x * 24.0 + sin(p.y * 6.0 + uD.w * 1.3) * 0.6, p.y * 24.0 + uD.w * 7.0);
    vec2 ec = floor(eg);
    vec2 el = fract(eg) - 0.5;
    float h = hash12(ec + 3.7);
    vec2 off = vec2(hash12(ec + 1.1), hash12(ec + 9.4)) - 0.5;
    float ember = step(0.92 - 0.06 * uA.z - 0.05 * uD.z - 0.03 * ring, h) * exp(-dot(el - off * 0.6, el - off * 0.6) * 140.0);
    float flicker = 0.6 + 0.4 * sin(uD.w * 9.0 + h * 40.0);
    col += mix(uC2, uC3, h) * ember * flicker * (1.2 + uA.z);
  }
  col += uC2 * uB.w * 0.06;
  col *= (uD.y * 0.4 + 0.6) * (1.0 + 0.2 * uA.y);
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length((frag - 0.5 * uSize) / scale * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.85) {
    float e = (peak - 0.85) / 0.15;
    col *= (0.85 + 0.15 * e / (1.0 + e)) / peak;
  }
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
