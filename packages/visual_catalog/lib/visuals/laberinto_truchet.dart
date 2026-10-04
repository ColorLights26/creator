// Laberinto Truchet — caminos de neón hechos de losetas que giran.
// Cada loseta lleva dos cuartos de círculo que unen los centros de sus
// lados; según su giro, los arcos de todas las losetas se enlazan en caminos
// y lazos sin fin. Las losetas giran 90° cada cierto tiempo, cada una a su
// ritmo, con una animación suave, y los caminos se reconectan. Cada golpe
// lanza desde el centro una ola que gira todas las losetas a su paso. Por
// los caminos corre luz en ondas, el color pasa del lima al rojo por zonas y
// los graves engordan el neón.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('losetas', 'Losetas a lo ancho', min: 4, max: 16, value: 8),
  CreatorModifier.slider('grosor', 'Grosor del neón', min: .5, max: 2, value: 1),
  CreatorModifier.slider('giros', 'Giros sin música', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('ola', 'Ola con los golpes', value: true),
  CreatorModifier.toggle('luz', 'Luz que corre', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, flips = 0, waveAge = 100;
  int waves = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 30.0;
    flips = rng.unit() * 10.0;
    waveAge = 100;
    waves = 0;
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
    // Una ola nueva sólo cuando la anterior ya cruzó la pantalla.
    if (hit > kick + 0.2f && m.ola && waveAge > 1.2) {
      waves++;
      waveAge = 0;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (0.8 + 1.4 * drive);
    flips += f.delta * f.speed * m.giros * 0.18;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(m.losetas), m.grosor, float(std::fmod(flips, 512.0)), m.luz ? 1.0f : 0.0f});
    u.insert(u.end(), {float(waves % 64), float(std::min(waveAge, 10.0)) * 1.6f, f.glow, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("truchet", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'truchet': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // losetas, grosor, giros acumulados, luz
uniform vec4 uW;   // olas, radio de la última ola, glow, destello
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

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float n = uB.x;
  vec2 g = p * n;
  vec2 id = floor(g);
  vec2 f = fract(g) - 0.5;
  // Giros propios: cada loseta gira un cuarto de vuelta cuando su reloj cruza
  // un entero; el giro se anima durante el primer cuarto del intervalo.
  float h = hash12(id);
  float own = uB.z * (0.6 + 0.8 * h) + h * 7.0;
  float ownTurns = floor(own) - 1.0 + smoothstep(0.0, 0.25, fract(own));
  // Olas de los golpes: la última todavía puede no haber llegado.
  vec2 center = (id + 0.5) / n;
  float d = length(center);
  float arrived = uW.y - d;
  float waveTurns = uW.x - 1.0 + (arrived < 0.0 ? 0.0 : smoothstep(0.0, 0.18, arrived));
  float angle = 1.5707963 * (floor(h * 2.0) + ownTurns + waveTurns);
  float cs = cos(angle);
  float sn = sin(angle);
  vec2 r = vec2(cs * f.x - sn * f.y, sn * f.x + cs * f.y);
  // Dos arcos con centro en esquinas opuestas.
  float d1 = abs(length(r - vec2(0.5, 0.5)) - 0.5);
  float d2 = abs(length(r + vec2(0.5, 0.5)) - 0.5);
  float dist = min(d1, d2);
  float px = n / scale;
  float w = 0.07 * uB.y * (1.0 + 0.35 * uA.y);
  float core = 1.0 - smoothstep(w * 0.45 - px, w * 0.45 + px, dist);
  float tubeEdge = 1.0 - smoothstep(w - px, w + px, dist);
  float glow = exp(-dist / (0.1 + 0.05 * uA.y));
  // Color por zonas que se desplazan despacio.
  float zone = 0.5 + 0.5 * sin(p.x * 3.1 + p.y * 2.3 + uA.x * 0.25);
  vec3 neon = mix(uC1, uC2, smoothstep(0.35, 0.65, zone));
  // Luz que corre en ondas desde el centro.
  float run = 1.0;
  if (uB.w > 0.5) run = 0.45 + 0.75 * pow(0.5 + 0.5 * sin(length(p) * 14.0 - uA.x * 4.0), 3.0);
  // La ola del golpe ilumina las losetas que gira.
  float waveLight = exp(-abs(d - uW.y) * 10.0) * step(uW.y, 3.0);
  vec3 col = uC0 + neon * 0.025;
  col += neon * glow * 0.22 * (run + waveLight) * uW.z;
  col = mix(col, neon * (0.55 + 0.45 * run + waveLight), tubeEdge);
  col = mix(col, mix(neon, uC3, 0.55) * (0.8 + 0.6 * run + 0.6 * uA.z), core);
  col += neon * uW.w * 0.05;
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
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
