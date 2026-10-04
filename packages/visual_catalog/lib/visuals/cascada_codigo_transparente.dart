// Cascada de Código Transparente — columnas de símbolos que caen como el código de Matrix.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Cada columna deja caer una o dos estelas de símbolos con una cabeza dorada
// brillante que se apaga hacia atrás; los símbolos cambian a ratos. La
// energía de la música acelera la caída, cada golpe lanza una onda dorada que
// barre la pantalla de arriba abajo, los graves avivan el brillo y los agudos
// hacen parpadear símbolos sueltos.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Reloj de caída en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double fall = 0, clock = 0, waveAge = 100;
  float wavePower = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    fall = rng.unit() * 100.0;
    clock = 0;
    waveAge = 100;
    wavePower = 0;
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
    waveAge += f.delta;
    if (hit > kick + 0.2f) {
      waveAge = 0;
      wavePower = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    fall += f.delta * f.speed * (1.0 + 1.8 * drive + 0.6 * bass);
    clock += f.delta;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float age = float(waveAge);
    // Onda: posición vertical (0 arriba, 1 abajo) y fuerza que se apaga.
    float waveY = age * 1.6f - 0.1f;
    float wave = age < 1.0f ? wavePower * (1.0f - age) * amp : 0.0f;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(fall, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), waveY, wave, spark * amp});
    u.insert(u.end(), {f.glow, flash * amp, std::clamp(f.detail, 0.25f, 2.0f), 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("code_rain", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'code_rain': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // caída, graves, golpe, energía
uniform vec4 uB;   // reloj, altura de la onda, fuerza de la onda, agudos
uniform vec4 uD;   // glow, destello, detalle
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

float hash11(float x) {
  x = fract(x * 0.1031);
  x *= x + 33.33;
  x *= x + x;
  return fract(x);
}

// Brillo de una estela en la fila "row" de la columna: cabeza y cola.
float drop(float row, float rows, float col, float k) {
  float speed = 7.0 + 10.0 * hash11(col * 1.7 + k * 31.0);
  float len = 14.0 + 22.0 * hash11(col * 3.1 + k * 17.0);
  float cycle = rows * 0.7 + len;
  float headRow = mod(uA.x * speed + hash11(col * 7.7 + k * 5.0) * cycle, cycle) - 3.0;
  float d = headRow - row;
  if (d < 0.0 || d > len) return 0.0;
  float tail = 1.0 - d / len;
  return tail * tail + step(d, 1.0) * 2.0;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float cols = 16.0 + 6.0 * uD.z;
  float cw = uSize.x / cols;
  float ch = cw * 1.3;
  float rows = uSize.y / ch;
  vec2 cell = floor(vec2(frag.x / cw, frag.y / ch));
  vec2 local = fract(vec2(frag.x / cw, frag.y / ch));
  float b = drop(cell.y, rows, cell.x, 0.0) + 0.85 * drop(cell.y, rows, cell.x + 100.0, 1.0) +
            0.7 * drop(cell.y, rows, cell.x + 200.0, 2.0);
  float head = step(1.5, b);
  // Símbolo: matriz de 5 x 7 puntos sacada de un hash; cambia a ratos.
  float change = floor(uB.x * (0.5 + 3.0 * hash12(cell + 3.0)) + hash12(cell) * 10.0);
  float glyph = hash12(cell * 1.31 + change * 7.0);
  vec2 g = local * vec2(7.0, 9.0) - vec2(1.0, 1.0);
  float lit = 0.0;
  if (g.x >= 0.0 && g.x < 5.0 && g.y >= 0.0 && g.y < 7.0) {
    vec2 gi = floor(g);
    // Mitad de los símbolos simétricos, como caracteres katakana.
    float gx = glyph > 0.5 ? min(gi.x, 4.0 - gi.x) : gi.x;
    float bit = step(0.52, hash12(vec2(gx, gi.y) + glyph * 97.0));
    vec2 sub = fract(g) - 0.5;
    lit = bit * smoothstep(0.5, 0.3, max(abs(sub.x), abs(sub.y)));
  }
  float bright = min(b, 1.0) * (0.95 + 0.45 * uA.y);
  vec3 trailCol = mix(uC1 * 0.55, uC1 * 1.2, min(b, 1.0));
  vec3 col = uC0;
  col += trailCol * lit * bright * uD.x;
  col += mix(uC2, uC3, 0.4) * lit * head * (0.9 + 0.5 * uA.z);
  // Resplandor suave alrededor de las cabezas.
  col += uC2 * head * 0.10 * uD.x;
  // Brillo tenue de la estela entre los puntos del símbolo.
  col += uC1 * min(b, 1.0) * 0.07 * uD.x;
  // Onda dorada del golpe que barre la pantalla.
  float y01 = frag.y / uSize.y;
  float wave = uB.z * exp(-(y01 - uB.y) * (y01 - uB.y) * 120.0);
  col += uC2 * wave * (0.25 + 0.9 * lit);
  // Parpadeo de símbolos sueltos con los agudos.
  float tw = step(0.985 - 0.02 * uB.w, hash12(cell + floor(uB.x * 9.0)));
  col += uC3 * tw * lit * uB.w;
  col *= 1.0 - 0.3 * smoothstep(0.6, 1.4, length((frag - 0.5 * uSize) / min(uSize.x, uSize.y) * vec2(0.9, 0.65)));
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
