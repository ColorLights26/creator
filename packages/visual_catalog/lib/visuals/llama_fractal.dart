// Llama Fractal — seda de luz que se pliega como una llama fractal.
// Cada píxel recorre cinco transformaciones suaves (giro, seno y remolino, las
// variaciones clásicas de las llamas fractales) y brilla donde su órbita roza
// una línea o un anillo: el resultado son cintas sedosas enrolladas en
// remolinos con núcleos blancos. Cada dos golpes la llama muta a otra forma;
// los graves la avivan, el golpe la hace respirar y los agudos encienden los
// filamentos más finos.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  double phase = 0, drift = 0, sinceMorph = 0;
  std::array<float, 4> from{}, to{};
  float morph = 1, breath = 0, breathVel = 0;
  int beats = 0, shape = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Formas elegidas: giro inicial, giro por iteración, frecuencia y remolino.
  static std::array<float, 4> shapeAt(int i) {
    static const float shapes[6][4] = {{0.8f, 1.3f, 1.3f, 1.0f}, {0.6f, 1.7f, 1.1f, 1.8f}, {1.5f, 1.1f, 1.2f, 1.3f},
                                       {0.9f, 2.4f, 1.4f, 0.9f}, {0.1f, 2.0f, 1.5f, 1.4f}, {0.3f, 0.9f, 1.7f, 0.6f}};
    const float* s = shapes[((i % 6) + 6) % 6];
    return {s[0], s[1], s[2], s[3]};
  }

  void next() {
    float e = morph * morph * (3.0f - 2.0f * morph);
    for (int i = 0; i < 4; i++) from[i] = from[i] + (to[i] - from[i]) * e;
    shape++;
    to = shapeAt(shape);
    morph = 0;
    sinceMorph = 0;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    phase = rng.unit() * 6.2831853;
    drift = rng.unit() * 10.0;
    sinceMorph = 0;
    shape = int(rng.unit() * 6.0f);
    from = to = shapeAt(shape);
    morph = 1;
    breath = breathVel = 0;
    beats = 0;
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
    if (hit > kick + 0.2f) {
      beats++;
      breathVel += 1.4f * hit;
      if (beats % 2 == 0) next();
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // La llama respira con el golpe y vuelve con un muelle amortiguado.
    breathVel += (-breath * 30.0f - breathVel * 6.0f) * dt;
    breath += breathVel * dt;
    morph = std::min(1.0f, morph + dt * 1.1f);
    sinceMorph += f.delta;
    // En silencio la llama cambia de forma cada diez segundos.
    if (!m.active && sinceMorph > 10.0) next();
    phase += f.delta * f.speed * (0.07 + 0.25 * drive + 0.1 * bass);
    drift += f.delta * f.speed * (0.15 + 0.3 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float e = morph * morph * (3.0f - 2.0f * morph);
    std::array<float, 4> p;
    for (int i = 0; i < 4; i++) p[i] = from[i] + (to[i] - from[i]) * e;
    // Ondulación lenta del remolino para que la seda nunca quede quieta.
    p[3] += 0.15f * float(std::sin(drift * 0.9));
    p[2] += 0.05f * float(std::sin(drift * 0.6 + 1.3));
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(phase, 6.2831853)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {p[0], p[1], p[2], p[3]});
    u.insert(u.end(), {f.glow, spark * amp, 1.0f + 0.08f * breath * amp, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("flame", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'flame': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // fase de giro, graves, golpe, energía
uniform vec4 uP;   // giro inicial, giro por iteración, frecuencia, remolino
uniform vec4 uD;   // glow, agudos, zoom, destello
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

// Paleta en luz lineal por iteración: azul, violeta y blanco lavanda.
vec3 palette(float x) {
  vec3 c1 = pow(uC1, vec3(2.2));
  vec3 c2 = pow(uC2, vec3(2.2));
  vec3 c3 = pow(uC3, vec3(2.2));
  return x < 0.5 ? mix(c1, c2, x * 2.0) : mix(c2, c3, x * 2.0 - 1.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  vec2 z = p * 2.2 / uD.z;
  float kick = uA.z;

  vec3 glow = vec3(0.0);
  for (int i = 0; i < 5; i++) {
    float fi = float(i);
    float ang = uP.x + fi * uP.y + uA.x;
    float ca = cos(ang);
    float sa = sin(ang);
    z = vec2(ca * z.x - sa * z.y, sa * z.x + ca * z.y);
    // Variación sinusoidal seguida de un remolino.
    z = sin(z * uP.z) * 1.3;
    float r2 = dot(z, z);
    float cs = cos(r2 * uP.w);
    float ss = sin(r2 * uP.w);
    z = vec2(z.x * ss - z.y * cs, z.x * cs + z.y * ss);
    // La órbita brilla cerca de una línea y de un anillo: cintas de seda.
    float k = 14.0 * (1.0 + 0.35 * fi);
    float trap = exp(-abs(z.y) * k) + 0.4 * exp(-abs(length(z) - 0.8) * k);
    float weight = 1.0 / (1.0 + 0.55 * fi);
    if (i == 4) weight *= 1.0 + 2.0 * uD.y;
    glow += palette(fi * 0.25) * trap * weight;
  }

  float r = length(p);
  float gain = (1.3 + 0.8 * uA.y + 1.1 * kick + 0.3 * uA.w) * uD.x;
  vec3 I = glow * (0.25 + 1.2 * exp(-r * r * 3.0));
  I = max(I * 0.9 * gain - 0.03, 0.0);
  I += palette(0.6) * uD.w * 0.08;

  // Mapeo de tonos que conserva el tono y núcleos blancos donde la seda arde.
  float peak = max(I.r, max(I.g, I.b));
  float mapped = clamp((peak * (2.51 * peak + 0.03)) / (peak * (2.43 * peak + 0.59) + 0.14), 0.0, 1.0);
  vec3 col = I * (mapped / max(peak, 0.0001)) + vec3(max(peak - 1.2, 0.0) * 0.25);
  col += pow(uC0, vec3(2.2));
  col = pow(clamp(col, 0.0, 1.0), vec3(0.4545));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
