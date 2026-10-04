// Derretimiento — bandas de color psicodélicas que se derriten.
// La pantalla está pintada con bandas de colores intensos separadas por
// trazos oscuros; un campo retorcido las ondula y chorros de pintura caen
// desde arriba estirándolas hacia abajo, como un cuadro que se derrite. Los
// colores avanzan sin parar; los graves retuercen más las bandas, cada golpe
// da un salto de color y un brillo, y la energía acelera los goteos.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double flow = 0, melt = 0;
  float hueKick = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    flow = rng.unit() * 20.0;
    melt = rng.unit() * 20.0;
    hueKick = 0;
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
    if (hit > kick + 0.2f) hueKick += 0.18f * hit;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    flow += f.delta * f.speed * (0.25 + 0.6 * drive);
    melt += f.delta * f.speed * (0.06 + 0.2 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(flow, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(std::fmod(melt, 1000.0)), float(std::fmod(hueKick, 100.0)), f.glow, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("melt_bands", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'melt_bands': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // flujo, graves, golpe, energía
uniform vec4 uB;   // goteo, salto de color, glow, destello
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

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
             mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Paleta de póster: rojo, naranja, amarillo, magenta, turquesa, violeta.
vec3 poster(float x) {
  float k = fract(x) * 6.0;
  vec3 c0 = uC1;
  vec3 c1 = uC2;
  vec3 c2 = vec3(1.0, 0.9, 0.2);
  vec3 c3 = vec3(1.0, 0.1, 0.6);
  vec3 c4 = uC3;
  vec3 c5 = vec3(0.45, 0.1, 0.85);
  vec3 a = k < 1.0 ? c0 : (k < 2.0 ? c1 : (k < 3.0 ? c2 : (k < 4.0 ? c3 : (k < 5.0 ? c4 : c5))));
  vec3 b = k < 1.0 ? c1 : (k < 2.0 ? c2 : (k < 3.0 ? c3 : (k < 4.0 ? c4 : (k < 5.0 ? c5 : c0))));
  return mix(a, b, smoothstep(0.7, 1.0, fract(k)));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uA.x;
  // Chorros que caen desde arriba: columnas que estiran la pintura hacia abajo.
  float cols = 7.0;
  float cx = p.x * cols;
  float id = floor(cx);
  float local = fract(cx) - 0.5;
  float h = hash12(vec2(id, 3.0));
  float len = fract(uB.x * (0.4 + 0.5 * h) + h) * 1.6;
  float column = exp(-local * local * 9.0) * smoothstep(-0.8, 0.0, -(p.y + 0.6 - len)) * smoothstep(-0.6, 0.4, p.y);
  float drip = column * (0.25 + 0.3 * h);
  // Campo retorcido que ondula las bandas.
  vec2 q = vec2(p.x, p.y + drip);
  float w = 0.35 + 0.35 * uA.y;
  vec2 warp = vec2(noise(q * 2.0 + vec2(t * 0.3, 0.0)), noise(q * 2.0 + vec2(4.1, -t * 0.25))) - 0.5;
  q += warp * w;
  float v = q.y * 4.0 + 0.6 * sin(q.x * 3.0 + t * 0.5) + noise(q * 4.0) * 0.6 - t * 0.35 + uB.y;
  vec3 col = poster(v * 0.5);
  // Trazos oscuros entre bandas y brillo de pintura fresca.
  float edge = abs(fract(v * 3.0) - 0.5);
  col *= 0.35 + 0.65 * smoothstep(0.02, 0.12, edge);
  float gloss = pow(max(0.0, 1.0 - abs(fract(v * 3.0 + 0.2) - 0.5) * 6.0), 4.0);
  col += vec3(1.0) * gloss * 0.12 * (1.0 + uA.z);
  col *= (0.85 + 0.3 * uA.y + 0.35 * uA.z) * mix(1.0, uB.z, 0.5);
  col = mix(col, vec3(1.0), uB.w * 0.06);
  col *= 1.0 - 0.25 * smoothstep(0.6, 1.5, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
