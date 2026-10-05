// Células de Voronoi — un tejido vivo que se divide con la música.
// Cada punto del plano pertenece a la semilla más cercana: así nacen las
// celdas de Voronoi, la misma forma que tienen las células de un tejido, un
// panal o la espuma. Aquí las semillas se mueven, algunas células se parten
// en dos y se vuelven a juntar como en una mitosis, las membranas brillan y
// cada célula tiene su núcleo. Con música, cada golpe parte media pantalla
// a la vez, los graves engordan las membranas y los agudos mandan impulsos
// eléctricos que corren por ellas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: tejido orgánico, panal regular o burbujas separadas.
  CreatorModifier.choice(
    'celulas',
    'Células',
    options: ['Tejido', 'Panal', 'Burbujas'],
  ),
  // MOVIMIENTO: de un tejido tranquilo a uno que no para de dividirse.
  CreatorModifier.slider('vida', 'Actividad', min: 0, max: 1, value: .5),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Chispas'],
  ),
  // ATMÓSFERA: visto a través del ocular de un microscopio.
  CreatorModifier.slider('microscopio', 'Microscopio', min: 0, max: 1, value: .3),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Mitosis', {
    'celulas': 'Burbujas',
    'vida': 1,
    'pulso': 'Golpes',
    'microscopio': .8,
  }),
  CreatorVariation('Panal Vivo', {
    'celulas': 'Panal',
    'microscopio': 0,
    'pulso': 'Graves',
    'vida': .2,
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, split = 0, drive = 0;
  // Reloj en doble precisión: sin música es idéntico a 30 y 60 FPS.
  double clock = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = spark = energy = slowBass = kick = flash = split = drive = 0;
    clock = double(rng.unit()) * 50.0;
  }

  void update(const Frame& f) override {
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    // Cada golpe parte las células; luego se van juntando otra vez.
    if (hit > kick + 0.2f) split = std::max(split, hit);
    split *= std::exp(-dt * 2.5f);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (1.0 + 0.5 * double(drive));
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    std::vector<float> u;
    u.reserve(32);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), std::min(bass * amp, 1.5f) * g.pulso.weight(1),
                       std::min(split * amp, 1.0f) * g.pulso.weight(0), std::min(spark * amp, 1.0f) * g.pulso.weight(2)});
    // Detalle: cuántas células caben a lo ancho.
    u.insert(u.end(), {3.2f + 2.2f * f.detail, std::clamp(g.vida, 0.0f, 1.0f), std::clamp(g.microscopio, 0.0f, 1.0f), f.glow});
    u.insert(u.end(), {g.celulas.weight(0), g.celulas.weight(1), g.celulas.weight(2), std::min(flash * amp, 1.0f)});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[size_t(i)].r, f.colors[size_t(i)].g, f.colors[size_t(i)].b});
    c.material("voronoi_cells", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'voronoi_cells': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, graves, división por golpe, chispas
uniform vec4 uB;   // células a lo ancho, actividad, microscopio, glow
uniform vec4 uW;   // pesos: tejido, panal, burbujas; destello
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

float sq(float x) {
  return x * x;
}

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
  vec2 q = (frag - 0.5 * uSize) / scale;
  vec2 p = q * uB.x;
  float t = uA.x;
  float vida = uB.y;
  float jitter = uW.x * 0.8 + uW.y * 0.25 + uW.z * 0.7;
  vec2 g = floor(p);
  float F1 = 9.0;
  float F2 = 9.0;
  vec2 seed = vec2(0.0);
  // De qué célula vienen las dos semillas más cercanas y cuánto se partió.
  vec2 id1 = vec2(-99.0);
  vec2 id2 = vec2(-98.0);
  float split1 = 0.0;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 cell = g + vec2(float(i), float(j));
      vec2 h = hash22(cell);
      // Segundo azar derivado del primero: sin otro hash.
      vec2 h2 = fract(h * vec2(7.13, 5.71) + vec2(0.31, 0.77));
      vec2 move = 0.12 * (0.3 + vida) * sin(vec2(t * (0.5 + h.x) + h.y * 6.28, t * (0.4 + h.y) + h.x * 6.28 + 1.5707963));
      vec2 c = cell + 0.5 + (h - 0.5) * jitter + move * (1.0 - 0.7 * uW.y);
      // División: unas células se parten y se vuelven a juntar; los golpes parten muchas.
      float cyc = 0.5 + 0.5 * sin(t * 0.35 * (0.6 + h2.x) * (0.5 + vida) + h2.y * 20.0);
      float sp = clamp(smoothstep(0.55, 0.95, cyc) * (0.3 + 0.7 * vida) + uA.z * step(0.4, h2.x), 0.0, 1.0);
      // Dirección de la división sin trigonometría.
      vec2 dir = normalize(h2 - 0.5 + vec2(0.001, 0.0)) * 0.2 * sp;
      vec2 a = c + dir;
      float da = length(p - a);
      if (da < F1) { F2 = F1; id2 = id1; F1 = da; id1 = cell; split1 = sp; seed = a; } else if (da < F2) { F2 = da; id2 = cell; }
      if (sp > 0.02) {
        vec2 b = c - dir;
        float db = length(p - b);
        if (db < F1) { F2 = F1; id2 = id1; F1 = db; id1 = cell; split1 = sp; seed = b; } else if (db < F2) { F2 = db; id2 = cell; }
      }
    }
  }
  float edge = F2 - F1;
  // Entre dos mitades de una célula que aún se está partiendo, la membrana
  // nace poco a poco en vez de llenar la célula.
  float sibling = (id1.x == id2.x && id1.y == id2.y) ? 1.0 - smoothstep(0.2, 0.7, split1) : 0.0;
  edge = mix(edge, 1.0, sibling);
  float aa = uB.x * 1.5 / scale;
  // Membranas: más gruesas con los graves y más nítidas en el panal.
  float mw = (0.06 + 0.05 * uA.y) * mix(1.0, 0.6, uW.y);
  float memTissue = 1.0 - smoothstep(0.0, mw, edge);
  // Burbujas: células redondas con huecos entre ellas.
  float R0 = 0.42 + 0.06 * uA.y;
  float bubble = smoothstep(R0 + aa, R0 - aa, F1) * smoothstep(0.02, 0.06, edge);
  float mask = mix(1.0, bubble, uW.z);
  float memBubble = max(memTissue * bubble, exp(-sq((F1 - R0) / 0.03)) * smoothstep(0.0, 0.04, edge));
  float membrane = mix(memTissue, memBubble, uW.z);
  // Citoplasma con gránulos, núcleo y nucléolo.
  float shade = clamp(1.0 - F1 / 0.55, 0.0, 1.0);
  vec3 cyto = mix(uC1, uC2, shade) * (0.85 + 0.3 * noise(p * 8.0 + seed * 3.0));
  float nucleus = smoothstep(0.13 + aa, 0.13 - aa, F1);
  float nucleolus = smoothstep(0.05 + aa, 0.05 - aa, F1);
  cyto = mix(cyto, mix(uC2, uC3, 0.6), nucleus);
  cyto = mix(cyto, uC1 * 0.5, nucleolus);
  vec3 col = mix(uC0, cyto, mask);
  col += uC2 * exp(-edge / 0.08) * 0.22 * uB.w * mask;
  col = mix(col, uC3, membrane * 0.9);
  // Chispas: impulsos eléctricos que corren por las membranas.
  float travel = fract(dot(p, vec2(0.7, 0.7)) * 0.5 - t * 1.5);
  col += uC3 * membrane * smoothstep(0.85, 1.0, travel) * uA.w * 1.2;
  col *= 1.0 + 0.15 * uW.w;
  // Microscopio: el campo circular del ocular, con grano.
  float r = length(q);
  float field = smoothstep(0.49, 0.46, r);
  vec3 scope = col * field + uC2 * 0.08 * exp(-abs(r - 0.475) * 60.0);
  scope += (hash12(frag + t) - 0.5) * 0.06;
  col = mix(col, scope, uB.z);
  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, length(q * vec2(0.9, 0.65)));
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.9) col *= (0.9 + 0.1 * (peak - 0.9) / (peak - 0.8)) / peak;
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
