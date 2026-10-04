// Jardín Alucinante — flores psicodélicas de póster setentero.
// Una gran flor central de tres capas de pétalos (8, 12 y 6) gira capa contra
// capa con contornos oscuros y colores planos intensos; seis flores pequeñas
// orbitan a su alrededor y, detrás, un sol de rayos naranjas y amarillos gira
// al revés. Cada golpe hace florecer los pétalos con un muelle, los graves
// los hinchan, la energía acelera los giros y los colores avanzan despacio.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double spin = 0, orbit = 0, hue = 0;
  float bloom = 0, bloomVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    spin = rng.unit() * 6.2831853;
    orbit = rng.unit() * 6.2831853;
    hue = rng.unit();
    bloom = bloomVel = 0;
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
    if (hit > kick + 0.2f) bloomVel += 2.4f * hit;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // Los pétalos florecen con el golpe y vuelven con un muelle.
    bloomVel += (-bloom * 30.0f - bloomVel * 6.0f) * dt;
    bloom += bloomVel * dt;
    spin += f.delta * f.speed * (0.15 + 0.4 * drive);
    orbit += f.delta * f.speed * (0.08 + 0.2 * drive);
    hue += f.delta * (0.02 + 0.05 * energy);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(spin, 6.2831853)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(std::fmod(orbit, 6.2831853)), float(std::fmod(hue, 100.0)), std::max(-0.3f, bloom) * amp, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("flower_power", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'flower_power': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // giro, graves, golpe, energía
uniform vec4 uB;   // órbita, ciclo de color, floración, destello
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float TAU = 6.2831853;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec3 flowerColor(float x) {
  float k = mod(floor(x), 4.0);
  return k < 1.0 ? uC1 : (k < 2.0 ? uC2 : (k < 3.0 ? vec3(1.0, 0.88, 0.1) : uC3));
}

// Capa de pétalos: devuelve relleno (x) y contorno (y) en coordenadas polares.
vec2 petals(float r, float a, float n, float R, float rot) {
  float shape = pow(abs(cos((a + rot) * n * 0.5)), 0.7);
  float edge = R * (0.38 + 0.62 * shape);
  float fill = smoothstep(edge + 0.003, edge - 0.003, r);
  float line = exp(-abs(r - edge) * 260.0);
  return vec2(fill, line);
}

// Flor completa con tres capas y centro de puntos; pinta sobre "col".
vec3 flower(vec2 p, float R, float rot, float hueBase, vec3 col) {
  float r = length(p);
  if (r > R * 1.05) return col;
  float a = atan(p.y, p.x);
  vec3 ink = vec3(0.12, 0.02, 0.08);
  vec2 l0 = petals(r, a, 8.0, R, rot);
  col = mix(col, flowerColor(hueBase), l0.x);
  col = mix(col, ink, l0.y * 0.9);
  vec2 l1 = petals(r, a, 12.0, R * 0.7, -rot * 1.3 + 0.2);
  col = mix(col, flowerColor(hueBase + 1.0), l1.x);
  col = mix(col, ink, l1.y * 0.9);
  vec2 l2 = petals(r, a, 6.0, R * 0.45, rot * 1.7);
  col = mix(col, flowerColor(hueBase + 2.0), l2.x);
  col = mix(col, ink, l2.y * 0.9);
  float center = smoothstep(R * 0.2, R * 0.19, r);
  vec3 cc = flowerColor(hueBase + 3.0);
  float dots = smoothstep(0.35, 0.25, length(fract(p / (R * 0.06)) - 0.5));
  col = mix(col, mix(cc, ink, dots * 0.6), center);
  col = mix(col, ink, exp(-abs(r - R * 0.2) * 300.0) * 0.9);
  return col;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float r = length(p);
  float a = atan(p.y, p.x);
  // Sol de rayos naranjas y amarillos que gira al revés.
  float rays = step(0.5, fract((a - uA.x * 0.5) / TAU * 24.0));
  vec3 col = mix(mix(uC2, vec3(1.0, 0.85, 0.15), rays), uC0, smoothstep(0.3, 1.4, r) * 0.55);
  col *= 0.75 + 0.25 * smoothstep(0.0, 0.6, r);
  float hueBase = floor(uB.y);
  float bloom = 1.0 + 0.25 * uB.z + 0.1 * uA.y;
  // Seis flores pequeñas en órbita: sólo la más cercana puede tocar el píxel.
  float slot = floor((a - uB.x) / (TAU / 6.0) + 0.5);
  float oa = uB.x + slot * TAU / 6.0;
  vec2 c = vec2(cos(oa), sin(oa)) * 0.62;
  col = flower(p - c, 0.17 * bloom, uA.x * 1.4 + slot, hueBase + mod(slot, 6.0), col);
  // Flor central grande.
  col = flower(p, 0.42 * bloom, uA.x, hueBase + 1.0, col);
  col *= 0.9 + 0.3 * uA.z;
  col = mix(col, vec3(1.0), uB.w * 0.06);
  col *= 1.0 - 0.3 * smoothstep(0.7, 1.5, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
