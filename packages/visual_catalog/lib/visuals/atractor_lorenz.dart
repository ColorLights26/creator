// Atractor de Lorenz — partículas que recorren la mariposa del caos en 3D.
// Cada partícula sigue las ecuaciones de Lorenz; aunque empiezan juntas, el
// caos las reparte por las dos alas de la mariposa y dejan estelas de luz. La
// figura gira despacio en 3D. Cada golpe empuja las partículas fuera de la
// forma y el propio atractor las vuelve a atrapar; los graves cambian la
// forma de las alas y la energía acelera el recorrido.
const nativeSource = r'''
class Visual final : public Scene {
  // Integración en pasos fijos de 1/60 s contados con el tiempo absoluto:
  // es idéntica a 30 y a 60 FPS y se dibuja interpolada.
  static constexpr double kHz = 60.0;
  static constexpr int kTrail = 14;
  struct P { float x, y, z; };
  std::vector<P> now, prev;
  std::vector<P> trail;  // anillo: partícula * kTrail
  int head = 0;
  int64_t steps = -1;
  float frac = 0, pendingKick = 0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  double yaw = 0;
  Random rng{67};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void integrate(P& p, float rho, float h) const {
    const float sigma = 10.0f, beta = 8.0f / 3.0f;
    for (int k = 0; k < 3; k++) {
      float dx = sigma * (p.y - p.x);
      float dy = p.x * (rho - p.z) - p.y;
      float dz = p.x * p.y - beta * p.z;
      p.x += dx * h;
      p.y += dy * h;
      p.z += dz * h;
    }
  }

  void step() {
    float rho = 28.0f + 7.0f * bass;
    float h = 0.0035f * (1.0f + 1.2f * drive);
    float push = pendingKick;
    pendingKick = 0;
    for (size_t i = 0; i < now.size(); i++) {
      prev[i] = now[i];
      P& p = now[i];
      if (push > 0) {
        // Golpe: la partícula sale despedida y el atractor la vuelve a atrapar.
        p.x += (rng.unit() - 0.5f) * 6.0f * push;
        p.y += (rng.unit() - 0.5f) * 6.0f * push;
        p.z += (rng.unit() - 0.5f) * 4.0f * push;
      }
      integrate(p, rho, h);
      trail[i * kTrail + size_t(head)] = p;
    }
    head = (head + 1) % kTrail;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    now.clear();
    prev.clear();
    trail.clear();
    head = 0;
    steps = -1;
    frac = pendingKick = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    yaw = rng.unit() * 6.2831853;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (now.empty()) {
      int count = int(600.0f + 200.0f * std::clamp(f.detail, 0.25f, 2.0f));
      now.resize(size_t(count));
      for (auto& p : now) p = {1.0f + rng.unit() * 2.0f, 1.0f + rng.unit() * 2.0f, 20.0f + rng.unit() * 2.0f};
      // El caos reparte las partículas por la mariposa antes de empezar.
      for (auto& p : now)
        for (int k = 0; k < 400; k++) integrate(p, 28.0f, 0.004f);
      prev = now;
      trail.assign(now.size() * kTrail, P{0, 0, 0});
      for (size_t i = 0; i < now.size(); i++)
        for (int k = 0; k < kTrail; k++) trail[i * kTrail + size_t(k)] = now[i];
    }
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
    if (hit > kick + 0.2f) pendingKick = std::max(pendingKick, hit);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    yaw += f.delta * f.speed * (0.12 + 0.25 * drive);

    int64_t target = int64_t(std::floor(f.time * kHz + 1e-6));
    if (steps < 0 || target < steps || target - steps > 15) steps = target - 1;
    while (steps < target) {
      step();
      steps++;
    }
    frac = std::clamp(float(f.time * kHz - double(steps)), 0.0f, 1.0f);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float w = f.width, h = f.height, s = std::min(w, h);
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {bass * amp, kick * amp, energy, f.glow});
    u.insert(u.end(), {spark * amp, flash * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("chaos_space", {0, 0, w, h}, u);
    if (now.empty()) return;

    float cy = float(std::cos(yaw)), sy = float(std::sin(yaw));
    const float tilt = 0.35f;
    float ct = std::cos(tilt), st = std::sin(tilt);
    float scale = s * 0.026f;
    float ox = w * 0.5f, oy = h * 0.5f;
    auto project = [&](const P& p) -> Vec2 {
      // Centrado: las alas giran alrededor del eje vertical de la mariposa.
      float x = p.x, y = p.y, z = p.z - 25.0f;
      float rx = x * cy + y * sy;
      float ry = -x * sy + y * cy;
      float vy = z * ct - ry * st;
      float vz = z * st + ry * ct;
      float persp = 80.0f / (80.0f - vz);
      return {ox + rx * scale * persp, oy - vy * scale * persp};
    };
    std::array<std::vector<Vec2>, 2> heads;
    std::array<Path, 2> tails;
    for (int g = 0; g < 2; g++) heads[size_t(g)].reserve(now.size());
    for (size_t i = 0; i < now.size(); i++) {
      P p{prev[i].x + (now[i].x - prev[i].x) * frac, prev[i].y + (now[i].y - prev[i].y) * frac,
          prev[i].z + (now[i].z - prev[i].z) * frac};
      int wing = p.x > 0 ? 0 : 1;
      Vec2 hp = project(p);
      heads[size_t(wing)].push_back(hp);
      Path& path = tails[size_t(wing)];
      for (int k = 0; k < kTrail; k++) {
        Vec2 q = project(trail[i * kTrail + size_t((head + k) % kTrail)]);
        if (k == 0) path.moveTo(q.x, q.y); else path.lineTo(q.x, q.y);
      }
      path.lineTo(hp.x, hp.y);
    }
    float px = s / 400.0f;
    float gain = std::clamp((0.85f + 0.5f * bass + 0.6f * kick) * amp, 0.0f, 1.6f);
    for (int g = 0; g < 2; g++) {
      const Color& col = f.colors[1 + g];
      Paint tailGlow;
      tailGlow.blend = Blend::plus;
      tailGlow.strokeWidth = 4.0f * px;
      tailGlow.strokeCap = 1;
      tailGlow.strokeJoin = 1;
      tailGlow.color = {col.r, col.g, col.b, std::clamp(0.05f * gain * f.glow, 0.0f, 1.0f)};
      c.path(tails[size_t(g)], tailGlow);
      Paint tail = tailGlow;
      tail.strokeWidth = 1.1f * px;
      tail.color = {col.r, col.g, col.b, std::clamp(0.4f * gain, 0.0f, 1.0f)};
      c.path(tails[size_t(g)], tail);
      Paint halo;
      halo.blend = Blend::plus;
      halo.color = {col.r, col.g, col.b, std::clamp(0.08f * gain * f.glow, 0.0f, 1.0f)};
      c.points(heads[size_t(g)], 4.5f * px, halo);
      Paint core;
      core.blend = Blend::plus;
      const Color& white = f.colors[3];
      core.color = {col.r + (white.r - col.r) * 0.5f, col.g + (white.g - col.g) * 0.5f, col.b + (white.b - col.b) * 0.5f,
                    std::clamp(0.9f * gain, 0.0f, 1.0f)};
      c.points(heads[size_t(g)], (1.4f + 0.5f * spark * amp) * px, core);
    }
  }
};
''';

const shaderSources = <String, String>{
  'chaos_space': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // graves, golpe, energía, glow
uniform vec4 uB;   // agudos, destello
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
  // Espacio azul profundo con resplandor detrás de la mariposa.
  vec3 col = uC0 + uC1 * exp(-dot(p, p) * 2.2) * (0.06 + 0.05 * uA.x + 0.12 * uA.y) * uA.w;
  col += uC2 * uB.y * 0.04;
  col *= 1.0 - 0.45 * smoothstep(0.5, 1.4, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
