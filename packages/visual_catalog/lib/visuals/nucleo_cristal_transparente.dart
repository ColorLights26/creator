// Núcleo de Cristal Transparente — un cristal de luz que lanza contornos de neón.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// En el centro late un cristal en espejo hecho de facetas plegadas, con un
// corazón blanco y destellos laterales. De él salen hacia la cámara contornos
// de neón simétricos (rombos, hexágonos, estrellas cóncavas y barras) que
// crecen hasta salir de la pantalla; cada uno cambia de forma y de color
// (azul, naranja, rojo o blanco). Cada golpe acelera la salida y enciende el
// contorno más nuevo, los graves hacen latir el cristal y los agudos sueltan
// chispas a su alrededor.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double travel = 0, clock = 0;
  float boost = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    travel = rng.unit() * 8.0;
    clock = rng.unit() * 50.0;
    boost = 0;
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
    if (hit > kick + 0.2f) boost = std::max(boost, hit);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    boost *= std::exp(-dt * 3.0f);
    travel += f.delta * f.speed * (0.28 + 0.45 * drive + 1.2 * boost);
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(std::fmod(travel, 1000.0)), f.glow, spark * amp, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("crystal_core", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'crystal_core': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // avance de los contornos, glow, agudos, destello
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

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
             mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// "Radio" de cada forma en el cuadrante en espejo: la línea está donde vale s.
float shapeRadius(float type, vec2 q) {
  if (type < 0.5) return q.x * 0.72 + q.y;                         // rombo alto
  if (type < 1.5) return max(q.x * 0.95, q.x * 0.5 + q.y * 0.87);  // hexágono
  if (type < 2.5) {
    vec2 r = sqrt(q + 1e-5);                                       // estrella cóncava
    return (r.x + r.y) * (r.x + r.y) * 0.5;
  }
  return max(q.x * 1.25, (q.x * 0.55 + q.y) * 0.85);               // barras y rombo
}

vec3 waveColor(float id) {
  float k = mod(id, 4.0);
  return k < 1.0 ? uC1 : (k < 2.0 ? uC2 : (k < 3.0 ? vec3(1.0, 0.25, 0.2) : vec3(0.85, 0.92, 1.0)));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  vec2 q = abs(p);
  float r = length(p);
  float t = uA.x;
  float kick = uA.z;

  // Sin nebulosa de fondo: el cristal flota sobre lo que haya detrás.
  vec3 col = uC0;

  // Contornos de neón que salen del centro.
  for (int k = 0; k < 4; k++) {
    float fk = float(k);
    float wave = uB.x * 0.35 + fk * 0.25;
    float id = floor(wave);
    float ph = fract(wave);
    float s = 0.11 * exp(ph * 3.3);
    float type = mod(id + hash11(id) * 3.0, 4.0);
    float F = shapeRadius(floor(type), q);
    float width = 0.0035 + 0.012 * s;
    float d = abs(F - s);
    float fade = smoothstep(0.0, 0.08, ph) * smoothstep(1.0, 0.7, ph);
    vec3 wc = waveColor(id);
    float isNew = smoothstep(0.25, 0.0, ph);
    float lineCore = exp(-d / (width * 0.35));
    float lineGlow = exp(-d / (width * 2.5));
    col += (wc * lineGlow * 0.55 + mix(wc, vec3(1.0), 0.6) * lineCore) * fade * (1.0 + 1.5 * kick * isNew) * uB.y;
    // Línea fina paralela, como un segundo trazo de alambre.
    float d2 = abs(F - s * 1.07);
    col += uC1 * exp(-d2 / (width * 0.25)) * fade * 0.35;
  }

  // Cristal central: facetas plegadas en espejo que giran despacio.
  float coreR = 0.24 * (1.0 + 0.12 * uA.y + 0.08 * kick);
  if (r < coreR * 1.6) {
    vec2 z = p / coreR;
    float edges = 0.0;
    for (int i = 0; i < 4; i++) {
      z = abs(z) - vec2(0.42, 0.3);
      float a = 0.7 + 0.05 * sin(t * 0.3 + float(i));
      z = vec2(cos(a) * z.x - sin(a) * z.y, sin(a) * z.x + cos(a) * z.y);
      edges += exp(-min(abs(z.x), abs(z.y)) * 28.0);
    }
    float body = smoothstep(1.15, 0.6, max(q.x * 0.8 + q.y, 0.0) / coreR);
    vec3 facet = mix(vec3(0.25, 0.15, 0.55), uC1, 0.4) * (0.35 + 0.25 * edges) + uC3 * edges * 0.12;
    col = mix(col, facet + col * 0.4, body * 0.85);
  }
  // Corazón blanco, destellos laterales y halo rosado.
  col += vec3(1.0, 0.95, 1.0) * (0.02 + 0.03 * uA.y + 0.05 * kick) / (r * r + 0.004) * exp(-r * r * 12.0);
  float flare = exp(-q.y * 60.0) * exp(-q.x * 2.2) + exp(-q.x * 90.0) * exp(-q.y * 6.0) * 0.4;
  col += mix(uC3, vec3(1.0), 0.5) * flare * (0.6 + 0.8 * kick);
  vec2 side = vec2(q.x - coreR * 0.95, q.y);
  col += uC3 * 0.012 / (dot(side, side) + 0.002) * (0.5 + 0.8 * uA.y) * exp(-dot(side, side) * 20.0);
  // Chispas alrededor del cristal con los agudos.
  vec2 cell = floor(p * 40.0);
  float sparkle = step(0.985 - 0.02 * uB.z, hash12(cell + floor(t * 10.0))) * smoothstep(0.6, 0.15, r);
  col += vec3(0.8, 0.9, 1.0) * sparkle * uB.z;

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
