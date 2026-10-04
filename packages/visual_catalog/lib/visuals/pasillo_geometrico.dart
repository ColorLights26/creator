// Pasillo Geométrico — formas de neón que nacen en el centro y vienen hacia ti.
// Sobre negro puro, un pequeño triángulo rojo marca el fondo del pasillo. Con
// cada golpe nace allí una forma de neón (triángulo, rombo, cruz o estrella
// de picos), en rojo o en blanco con borde azul, que crece hasta llenar la
// pantalla y desaparece; las formas grandes sueltan ráfagas de picos desde
// los bordes. Sin golpes nace una forma cada segundo y medio. Los graves
// engordan el neón y el destello enciende la pantalla.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kWaves = 4;
  struct Wave { double born = -100; int type = 0, color = 0; float power = 0; };
  std::array<Wave, kWaves> waves{};
  int next = 0, count = 0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Las formas se describen por su edad: la escena es idéntica a 30 y 60 FPS.
  double clock = 0, nextAuto = 0.2;
  Random rng{71};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void spawn(double born, float power) {
    Wave& w = waves[size_t(next)];
    next = (next + 1) % kWaves;
    w.born = born;
    w.type = int(rng.unit() * 4.0f) % 4;
    w.color = count % 2;
    w.power = power;
    count++;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    waves = {};
    next = count = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = 0;
    nextAuto = 0.2;
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
    clock += f.delta * f.speed;
    if (hit > kick + 0.2f) {
      spawn(clock, 0.7f + 0.3f * hit);
      nextAuto = clock + 1.5;
    }
    while (clock >= nextAuto) {
      spawn(nextAuto, 0.75f);
      nextAuto += 1.5;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(36);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, 0.0f});
    for (int k = 0; k < kWaves; k++) {
      const Wave& w = waves[size_t(k)];
      // Edad acotada: las formas sin nacer o ya pasadas quedan fuera de la vista.
      float age = std::clamp(float(clock - w.born), 0.0f, 2.0f);
      // Tamaño exponencial: la forma parece acercarse a velocidad constante.
      float size = 0.05f * std::exp(age * 2.4f);
      float alpha = w.born < -50 || size > 4.0f ? 0.0f : w.power * std::clamp(age / 0.08f, 0.0f, 1.0f);
      u.insert(u.end(), {size, float(w.type), float(w.color), alpha * amp});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("geo_corridor", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'geo_corridor': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello
uniform vec4 uW0;  // formas: tamaño, tipo, color, intensidad
uniform vec4 uW1;
uniform vec4 uW2;
uniform vec4 uW3;
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

// Distancia al contorno de un triángulo equilátero de radio r (apuntando arriba).
float triangleEdge(vec2 p, float r) {
  p.y = -p.y;
  const float k = 1.7320508;
  p.x = abs(p.x) - r * 0.866;
  p.y = p.y + r * 0.5;
  if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
  p.x -= clamp(p.x, -r * 1.732, 0.0);
  return abs(-length(p) * sign(p.y));
}

float boxEdge(vec2 p, vec2 b) {
  vec2 d = abs(p) - b;
  return abs(length(max(d, 0.0)) + min(max(d.x, d.y), 0.0));
}

// Distancia al contorno de la forma de tipo "type" y tamaño s.
float shapeEdge(float type, vec2 p, float s) {
  if (type < 0.5) return triangleEdge(p, s);
  if (type < 1.5) {
    vec2 q = abs(p);
    return abs(q.x + q.y - s) * 0.7071;                       // rombo
  }
  if (type < 2.5) {
    // Cruz de cinco cuadrados.
    float c = boxEdge(p, vec2(s * 0.34));
    c = min(c, boxEdge(p - vec2(s * 0.68, 0.0), vec2(s * 0.34)));
    c = min(c, boxEdge(p + vec2(s * 0.68, 0.0), vec2(s * 0.34)));
    c = min(c, boxEdge(p - vec2(0.0, s * 0.68), vec2(s * 0.34)));
    c = min(c, boxEdge(p + vec2(0.0, s * 0.68), vec2(s * 0.34)));
    return c;
  }
  // Estrella de ocho picos.
  float a = atan(p.y, p.x);
  float r = length(p);
  float spike = s * (0.55 + 0.45 * pow(abs(cos(a * 4.0)), 6.0));
  return abs(r - spike) * 0.8;
}

vec3 shapeLight(vec2 p, vec4 W) {
  if (W.w < 0.003) return vec3(0.0);
  float s = W.x;
  float d = shapeEdge(W.y, p, s);
  float w = 0.004 + 0.035 * s;
  float core = exp(-d / (w * 0.45));
  float glow = exp(-d / (w * 2.2));
  vec3 base = W.z < 0.5 ? uC1 : uC2;
  vec3 halo = W.z < 0.5 ? uC1 : uC3;
  vec3 col = halo * glow * 0.7 + mix(base, vec3(1.0), 0.45) * core;
  // Ráfaga de picos desde los bordes cuando la forma ya es grande.
  float a = atan(p.y, p.x);
  float r = length(p);
  float spikes = pow(abs(cos(a * 6.0 + W.y)), 40.0) * smoothstep(s * 0.9, s * 1.6, r) * smoothstep(0.4, 1.2, s);
  col += halo * spikes * 0.6;
  float fade = smoothstep(3.6, 1.6, s);
  return col * W.w * fade;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  vec3 col = uC0;
  float boost = 1.0 + 0.6 * uA.y + 0.6 * uA.z;
  col += shapeLight(p, uW0) * boost * uB.x;
  col += shapeLight(p, uW1) * boost * uB.x;
  col += shapeLight(p, uW2) * boost * uB.x;
  col += shapeLight(p, uW3) * boost * uB.x;
  // El triángulo del fondo del pasillo, siempre presente.
  float d0 = triangleEdge(p, 0.05);
  col += uC1 * (exp(-d0 / 0.0016) + 0.4 * exp(-d0 / 0.008)) * (0.9 + 0.6 * uA.z);
  float d1 = triangleEdge(p, 0.028);
  col += uC2 * exp(-d1 / 0.0012) * 0.6;
  col += uC1 * uB.z * 0.06;
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
