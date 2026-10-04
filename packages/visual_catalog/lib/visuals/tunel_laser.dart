// Túnel Láser Arcoíris — túnel de paneles dorados con marcos y láseres de color.
// La cámara avanza por un túnel cuadrado cuyas paredes tienen paneles de luz
// dorada encendidos al azar. Marcos de neón cuadrados, cada uno de un color
// del arcoíris y girado un poco más que el anterior, vienen hacia la cámara, y
// cuatro haces láser (amarillo, magenta, cian y verde) salen del fondo y
// barren la pantalla. Cada golpe empuja la cámara y abre los láseres, los
// graves encienden los paneles y la energía acelera el giro de los marcos.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double travel = 0, twist = 0, sweep = 0;
  float boost = 0, laser = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    travel = rng.unit() * 20.0;
    twist = rng.unit() * 6.2831853;
    sweep = rng.unit() * 6.2831853;
    boost = laser = 0;
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
      boost = std::max(boost, hit);
      laser = std::max(laser, hit);
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    boost *= std::exp(-dt * 3.0f);
    laser *= std::exp(-dt * 2.0f);
    travel += f.delta * f.speed * (0.8 + 1.5 * drive + 2.0 * boost);
    twist += f.delta * f.speed * (0.1 + 0.4 * drive);
    sweep += f.delta * f.speed * (0.25 + 0.5 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(travel, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {float(std::fmod(twist, 6.2831853)), f.glow, spark * amp, flash * amp});
    u.insert(u.end(), {float(std::fmod(sweep, 6.2831853)), (0.35f + laser) * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("laser_tunnel", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'laser_tunnel': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // avance, graves, golpe, energía
uniform vec4 uB;   // giro de los marcos, glow, agudos, destello
uniform vec4 uL;   // barrido de los láseres, fuerza de los láseres
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

vec3 beamColor(int i) {
  return i == 0 ? vec3(1.0, 0.95, 0.1) : (i == 1 ? uC2 : (i == 2 ? uC3 : vec3(0.4, 1.0, 0.2)));
}

vec3 rainbow(float x) {
  return clamp(abs(fract(x + vec3(0.0, 0.333, 0.667)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float travel = uA.x;
  float kick = uA.z;

  // Túnel cuadrado: paneles dorados en las paredes.
  float sq = max(abs(p.x), abs(p.y)) + 1e-4;
  float z = 0.3 / sq;
  float depth = z + travel;
  bool side = abs(p.x) > abs(p.y);
  float v = side ? p.y / abs(p.x) : p.x / abs(p.y);
  float wallId = side ? (p.x > 0.0 ? 0.0 : 1.0) : (p.y > 0.0 ? 2.0 : 3.0);
  vec2 g = vec2(v * 4.0 + wallId * 13.0, depth * 2.5);
  vec2 cell = floor(g);
  vec2 lc = fract(g);
  float h = hash12(cell);
  vec2 size = vec2(0.2 + 0.25 * hash12(cell + 1.3), 0.15 + 0.3 * hash12(cell + 2.7));
  vec2 dd = abs(lc - 0.5) - size;
  float panel = step(0.62, h) * smoothstep(0.03, -0.01, max(dd.x, dd.y));
  float fog = exp(-z * 0.14);
  vec3 wall = vec3(0.05, 0.035, 0.02) * (0.6 + 0.4 * hash12(cell + 9.0));
  vec3 col = uC0 + wall * fog;
  col += uC1 * mix(vec3(1.0), vec3(1.0, 0.9, 0.6), h) * panel * fog * (0.8 + 0.8 * uA.y + 0.6 * kick);

  // Marcos de neón arcoíris girados que vienen hacia la cámara.
  for (int k = 0; k < 4; k++) {
    float fk = float(k);
    float fz = fk + 1.0 - fract(travel * 0.4);
    float R = 0.3 / fz;
    float ang = uB.x + (floor(travel * 0.4) + fk) * 0.45;
    float c = cos(ang);
    float s = sin(ang);
    vec2 q = vec2(c * p.x + s * p.y, -s * p.x + c * p.y);
    float d = abs(max(abs(q.x), abs(q.y)) - R);
    float w = 0.002 + 0.004 / fz;
    float bright = smoothstep(4.0, 3.0, fz) * smoothstep(0.2, 0.5, fz);
    vec3 rc = rainbow(fk * 0.23 + floor(travel * 0.4) * 0.23);
    col += rc * (exp(-d / (w * 0.5)) + 0.35 * exp(-d / (w * 3.0))) * bright * (1.0 + kick) * uB.y;
  }

  // Cuatro láseres de color que salen del fondo y barren la pantalla.
  float r = length(p);
  float a = atan(p.y, p.x);
  for (int i = 0; i < 4; i++) {
    float ba = uL.x * (i < 2 ? 1.0 : -1.0) + float(i) * TAU / 4.0 + 0.4;
    float da = abs(sin(a - ba)) * r;
    float front = step(0.0, cos(a - ba));
    float width = 0.004 + 0.035 * r;
    float beam = (exp(-da / width) * 0.6 + exp(-da / (width * 0.25))) * front * smoothstep(0.05, 0.35, r);
    col += beamColor(i) * beam * uL.y;
  }

  // Marco pequeño al final del túnel.
  float endD = abs(sq - 0.04);
  col += rainbow(travel * 0.1) * exp(-endD * 300.0) * 0.9;
  col += uC1 * uB.w * 0.06;
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
