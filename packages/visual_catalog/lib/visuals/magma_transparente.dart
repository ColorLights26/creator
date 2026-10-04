// Magma Transparente — corteza volcánica agrietada sobre un río de lava.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// La pantalla es una corteza de roca negra partida en placas que se mueven
// muy despacio; por las grietas asoma la lava naranja y amarilla que fluye
// debajo, y el calor tiñe de rojo los bordes de las placas. Los graves
// ensanchan y encienden las grietas, cada golpe hace saltar brasas y abre un
// destello de calor, y la energía acelera el flujo de la lava.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('calor', 'Calor', min: .4, max: 2, value: 1),
  CreatorModifier.steps('placas', 'Tamaño de placas', min: 3, max: 10, value: 5),
  CreatorModifier.slider('flujo', 'Flujo de lava', min: .2, max: 2, value: 1),
  CreatorModifier.toggle('brasas', 'Brasas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double flow = 0, drift = 0, rise = 0;
  float heat = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    flow = rng.unit() * 50.0;
    drift = rng.unit() * 50.0;
    rise = 0;
    heat = 0;
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
    if (hit > kick + 0.2f) heat = std::max(heat, hit);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    heat *= std::exp(-dt * 2.0f);
    flow += f.delta * f.speed * m.flujo * (0.15 + 0.5 * drive);
    drift += f.delta * f.speed * (0.02 + 0.05 * drive);
    rise += f.delta * f.speed * (0.25 + 0.6 * drive + 0.8 * heat);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(flow, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {m.calor, float(m.placas), m.brasas ? 1.0f : 0.0f, flash * amp});
    u.insert(u.end(), {float(std::fmod(drift, 1000.0)), f.glow, heat * amp, float(std::fmod(rise, 1000.0))});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("magma_crust", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'magma_crust': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // flujo de lava, graves, golpe, energía
uniform vec4 uB;   // calor, tamaño de placas, brasas, destello
uniform vec4 uD;   // deriva de las placas, glow, fogonazo de calor, subida de brasas
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
  // Placas de corteza: celdas de Voronoi que se desplazan muy despacio.
  vec2 gi = floor(g);
  vec2 gf = fract(g);
  float d1 = 8.0;
  float d2 = 8.0;
  vec2 nearest = vec2(0.0);
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 cell = gi + vec2(float(i), float(j));
      vec2 h = hash22(cell);
      vec2 o = vec2(float(i), float(j)) + 0.5 + 0.38 * sin(uD.x * (0.6 + h) + h * 6.2831);
      float d = length(gf - o);
      if (d < d1) {
        d2 = d1;
        d1 = d;
        nearest = cell;
      } else if (d < d2) {
        d2 = d;
      }
    }
  }
  float edge = d2 - d1;
  // Grieta: más ancha y brillante con los graves y el calor.
  float width = (0.035 + 0.05 * uA.y + 0.06 * uD.z) * uB.x;
  float crack = smoothstep(width, width * 0.3, edge);
  // En el overlay el calor queda pegado a las grietas: la roca es transparente.
  float heatGlow = exp(-edge / (width * 1.4));

  // Roca de la corteza: textura oscura con brillo rojizo junto a las grietas.
  float rock = noise(g * 3.0 + nearest * 7.0) * 0.7 + hash12(floor(frag * 0.5)) * 0.3;
  vec3 crust = uC0 + vec3(0.06, 0.04, 0.035) * rock;
  crust += uC1 * heatGlow * (0.25 + 0.5 * uA.y + 0.6 * uD.z) * uB.x;
  vec3 col = crust;
  // Lava que fluye bajo la corteza: sólo se calcula dentro de las grietas.
  if (crack > 0.002) {
    vec2 lp = p * 3.0 + vec2(uA.x * 0.4, -uA.x * 0.25);
    float w = noise(lp * 0.7 + uA.x * 0.1);
    float lava = noise(lp + vec2(w * 2.0, 0.0)) * 0.6 + noise(lp * 2.3 - w) * 0.4;
    vec3 lavaCol = mix(uC1, uC2, smoothstep(0.3, 0.7, lava));
    lavaCol = mix(lavaCol, uC3, smoothstep(0.65, 0.95, lava) * (0.6 + 0.6 * uA.y));
    col = mix(crust, lavaCol * (1.1 + 0.6 * uA.z), crack);
  }

  // Brasas que suben con el calor.
  if (uB.z > 0.5) {
    vec2 eg = vec2(p.x * 22.0, p.y * 22.0 + uD.w * 6.0);
    vec2 ec = floor(eg);
    vec2 el = fract(eg) - 0.5;
    float h = hash12(ec + 3.7);
    vec2 off = vec2(hash12(ec + 1.1), hash12(ec + 9.4)) - 0.5;
    float ember = step(0.94 - 0.05 * uA.z - 0.04 * uD.z, h) * exp(-dot(el - off * 0.6, el - off * 0.6) * 140.0);
    float flicker = 0.6 + 0.4 * sin(uD.w * 9.0 + h * 40.0);
    col += mix(uC2, uC3, h) * ember * flicker * (1.2 + uA.z);
  }
  col *= uD.y * 0.4 + 0.6;
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length((frag - 0.5 * uSize) / scale * vec2(0.9, 0.65)));
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
