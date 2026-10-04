// Puerta Estelar — dos planos de luz psicodélica que pasan a toda velocidad.
// Como la secuencia de la puerta estelar de 2001 (hecha con slit-scan), la
// cámara vuela entre dos planos infinitos, arriba y abajo, cubiertos de
// franjas y formas de colores estiradas por la velocidad, con una línea de
// horizonte brillante en el centro. La energía acelera el vuelo, cada cuatro
// golpes el patrón se transforma y en modo Auto los planos giran a vertical
// (paredes) cada dieciséis golpes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('orientacion', 'Planos', options: ['Auto', 'Suelo y techo', 'Paredes']),
  CreatorModifier.slider('velocidad_luz', 'Velocidad de vuelo', min: .4, max: 2, value: 1),
  CreatorModifier.steps('franjas', 'Franjas', min: 2, max: 12, value: 6),
  CreatorModifier.toggle('horizonte', 'Línea de horizonte', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double travel = 0, sinceSwitch = 0, sinceTurn = 0;
  float boost = 0, patternA = 0, patternB = 0, mix = 1, turn = 0, turnTarget = 0;
  int beats = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void nextPattern() {
    patternA = patternB;
    patternB += 1.0f;
    mix = 0;
    sinceSwitch = 0;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    travel = rng.unit() * 50.0;
    sinceSwitch = sinceTurn = 0;
    boost = 0;
    patternA = patternB = float(int(rng.unit() * 20.0f));
    mix = 1;
    turn = turnTarget = 0;
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
    if (hit > kick + 0.2f) {
      beats++;
      boost = std::max(boost, hit);
      if (beats % 4 == 0) nextPattern();
      if (beats % 16 == 0) {
        turnTarget = 1.0f - turnTarget;
        sinceTurn = 0;
      }
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    boost *= std::exp(-dt * 3.0f);
    sinceSwitch += f.delta;
    sinceTurn += f.delta;
    if (!mu.active && sinceSwitch > 6.0) nextPattern();
    if (!mu.active && sinceTurn > 14.0) {
      turnTarget = 1.0f - turnTarget;
      sinceTurn = 0;
    }
    // Planos: Auto alterna; las otras opciones fijan suelo y techo o paredes.
    float goal = m.orientacion == 1 ? 0.0f : (m.orientacion == 2 ? 1.0f : turnTarget);
    turn += (goal - turn) * (1.0f - std::exp(-dt * 2.0f));
    mix = std::min(1.0f, mix + dt * 1.5f);
    travel += f.delta * f.speed * m.velocidad_luz * (0.8 + 1.8 * drive + 2.5 * boost);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    float e = mix * mix * (3.0f - 2.0f * mix);
    float t = turn * turn * (3.0f - 2.0f * turn);
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(travel, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {patternA, patternB, e, t * 1.5707963f});
    u.insert(u.end(), {f.glow, float(m.franjas), m.horizonte ? 1.0f : 0.0f, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("star_gate", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'star_gate': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // vuelo, graves, golpe, energía
uniform vec4 uB;   // patrón anterior, patrón nuevo, transición, giro de los planos
uniform vec4 uD;   // glow, franjas, horizonte, destello
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

float hash11(float x) {
  x = fract(x * 0.1031);
  x *= x + 33.33;
  x *= x + x;
  return fract(x);
}

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec3 tone(float x) {
  float k = fract(x) * 3.0;
  vec3 a = k < 1.0 ? uC1 : (k < 2.0 ? uC2 : uC3);
  vec3 b = k < 1.0 ? uC2 : (k < 2.0 ? uC3 : uC1);
  return mix(a, b, smoothstep(0.0, 1.0, fract(k)));
}

// Patrón de un plano: bandas de color anchas y suaves, encima muchas rayas
// finas de luz cortadas en tramos que corren hacia la cámara, y rombos de
// luz que pasan de vez en cuando.
vec3 plane(float seed, float x, float depth, float side, float z) {
  float k = uD.y;
  float b1 = x * k * 0.6 + side * 3.1 + seed * 7.3;
  float id1 = floor(b1);
  float f1 = fract(b1);
  float h1 = hash11(id1 * 1.7 + seed * 13.0);
  float body = smoothstep(0.0, 0.2, f1) * smoothstep(1.0, 0.8, f1);
  float flow = 0.5 + 0.5 * sin(depth * (0.35 + 0.7 * h1) + h1 * 40.0);
  vec3 col = tone(h1 + depth * 0.01 + seed * 0.37) * body * (0.05 + 0.22 * flow);
  // Rayas finas: se apagan cerca del horizonte para no hacer muaré.
  float fine = exp(-z * 0.3);
  for (int L = 0; L < 2; L++) {
    float fl = float(L);
    float b2 = x * k * (2.6 + 1.9 * fl) + side * (1.7 + fl) + seed * 3.1 + fl * 0.5;
    float id2 = floor(b2);
    float f2 = fract(b2);
    float h2 = hash11(id2 * 3.3 + seed * 7.0 + fl * 17.0);
    float line = exp(-abs(f2 - 0.5) * (10.0 + 14.0 * h2));
    float seg = smoothstep(0.2, 0.85, 0.5 + 0.5 * sin(depth * (0.8 + 1.6 * h2) + h2 * 60.0));
    col += mix(tone(h2 + 0.33 + seed * 0.21), vec3(1.0), 0.15) * line * seg * step(0.25, h2) * (1.5 - 0.4 * fl) * fine;
  }
  // Rombos de luz pequeños.
  vec2 cell = vec2(id1, floor(depth * 0.3));
  vec2 lc = vec2(f1, fract(depth * 0.3)) - 0.5;
  float gem = step(0.88, hash12(cell + seed)) * exp(-(abs(lc.x) * 6.0 + abs(lc.y) * 9.0)) * fine;
  col += mix(tone(h1 + 0.66), vec3(1.0), 0.5) * gem * 1.4;
  return col;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float cs = cos(uB.w);
  float sn = sin(uB.w);
  p = vec2(cs * p.x + sn * p.y, -sn * p.x + cs * p.y);
  float ay = abs(p.y) + 1e-3;
  float side = p.y > 0.0 ? 1.0 : -1.0;
  // Perspectiva de un plano: lo lejano se junta en el horizonte.
  float z = 0.16 / ay;
  float x = p.x * z;
  float depth = z * 3.0 + uA.x * 4.0;
  vec3 col = plane(uB.y, x, depth, side, z);
  if (uB.z < 0.999) col = mix(plane(uB.x, x, depth, side, z), col, uB.z);
  float near = smoothstep(0.012, 0.08, ay);
  float far = exp(-z * 0.12);
  col *= near * far * (0.85 + 0.5 * uA.y + 0.6 * uA.z) * uD.x;
  // Horizonte brillante en el centro.
  float horizon = uD.z * (0.9 + 0.8 * uA.z);
  col += vec3(1.0) * exp(-ay * 220.0) * horizon;
  col += tone(uB.y * 0.37) * exp(-ay * 30.0) * 0.35 * horizon;
  col += tone(uB.y * 0.37 + 0.5) * uD.w * 0.06;
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.85) {
    float e = (peak - 0.85) / 0.15;
    col *= (0.85 + 0.15 * e / (1.0 + e)) / peak;
  }
  col += uC0 + (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
