// Panal de Energía — un escudo de hexágonos que recibe impactos.
// La pantalla es un escudo de ciencia ficción hecho de celdas hexagonales con
// bordes ámbar, abombado como una cúpula (celdas grandes en el centro y más
// pequeñas hacia los lados). Cada golpe es un impacto en un punto: las
// celdas de alrededor se encienden en rojo con un núcleo blanco y una onda
// de luz recorre el panal celda a celda. Sin música caen impactos suaves de
// vez en cuando; algunas celdas parpadean solas, los graves avivan los
// bordes y una franja de energía barre el escudo en diagonal.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('tamano', 'Tamaño de celdas', min: .5, max: 2, value: 1),
  CreatorModifier.slider('curvatura', 'Curvatura de cúpula', min: 0, max: 1, value: .7),
  CreatorModifier.toggle('chispas', 'Celdas que parpadean', value: true),
  CreatorModifier.toggle('barrido', 'Franja de energía', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kImpacts = 4;
  struct Impact { float x, y, power; double age; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, sinceIdle = 0;
  int nextImpact = 0;
  Random rng{1};
  std::array<Impact, kImpacts> impacts{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void strike(float power, float aspect) {
    Impact& i = impacts[size_t(nextImpact)];
    i.x = (rng.unit() - 0.5f) * 0.8f;
    i.y = (rng.unit() - 0.5f) * 0.8f * aspect;
    i.power = power;
    i.age = 0;
    nextImpact = (nextImpact + 1) % kImpacts;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 20.0;
    sinceIdle = 0;
    nextImpact = 0;
    for (auto& i : impacts) i = {0, 0, 0, 100};
  }

  void update(const Frame& f) override {
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
    float aspect = f.height / std::max(std::min(f.width, f.height), 1.0f);
    sinceIdle += f.delta;
    if (hit > kick + 0.2f) {
      strike(0.6f + 0.5f * hit, aspect);
      sinceIdle = 0;
    }
    if (!mu.active && sinceIdle > 2.6) {
      strike(0.55f, aspect);
      sinceIdle -= 2.6;
    }
    for (auto& i : impacts) i.age += f.delta * f.speed;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (1.0 + 1.0 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(40);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {m.tamano, m.curvatura, m.chispas ? 1.0f : 0.0f, m.barrido ? 1.0f : 0.0f});
    for (const auto& i : impacts) {
      float fade = float(std::max(0.0, 1.0 - i.age / 2.2));
      u.insert(u.end(), {i.x, i.y, float(i.age) * 0.85f, i.power * fade * amp});
    }
    u.insert(u.end(), {f.glow, flash * amp, spark * amp, 0.0f});
    for (int k = 0; k < 4; k++) u.insert(u.end(), {f.colors[k].r, f.colors[k].g, f.colors[k].b});
    c.material("hex_shield", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'hex_shield': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // tamaño, curvatura, parpadeo, barrido
uniform vec4 uI0;  // impacto: x, y, radio de la onda, fuerza
uniform vec4 uI1;
uniform vec4 uI2;
uniform vec4 uI3;
uniform vec4 uD;   // glow, destello, agudos
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

// Cúpula: el centro se agranda y los lados se encogen.
vec2 dome(vec2 p) {
  return p * mix(1.0, 0.72 + 0.45 * dot(p, p), uB.y);
}

// Luz de un impacto en la celda con centro c (en espacio de rejilla).
float impact(vec2 c, vec4 I, float cells) {
  if (I.w <= 0.0) return 0.0;
  vec2 ic = dome(I.xy) * cells;
  float d = length(c - ic) / cells;
  float ring = exp(-abs(d - I.z) * 9.0);
  float core = exp(-d * 9.0) * smoothstep(0.6, 0.0, I.z);
  return (ring + 1.5 * core) * I.w;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float cells = 7.0 / uB.x;
  vec2 uv = dome(p) * cells;
  // Rejilla hexagonal: dos rejillas desplazadas, gana el centro más cercano.
  vec2 r = vec2(1.0, 1.7320508);
  vec2 h = r * 0.5;
  vec2 a = mod(uv, r) - h;
  vec2 b = mod(uv - h, r) - h;
  vec2 gv = dot(a, a) < dot(b, b) ? a : b;
  vec2 id = uv - gv;
  vec2 q = abs(gv);
  float hexD = max(dot(q, normalize(r)), q.x);
  float edge = 0.5 - hexD;
  float px = cells / scale * 1.2;
  float border = 1.0 - smoothstep(0.02, 0.02 + px * 1.5, edge);
  float glowEdge = exp(-edge * 14.0);

  float hit = impact(id, uI0, cells) + impact(id, uI1, cells) + impact(id, uI2, cells) + impact(id, uI3, cells);
  float t = uA.x;
  // Celdas que parpadean solas.
  float sparkle = 0.0;
  if (uB.z > 0.5) {
    float hs = hash12(id + floor(t * 2.5));
    sparkle = step(0.965 - 0.03 * uD.z, hs) * (0.5 + 0.5 * sin(t * 20.0 + hs * 30.0));
  }
  // Franja de energía en diagonal.
  float sweep = 0.0;
  if (uB.w > 0.5) {
    float s = fract((p.x + p.y) * 0.35 - t * 0.12);
    sweep = exp(-abs(s - 0.5) * 18.0);
  }
  float shade = 1.0 - 0.45 * smoothstep(0.2, 1.0, length(p * vec2(1.0, 0.6)));
  vec3 col = uC0 + uC1 * 0.03 * shade;
  // Relleno de la celda: oscuro con un degradado hacia el borde.
  col += uC1 * (0.03 + 0.05 * smoothstep(0.35, 0.0, edge)) * shade;
  float cellLit = clamp(hit, 0.0, 2.0) + sparkle * 0.6;
  vec3 hotFill = mix(uC2, uC3, clamp(hit - 0.8, 0.0, 1.0));
  col += hotFill * cellLit * (0.35 + 0.4 * smoothstep(0.5, 0.0, hexD)) ;
  // Bordes ámbar que se avivan con los graves, el impacto y la franja.
  float edgeLit = (0.45 + 0.4 * uA.y + 0.9 * hit + 0.8 * sweep + 0.5 * sparkle) * shade;
  col += mix(uC1, uC3, clamp(hit * 0.5, 0.0, 1.0)) * border * edgeLit;
  col += uC1 * glowEdge * 0.15 * edgeLit * uD.x;
  col += uC1 * uD.y * 0.05;
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
