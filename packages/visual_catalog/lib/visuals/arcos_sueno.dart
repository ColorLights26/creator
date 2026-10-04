// Arcos del Sueño — pasillo surrealista de arcos que se derriten.
// La cámara avanza por un pasillo de sección en arco: paredes y bóveda pintadas
// con bandas rojas, naranjas, doradas y crema que se ondulan y gotean, un
// suelo recorrido por un río de ondas turquesa, crema y rojo, y al fondo una
// puerta de luz con una esfera. Todo respira: los graves hinchan las paredes,
// cada golpe empuja la cámara y hace brillar los arcos, la energía acelera el
// avance y el destello enciende la puerta.
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
    travel = rng.unit() * 10.0;
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
    travel += f.delta * f.speed * (0.45 + 0.9 * drive + 1.5 * boost);
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(travel, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), f.glow, spark * amp, flash * amp});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("dream_arches", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'dream_arches': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // avance, graves, golpe, energía
uniform vec4 uB;   // reloj, glow, agudos, destello
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

const float PI = 3.14159265;

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

vec3 paint(float x) {
  float k = fract(x) * 4.0;
  vec3 cream = vec3(1.0, 0.86, 0.6);
  vec3 a = k < 1.0 ? uC1 : (k < 2.0 ? uC2 : (k < 3.0 ? cream : uC2));
  vec3 b = k < 1.0 ? uC2 : (k < 2.0 ? cream : (k < 3.0 ? uC2 : uC1));
  return mix(a, b, smoothstep(0.6, 1.0, fract(k)));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float t = uB.x;
  float travel = uA.x;
  // El pasillo respira con los graves y se ondula suavemente.
  p += 0.012 * vec2(sin(p.y * 6.0 + t), cos(p.x * 5.0 - t * 0.8)) * (1.0 + 2.0 * uA.y);
  p.y += 0.12;
  // Sección en arco: paredes rectas, suelo plano y bóveda semicircular.
  float s = p.y > 0.0 ? length(p) : max(abs(p.x), -p.y * 1.25);
  s = max(s, 1e-4);
  float z = 0.32 / s;
  float depth = z + travel;
  bool floorZone = p.y < 0.0 && -p.y * 1.25 > abs(p.x);
  vec3 col;
  if (floorZone) {
    // Suelo: río de ondas turquesa, crema y rojo.
    float u = p.x / (-p.y * 1.25);
    float river = u * 2.5 + 0.6 * sin(depth * 1.3 + u * 2.0) + 0.3 * noise(vec2(u * 3.0, depth * 0.8));
    float k = fract(river);
    vec3 cream = vec3(1.0, 0.9, 0.75);
    col = k < 0.33 ? uC3 : (k < 0.55 ? cream : (k < 0.8 ? uC1 : cream * 0.85));
    col *= 0.7 + 0.3 * smoothstep(0.0, 0.08, min(abs(k - 0.33), abs(k - 0.8)));
  } else {
    // Paredes y bóveda: bandas verticales que gotean.
    float v = p.y > 0.0 ? atan(p.x, p.y) / PI : (p.x > 0.0 ? 0.5 + (-p.y / s) * 0.5 : -0.5 - (-p.y / s) * 0.5);
    float melt = noise(vec2(v * 9.0, depth * 0.6)) * 0.5 + noise(vec2(v * 22.0, depth * 1.4 - t * 0.2)) * 0.25;
    col = paint(v * 1.6 + melt + depth * 0.05);
    // Arcos: anillos más oscuros con borde dorado a intervalos regulares.
    float fz = fract(depth * 0.5);
    float arch = smoothstep(0.0, 0.05, fz) * smoothstep(0.4, 0.3, fz);
    col = mix(col, col * vec3(0.35, 0.18, 0.12), arch);
    // Borde dorado del arco, nítido y brillante.
    col += mix(uC2, vec3(1.0, 0.9, 0.6), 0.4) * exp(-abs(fz - 0.4) * 60.0) * (0.6 + 0.9 * uA.z) * uB.y;
    col += uC2 * exp(-abs(fz) * 60.0) * 0.4 * uB.y;
    // Agujeros y manchas que salpican las paredes.
    float blot = smoothstep(0.82, 0.86, noise(vec2(v * 14.0, depth * 2.0)));
    col = mix(col, uC3 * 0.8, blot * 0.6);
  }
  // Niebla cálida y puerta de luz al fondo.
  col *= exp(-z * 0.11) * (0.85 + 0.35 * uA.y + 0.25 * uA.z);
  vec2 dp = p - vec2(0.0, 0.015);
  float door = smoothstep(0.06, 0.03, s);
  col = mix(col, mix(uC1, vec3(1.0, 0.8, 0.6), 0.4) * (1.2 + uB.w), door);
  col += vec3(1.0, 0.85, 0.7) * exp(-dot(dp, dp) * 3000.0) * (0.6 + 0.8 * uA.z);
  col += uC2 * uB.w * 0.05;
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
