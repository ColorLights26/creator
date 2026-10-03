// Lluvia Cinética — escultura de gotas de cobre suspendidas en el aire.
// Una cuadrícula de gotas metálicas cuelga en 3D y cada gota sube o baja para
// dibujar entre todas una superficie: olas, ondas concéntricas, sillas de
// montar, cúpulas y espirales que se transforman unas en otras. Cada golpe
// lanza una onda desde el centro; cada ocho golpes la escultura cambia de
// forma, los graves amplían el movimiento y los agudos hacen brillar el cobre.
const nativeSource = r'''
class Visual final : public Scene {
  struct Drop { float x, y, depth, radius, light; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Fases en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, yaw = 0, sinceShape = 0;
  int shapeA = 0, shapeB = 0, beats = 0, step = 0;
  float morph = 1, ringR = 3.0f, ringAmp = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Formas de la escultura sobre la cuadrícula (x, z en -1..1).
  static float shape(int id, float x, float z, float t) {
    float r = std::sqrt(x * x + z * z);
    switch (id) {
      case 0: return 0.28f * std::sin(x * 2.4f + t * 1.1f) + 0.12f * std::sin(z * 3.1f - t * 0.7f);
      case 1: return 0.30f * std::sin(r * 6.0f - t * 2.0f) * std::exp(-r * 0.5f);
      case 2: return 0.42f * (x * x - z * z) * std::cos(t * 0.5f);
      case 3: return 0.28f * std::sin(x * 3.0f + t) * std::cos(z * 3.0f - t * 0.8f);
      case 4: return 0.55f * std::exp(-r * r * 2.2f) * (0.8f + 0.2f * std::sin(t * 1.5f)) - 0.2f;
      default: return 0.25f * std::sin(std::atan2(z, x) * 2.0f + r * 5.0f - t * 1.8f);
    }
  }

  void next() {
    step++;
    shapeA = shapeB;
    shapeB = step % 6;
    morph = 0;
    sinceShape = 0;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = rng.unit() * 20.0;
    yaw = 0.5 + rng.unit() * 0.5;
    sinceShape = 0;
    shapeA = shapeB = 0;
    beats = step = 0;
    morph = 1;
    ringR = 3.0f;
    ringAmp = 0;
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
      ringR = 0.0f;
      ringAmp = hit;
      if (beats % 8 == 0) next();
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    morph = std::min(1.0f, morph + dt * 0.8f);
    sinceShape += f.delta;
    // En silencio la escultura cambia de forma cada nueve segundos.
    if (!m.active && sinceShape > 9.0) next();
    ringR += dt * (1.2f + 0.6f * drive);
    ringAmp *= std::exp(-dt * 1.6f);
    clock += f.delta * f.speed * (0.7 + 0.9 * drive);
    yaw += f.delta * f.speed * (0.06 + 0.12 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float s = std::min(f.width, f.height);
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(clock, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("rain_room", {0, 0, f.width, f.height}, u);

    int n = int(14.0f + 4.0f * std::clamp(f.detail, 0.25f, 2.0f));
    float t = float(std::fmod(clock, 6283.0));
    float e = morph * morph * (3.0f - 2.0f * morph);
    float cy = float(std::cos(yaw)), sy = float(std::sin(yaw));
    const float pitch = 0.62f;
    float cp = std::cos(pitch), sp = std::sin(pitch);
    float scale = s * 0.95f, focal = 2.8f;
    float cx = f.width * 0.5f, cyScreen = f.height * 0.5f;
    float heightGain = (0.9f + 1.0f * bass) * amp;
    std::vector<Drop> drops;
    drops.reserve(size_t(n * n));
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        float x = -1.0f + 2.0f * float(i) / float(n - 1);
        float z = -1.0f + 2.0f * float(j) / float(n - 1);
        float r = std::sqrt(x * x + z * z);
        float h = shape(shapeA, x, z, t) + (shape(shapeB, x, z, t) - shape(shapeA, x, z, t)) * e;
        h *= heightGain;
        h += 0.55f * ringAmp * amp * std::exp(-(r - ringR) * (r - ringR) * 10.0f);
        // Giro alrededor del eje vertical e inclinación de la cámara.
        float rx = x * cy - z * sy, rz = x * sy + z * cy;
        float vy = h * cp - rz * sp;
        float vz = h * sp + rz * cp;
        float depth = vz + focal;
        float k = focal / depth;
        Drop d;
        d.x = cx + rx * scale * k;
        d.y = cyScreen - vy * scale * k;
        d.depth = depth;
        d.radius = s * 0.021f * k;
        d.light = 0.75f + 0.9f * std::clamp(h + 0.3f, 0.0f, 1.0f);
        drops.push_back(d);
      }
    }
    // Pintor: primero las gotas lejanas.
    std::vector<int> order(drops.size());
    for (size_t i = 0; i < order.size(); i++) order[i] = int(i);
    std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return drops[a].depth > drops[b].depth; });

    const Color& copper = f.colors[1];
    const Color& champagne = f.colors[2];
    const Color& shadow = f.colors[3];
    float shine = 1.15f + 0.7f * kick * amp + 0.3f * spark * amp + 0.4f * flash * amp;
    // Halo cálido detrás de las gotas.
    std::vector<Vec2> centers;
    centers.reserve(drops.size());
    for (const auto& d : drops) centers.push_back({d.x, d.y});
    Paint halo;
    halo.blend = Blend::plus;
    halo.color = {copper.r, copper.g, copper.b, std::clamp(0.05f * f.glow * shine, 0.0f, 1.0f)};
    c.points(centers, s * 0.04f, halo);
    for (int idx : order) {
      const Drop& d = drops[idx];
      float L = std::min(d.light * shine, 2.0f);
      auto mixc = [](const Color& a, const Color& b, float t, float g) {
        return Color{std::min(1.0f, (a.r + (b.r - a.r) * t) * g), std::min(1.0f, (a.g + (b.g - a.g) * t) * g),
                     std::min(1.0f, (a.b + (b.b - a.b) * t) * g), 1.0f};
      };
      Color hi = mixc(champagne, Color{1, 1, 1, 1}, 0.25f, std::min(L, 1.2f));
      Color mid = mixc(copper, champagne, 0.15f, L * 0.8f);
      Color dark = mixc(shadow, copper, 0.2f, 0.6f);
      Vec2 hot{d.x - d.radius * 0.35f, d.y - d.radius * 0.4f};
      Paint drop = Paint::radial(hot, d.radius * 1.35f, {hi, mid, dark}, {0.0f, 0.45f, 1.0f});
      c.circle({d.x, d.y}, d.radius, drop);
    }
  }
};
''';

const shaderSources = <String, String>{
  'rain_room': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // reloj, graves, golpe, energía
uniform vec4 uB;   // glow, agudos, destello
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

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  // Sala oscura con un foco cálido desde arriba y su reflejo en el suelo.
  vec3 col = uC0;
  float spot = exp(-(p.x * p.x * 2.5 + (p.y + 0.9) * (p.y + 0.9) * 1.2));
  col += uC1 * spot * (0.10 + 0.08 * uA.y + 0.12 * uA.z) * uB.x;
  float floorGlow = exp(-(p.x * p.x * 1.5 + (p.y - 0.75) * (p.y - 0.75) * 6.0));
  col += uC2 * floorGlow * (0.04 + 0.05 * uA.y) * uB.x;
  col += uC2 * uB.z * 0.05;
  col *= 1.0 - 0.45 * smoothstep(0.5, 1.3, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
