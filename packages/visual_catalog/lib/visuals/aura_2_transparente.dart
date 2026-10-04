// Aura 2 Transparente — degradado de color intenso que gira, late y estalla.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Versión de alto impacto del Aura: rojo encendido, naranja y azul eléctrico
// con contraste fuerte y zonas negras entre las manchas. Las manchas se mueven
// más rápido, los graves las hinchan, cada golpe las hace estallar en tamaño y
// brillo con un núcleo blanco donde se cruzan, y la energía retuerce el remolino.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, twist = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 100.0;
    twist = rng.unit() * 6.2831853;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 12.0f, 2.5f, dt);
    body = follow(body, m.body, 10.0f, 2.5f, dt);
    spark = follow(spark, m.spark, 20.0f, 5.0f, dt);
    energy = follow(energy, m.energy, 5.0f, 1.5f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    kick = std::max(kick * std::exp(-dt * 3.5f), hit);
    flash = std::max(flash * std::exp(-dt * 6.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (0.5 + 1.1 * drive);
    twist += f.delta * f.speed * (0.15 + 0.6 * energy + 0.4 * kick);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float aspectY = f.height / std::max(1.0f, std::min(f.width, f.height));
    std::vector<float> u;
    u.reserve(40);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, 0.9f * float(std::sin(twist))});
    float bx[5], by[5], br[5];
    for (int i = 0; i < 5; i++) {
      double t = clock * (0.5 + 0.11 * i) + i * 2.4;
      bx[i] = 0.42f * float(std::sin(t * 0.8 + i * 1.3));
      by[i] = 0.42f * aspectY * float(std::cos(t * 0.6 + i * 0.7));
      br[i] = (0.30f + 0.05f * float(i % 3)) * (1.0f + 0.45f * bass * amp + 0.3f * kick * amp);
    }
    u.insert(u.end(), {bx[0], by[0], bx[1], by[1]});
    u.insert(u.end(), {bx[2], by[2], bx[3], by[3]});
    u.insert(u.end(), {bx[4], by[4], br[4], 0.0f});
    u.insert(u.end(), {br[0], br[1], br[2], br[3]});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("aura_blend", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'aura_blend': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello, remolino
uniform vec4 uP0;  // manchas 1 y 2
uniform vec4 uP1;  // manchas 3 y 4
uniform vec4 uP2;  // mancha 5 y su radio
uniform vec4 uR0;  // radios 1 a 4
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

void blob(vec2 p, vec2 b, float r, vec3 c, inout vec3 acc, inout float wsum) {
  vec2 d = p - b;
  float w = exp(-dot(d, d) / (r * r));
  acc += c * w;
  wsum += w;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  // Remolino suave: el giro es mayor cerca del centro.
  float ang = uB.w * exp(-dot(p, p) * 1.2);
  float ca = cos(ang);
  float sa = sin(ang);
  vec2 q = vec2(ca * p.x - sa * p.y, sa * p.x + ca * p.y);
  vec3 acc = vec3(0.0);
  float wsum = 0.0;
  blob(q, uP0.xy, uR0.x, uC1, acc, wsum);
  blob(q, uP0.zw, uR0.y, uC2, acc, wsum);
  blob(q, uP1.xy, uR0.z, uC3, acc, wsum);
  blob(q, uP1.zw, uR0.w, mix(uC1, uC2, 0.5), acc, wsum);
  blob(q, uP2.xy, uP2.z, mix(uC2, uC3, 0.5), acc, wsum);
  // Mezcla tipo pintura: media ponderada sobre la base oscura.
  vec3 paint = (acc + uC0 * 0.05) / (wsum + 0.05);
  vec3 col = mix(uC0, paint, clamp(wsum * 1.6 - 0.15, 0.0, 1.0));
  // Colores más vivos y luminosos, como el fondo de Apple Music.
  float luma = dot(col, vec3(0.299, 0.587, 0.114));
  col = max(mix(vec3(luma), col, 1.7), 0.0);
  col *= (1.0 + 0.4 * uA.y + 0.45 * uA.z) * mix(1.0, uB.x, 0.5);
  // Núcleo caliente donde las manchas se cruzan, que estalla con el golpe.
  col += mix(uC1, vec3(1.0), 0.4) * smoothstep(1.3, 2.4, wsum) * (0.15 + 0.35 * uA.z);
  // Sólo las manchas flotan: donde casi no hay pintura queda transparente.
  col *= smoothstep(0.5, 1.1, wsum);
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
