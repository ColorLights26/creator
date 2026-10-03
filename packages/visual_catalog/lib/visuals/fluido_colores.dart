// Fluido de Colores — simulación de fluido con tinta de colores.
// Una rejilla resuelve el fluido de verdad (advección, confinamiento de
// vorticidad y proyección de presión) y miles de partículas de tinta viajan
// con él: los chorros se enroscan en remolinos y los colores se mezclan. Cada
// golpe lanza un chorro nuevo de otro color, el drop lanza tres a la vez, la
// energía aviva los remolinos y los agudos encienden destellos en la tinta.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int NX = 36, NY = 64;
  // El fluido avanza en pasos fijos de 1/60 s contados con el tiempo absoluto:
  // es idéntico a 30 y a 60 FPS y la tinta se dibuja interpolada.
  static constexpr double kHz = 60.0;
  static constexpr float kStep = float(1.0 / kHz);
  struct Dye { float x, y, px, py; int color; };
  struct Splat { float x, y, dx, dy, radius; int color; };
  std::vector<float> u, v, u0, v0, pr, dv, cu;
  std::vector<Dye> dye;
  std::vector<Splat> pending;
  int64_t steps = -1, stepCount = 0, nextAuto = 20;
  float frac = 0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  int turn = 0;
  double sinceDrop = 100;
  Random rng{43};

  static int I(int i, int j) { return i + (NX + 2) * j; }

  static float follow(float val, float target, float up, float down, float dt) {
    return val + (target - val) * (1.0f - std::exp(-(target > val ? up : down) * dt));
  }

  // Interpolación bilineal en coordenadas de celda (centros en 1..N).
  float sample(const std::vector<float>& f, float x, float y) const {
    x = std::clamp(x, 0.5f, float(NX) + 0.5f);
    y = std::clamp(y, 0.5f, float(NY) + 0.5f);
    int i0 = std::min(int(x), NX), j0 = std::min(int(y), NY);
    float sx = x - float(i0), sy = y - float(j0);
    float a = f[I(i0, j0)], b = f[I(i0 + 1, j0)], c = f[I(i0, j0 + 1)], d = f[I(i0 + 1, j0 + 1)];
    return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy;
  }

  // Paredes: la velocidad normal se anula reflejándola.
  static void bound(std::vector<float>& f, int kind) {
    for (int j = 1; j <= NY; j++) {
      f[I(0, j)] = kind == 1 ? -f[I(1, j)] : f[I(1, j)];
      f[I(NX + 1, j)] = kind == 1 ? -f[I(NX, j)] : f[I(NX, j)];
    }
    for (int i = 1; i <= NX; i++) {
      f[I(i, 0)] = kind == 2 ? -f[I(i, 1)] : f[I(i, 1)];
      f[I(i, NY + 1)] = kind == 2 ? -f[I(i, NY)] : f[I(i, NY)];
    }
    f[I(0, 0)] = 0.5f * (f[I(1, 0)] + f[I(0, 1)]);
    f[I(NX + 1, 0)] = 0.5f * (f[I(NX, 0)] + f[I(NX + 1, 1)]);
    f[I(0, NY + 1)] = 0.5f * (f[I(1, NY + 1)] + f[I(0, NY)]);
    f[I(NX + 1, NY + 1)] = 0.5f * (f[I(NX, NY + 1)] + f[I(NX + 1, NY)]);
  }

  void advect(std::vector<float>& d, const std::vector<float>& d0, int kind) {
    for (int j = 1; j <= NY; j++) {
      for (int i = 1; i <= NX; i++) {
        float x = float(i) - kStep * u0[I(i, j)];
        float y = float(j) - kStep * v0[I(i, j)];
        d[I(i, j)] = sample(d0, x, y);
      }
    }
    bound(d, kind);
  }

  void project() {
    for (int j = 1; j <= NY; j++) {
      for (int i = 1; i <= NX; i++) {
        dv[I(i, j)] = -0.5f * (u[I(i + 1, j)] - u[I(i - 1, j)] + v[I(i, j + 1)] - v[I(i, j - 1)]);
        pr[I(i, j)] = 0;
      }
    }
    bound(dv, 0);
    bound(pr, 0);
    for (int k = 0; k < 18; k++) {
      for (int j = 1; j <= NY; j++) {
        for (int i = 1; i <= NX; i++) {
          pr[I(i, j)] = (dv[I(i, j)] + pr[I(i - 1, j)] + pr[I(i + 1, j)] + pr[I(i, j - 1)] + pr[I(i, j + 1)]) * 0.25f;
        }
      }
      bound(pr, 0);
    }
    for (int j = 1; j <= NY; j++) {
      for (int i = 1; i <= NX; i++) {
        u[I(i, j)] -= 0.5f * (pr[I(i + 1, j)] - pr[I(i - 1, j)]);
        v[I(i, j)] -= 0.5f * (pr[I(i, j + 1)] - pr[I(i, j - 1)]);
      }
    }
    bound(u, 1);
    bound(v, 2);
  }

  // Confinamiento de vorticidad: devuelve energía a los remolinos pequeños.
  void vorticity(float eps) {
    for (int j = 1; j <= NY; j++)
      for (int i = 1; i <= NX; i++)
        cu[I(i, j)] = 0.5f * ((v[I(i + 1, j)] - v[I(i - 1, j)]) - (u[I(i, j + 1)] - u[I(i, j - 1)]));
    bound(cu, 0);
    for (int j = 2; j < NY; j++) {
      for (int i = 2; i < NX; i++) {
        float nx = 0.5f * (std::fabs(cu[I(i + 1, j)]) - std::fabs(cu[I(i - 1, j)]));
        float ny = 0.5f * (std::fabs(cu[I(i, j + 1)]) - std::fabs(cu[I(i, j - 1)]));
        float len = std::sqrt(nx * nx + ny * ny) + 1e-5f;
        nx /= len;
        ny /= len;
        float w = cu[I(i, j)];
        u[I(i, j)] += kStep * eps * ny * w;
        v[I(i, j)] -= kStep * eps * nx * w;
      }
    }
  }

  void queueSplat(float power, int color) {
    Splat s;
    s.x = 4.0f + rng.unit() * float(NX - 8);
    s.y = 6.0f + rng.unit() * float(NY - 12);
    float a = rng.unit() * 6.2831853f;
    float speed = (40.0f + 40.0f * rng.unit()) * power;
    s.dx = std::cos(a) * speed;
    s.dy = std::sin(a) * speed;
    s.radius = 4.0f + 3.0f * power;
    s.color = color;
    pending.push_back(s);
  }

  void step() {
    for (const Splat& s : pending) {
      int r = int(std::ceil(s.radius * 2.0f));
      int ci = int(s.x), cj = int(s.y);
      for (int j = std::max(1, cj - r); j <= std::min(NY, cj + r); j++) {
        for (int i = std::max(1, ci - r); i <= std::min(NX, ci + r); i++) {
          float dx = float(i) - s.x, dy = float(j) - s.y;
          float g = std::exp(-(dx * dx + dy * dy) / (s.radius * s.radius));
          u[I(i, j)] += s.dx * g;
          v[I(i, j)] += s.dy * g;
        }
      }
      // La tinta cercana toma el color del chorro.
      float r2 = s.radius * s.radius * 2.2f;
      for (Dye& d : dye) {
        float dx = d.x - s.x, dy = d.y - s.y;
        if (dx * dx + dy * dy < r2) d.color = s.color;
      }
    }
    pending.clear();
    vorticity(3.5f + 7.0f * energy);
    u0 = u;
    v0 = v;
    advect(u, u0, 1);
    advect(v, v0, 2);
    project();
    for (size_t k = 0; k < u.size(); k++) {
      u[k] = std::clamp(u[k] * 0.992f, -120.0f, 120.0f);
      v[k] = std::clamp(v[k] * 0.992f, -120.0f, 120.0f);
    }
    for (Dye& d : dye) {
      d.px = d.x;
      d.py = d.y;
      float vx = sample(u, d.x, d.y), vy = sample(v, d.x, d.y);
      d.x = std::clamp(d.x + vx * kStep, 0.8f, float(NX) + 0.2f);
      d.y = std::clamp(d.y + vy * kStep, 0.8f, float(NY) + 0.2f);
    }
    stepCount++;
    // Sin golpes: un chorro cada segundo y medio, en pasos fijos.
    if (stepCount >= nextAuto) {
      queueSplat(0.75f, turn++ % 3);
      nextAuto = stepCount + 90;
    }
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    size_t n = size_t((NX + 2) * (NY + 2));
    u.assign(n, 0.0f);
    v.assign(n, 0.0f);
    u0.assign(n, 0.0f);
    v0.assign(n, 0.0f);
    pr.assign(n, 0.0f);
    dv.assign(n, 0.0f);
    cu.assign(n, 0.0f);
    dye.clear();
    pending.clear();
    steps = -1;
    stepCount = 0;
    nextAuto = 20;
    frac = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    turn = 0;
    sinceDrop = 100;
    for (int k = 0; k < 3; k++) queueSplat(0.9f, turn++ % 3);
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (dye.empty()) {
      int count = int(6000.0f + 3000.0f * std::clamp(f.detail, 0.25f, 2.0f));
      dye.resize(count);
      for (auto& d : dye) {
        d.x = d.px = 1.0f + rng.unit() * float(NX - 1);
        d.y = d.py = 1.0f + rng.unit() * float(NY - 1);
        d.color = std::min(2, int(d.y / float(NY) * 3.0f));
      }
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
    sinceDrop += f.delta;
    if (hit > kick + 0.2f) {
      if (hit > 0.7f && drive > 0.4f && sinceDrop > 6.0) {
        for (int k = 0; k < 3; k++) queueSplat(1.2f, turn++ % 3);
        sinceDrop = 0;
      } else {
        queueSplat(0.6f + 0.6f * hit, turn++ % 3);
      }
      nextAuto = stepCount + 110;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

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
    std::vector<float> uni;
    uni.reserve(20);
    uni.insert(uni.end(), {bass * amp, kick * amp, energy, f.glow});
    uni.insert(uni.end(), {spark * amp, flash * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) uni.insert(uni.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("fluid_dark", {0, 0, f.width, f.height}, uni);
    if (dye.empty()) return;
    float cellW = f.width / float(NX), cellH = f.height / float(NY);
    std::array<std::vector<Vec2>, 3> groups;
    for (auto& g : groups) g.reserve(dye.size() / 3 + 1);
    for (const Dye& d : dye) {
      float x = d.px + (d.x - d.px) * frac, y = d.py + (d.y - d.py) * frac;
      groups[d.color].push_back({(x - 0.5f) * cellW, (y - 0.5f) * cellH});
    }
    float s = std::min(f.width, f.height);
    float px = s / 400.0f;
    float gain = std::clamp((0.85f + 0.4f * bass + 0.4f * kick) * amp, 0.0f, 1.5f);
    for (int g = 0; g < 3; g++) {
      const Color& col = f.colors[1 + g];
      // Tinta: discos grandes y muy suaves que se funden entre sí; la mezcla
      // de partículas de distintos colores se ve como tinta mezclada.
      Paint wide;
      wide.blend = Blend::plus;
      wide.color = {col.r, col.g, col.b, std::clamp(0.016f * gain * f.glow, 0.0f, 1.0f)};
      c.points(groups[g], 17.0f * px, wide);
      Paint soft;
      soft.blend = Blend::plus;
      soft.color = {col.r, col.g, col.b, std::clamp(0.026f * gain, 0.0f, 1.0f)};
      c.points(groups[g], 8.0f * px, soft);
    }
  }
};
''';

const shaderSources = <String, String>{
  'fluid_dark': r"""
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
  vec3 col = uC0 + mix(uC1, uC2, 0.5) * uB.y * 0.03;
  col *= 1.0 - 0.4 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
