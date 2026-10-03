// Polvo de Colores — explosiones de polvo Holi en cámara súper lenta.
// Cada dos golpes (o en cada golpe fuerte) estalla una nube de polvo de color:
// se expande rápido, frena, se retuerce en volutas y cae despacio mientras se
// desvanece, mezclándose con las anteriores. Granos sueltos salen disparados
// del centro de cada explosión. En el drop estallan dos nubes a la vez; los
// graves iluminan el polvo y los agudos encienden los granos.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kBursts = 4;
  struct Burst { float x = 0, y = 0, size = 0, seed = 0, hue = 0; double born = -100; };
  std::array<Burst, kBursts> bursts{};
  int next = 0, count = 0, beats = 0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Reloj propio en doble precisión; las nubes se describen por su edad, así
  // que la escena es idéntica a 30 y a 60 FPS.
  double clock = 0, nextAuto = 0.4, sinceDrop = 100;
  Random rng{41};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float hash(float n) {
    float x = std::sin(n) * 43758.5453f;
    return x - std::floor(x);
  }

  void spawn(double born, float size) {
    Burst& b = bursts[next];
    next = (next + 1) % kBursts;
    b.x = (rng.unit() - 0.5f) * 0.8f;
    b.y = (rng.unit() - 0.5f) * 1.2f;
    b.size = size * (0.85f + 0.4f * rng.unit());
    b.seed = rng.unit() * 50.0f;
    // Colores en turno con algún tono intermedio.
    b.hue = float(count % 3) + (rng.unit() < 0.3f ? 0.5f : 0.0f);
    b.born = born;
    count++;
  }

  // Edad, radio, desvanecido y posición de una nube.
  void state(const Burst& b, float& age, float& radius, float& fade, float& x, float& y) const {
    age = float(clock - b.born);
    radius = b.size * (0.12f + 0.88f * (1.0f - std::exp(-age * 2.0f))) + 0.025f * age;
    fade = std::exp(-age * 0.7f) * std::clamp(age / 0.06f, 0.0f, 1.0f);
    x = b.x;
    y = b.y - 0.03f * age + 0.004f * age * age;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bursts = {};
    next = count = beats = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = 0;
    nextAuto = 0.4;
    sinceDrop = 100;
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
    sinceDrop += f.delta;
    if (hit > kick + 0.2f) {
      if (hit > 0.7f && drive > 0.4f && sinceDrop > 6.0) {
        // Drop: dos nubes grandes a la vez.
        for (int i = 0; i < 2; i++) spawn(clock, 0.5f);
        sinceDrop = 0;
      } else if (hit > 0.8f || (++beats % 2) == 0) {
        // Una nube cada dos golpes (o en cada golpe fuerte): menos capas a la vez.
        spawn(clock, 0.3f + 0.15f * hit);
      }
      nextAuto = clock + 1.8;
    }
    // Sin golpes (silencio o música tranquila): una nube suave cada 2,4 s.
    while (clock >= nextAuto) {
      spawn(nextAuto, 0.38f);
      nextAuto += 2.4;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float s = std::min(f.width, f.height);
    // Nubes de la más antigua a la más reciente: la nueva queda delante.
    std::array<int, kBursts> order;
    for (int i = 0; i < kBursts; i++) order[i] = i;
    std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return bursts[a].born < bursts[b].born; });
    std::vector<float> u;
    u.reserve(52);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, 0.0f});
    for (int k = 0; k < kBursts; k++) {
      const Burst& b = bursts[order[k]];
      float age, radius, fade, x, y;
      state(b, age, radius, fade, x, y);
      if (b.born < -50) fade = 0;
      u.insert(u.end(), {x, y, radius, std::max(0.0f, fade) * amp});
      u.insert(u.end(), {age, b.seed, b.hue, 0.0f});
    }
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("powder", {0, 0, f.width, f.height}, u);

    // Granos que salen disparados de cada explosión.
    for (int k = 0; k < kBursts; k++) {
      const Burst& b = bursts[order[k]];
      if (b.born < -50) continue;
      float age, radius, fade, x, y;
      state(b, age, radius, fade, x, y);
      float life = 1.0f - age / 3.5f;
      if (life <= 0) continue;
      std::vector<Vec2> grains;
      grains.reserve(90);
      for (int i = 0; i < 90; i++) {
        float a = hash(b.seed * 7.1f + float(i) * 1.37f) * 6.2831853f;
        float speed = b.size * (0.6f + 1.4f * hash(b.seed * 3.3f + float(i) * 2.11f));
        float dist = speed * (1.0f - std::exp(-age * 2.4f)) / 2.4f * 2.2f;
        float gx = b.x + std::cos(a) * dist;
        float gy = b.y + std::sin(a) * dist + 0.05f * age * age;
        grains.push_back({f.width * 0.5f + gx * s, f.height * 0.5f + gy * s});
      }
      float hue = b.hue;
      int ci = int(std::floor(hue)) % 3;
      const Color& col = f.colors[1 + ci];
      Paint dust;
      dust.blend = Blend::plus;
      dust.color = {std::min(1.0f, col.r + 0.3f), std::min(1.0f, col.g + 0.3f), std::min(1.0f, col.b + 0.3f),
                    std::clamp(life * fade * (0.5f + 0.6f * spark) * amp, 0.0f, 1.0f)};
      c.points(grains, (1.0f + 0.6f * spark * amp) * s / 400.0f, dust);
    }
  }
};
''';

const shaderSources = <String, String>{
  'powder': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello
uniform vec4 uP0;  // nubes de la más antigua a la más reciente: centro, radio, intensidad
uniform vec4 uQ0;  // edad, semilla, tono
uniform vec4 uP1;
uniform vec4 uQ1;
uniform vec4 uP2;
uniform vec4 uQ2;
uniform vec4 uP3;
uniform vec4 uQ3;
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

vec3 tone(float h) {
  float k = mod(h, 3.0);
  vec3 a = k < 1.0 ? uC1 : (k < 2.0 ? uC2 : uC3);
  vec3 b = k < 1.0 ? uC2 : (k < 2.0 ? uC3 : uC1);
  return mix(a, b, smoothstep(0.0, 1.0, fract(k)));
}

// Una nube de polvo: borde deshilachado por ruido, volutas que giran con la
// edad y un núcleo más denso y luminoso al principio de la explosión.
vec4 cloud(vec2 p, vec4 P, vec4 Q) {
  if (P.w < 0.005) return vec4(0.0);
  vec2 d = (p - P.xy) / P.z;
  float r = length(d);
  if (r > 1.5) return vec4(0.0);
  float age = Q.x;
  vec2 q = d * 2.6 + Q.y;
  vec2 drift = vec2(age * 0.2, -age * 0.15);
  float w = noise(q * 0.8 + drift);
  vec2 qq = q + vec2(w * 1.8, -age * 0.25);
  float n = noise(qq * 1.6);
  // Volutas con relieve: la diferencia entre el ruido y su deformación hace
  // de luz y sombra.
  float light = clamp(0.6 + (n - w) * 1.3, 0.0, 1.2);
  float edge = r + (n - 0.5) * 1.05;
  float dens = smoothstep(1.0, 0.3, edge) * (0.55 + 0.7 * n);
  float core = exp(-r * r * 6.0) * exp(-age * 1.5);
  float a = clamp(dens * P.w * 1.25, 0.0, 0.97);
  // El polvo conserva su color vivo al desvanecerse: se aclara, no se oscurece.
  vec3 c = tone(Q.z) * (0.7 + 0.6 * light + 0.4 * uA.y) * (0.75 + 0.25 * P.w);
  c = mix(c, vec3(1.0), core * 0.5 + 0.12 * light * n);
  return vec4(c, a);
}

vec3 over(vec3 col, vec4 layer) {
  return mix(col, layer.rgb, layer.a);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  vec3 col = uC0;
  col = over(col, cloud(p, uP0, uQ0));
  col = over(col, cloud(p, uP1, uQ1));
  col = over(col, cloud(p, uP2, uQ2));
  col = over(col, cloud(p, uP3, uQ3));
  col += vec3(1.0) * uB.z * 0.04;
  col *= 1.0 - 0.35 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  // Compresión suave que conserva el tono vivo del polvo.
  float peak = max(col.r, max(col.g, col.b));
  if (peak > 0.8) {
    float e = (peak - 0.8) / 0.2;
    col *= (0.8 + 0.2 * e / (1.0 + e)) / peak;
  }
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
