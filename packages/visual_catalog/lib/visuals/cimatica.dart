// Cimática — arena luminosa sobre una placa de Chladni que vibra con la música.
// Miles de granos saltan donde la placa vibra y se acumulan en las líneas
// nodales, donde está quieta, formando figuras geométricas perfectas. Cada
// cuatro golpes la placa cambia de modo y la arena migra a una figura nueva;
// cada golpe hace saltar los granos, los graves agitan la placa y los agudos
// encienden destellos en la arena.
const nativeSource = r'''
class Visual final : public Scene {
  // La arena avanza en pasos fijos de 1/60 s contados con el tiempo absoluto:
  // es idéntica a 30 y a 60 FPS y se dibuja interpolada.
  static constexpr double kHz = 60.0;
  static constexpr float kStep = float(1.0 / kHz);
  static constexpr int kLut = 1024;
  struct Grain { float x, y, px, py; };
  struct Mode { float n, m, s; };
  std::vector<Grain> grains;
  std::array<float, kLut + 1> table{};
  Mode modeA{3, 5, -1}, modeB{3, 5, -1};
  float morph = 1;
  int modeIndex = 0, beats = 0, stepsSinceMode = 0;
  int64_t steps = -1;
  float frac = 0, pendingJolt = 0, pendingMode = 0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, t = 0;
  Random rng{31};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // cos(pi * x) desde una tabla: miles de granos por paso sin coste de trigonometría.
  float cospi(float x) const {
    float u = x * 0.5f;
    u -= std::floor(u);
    float i = u * kLut;
    int k = std::min(int(i), kLut - 1);
    float a = table[k];
    return a + (table[k + 1] - a) * (i - float(k));
  }
  float sinpi(float x) const { return cospi(x - 0.5f); }

  // Figura de Chladni de una placa rectangular y su gradiente.
  static float plate(const Mode& md, float x, float y, float& gx, float& gy, const Visual& v) {
    float cnx = v.cospi(md.n * x), cmy = v.cospi(md.m * y), cmx = v.cospi(md.m * x), cny = v.cospi(md.n * y);
    float snx = v.sinpi(md.n * x), smy = v.sinpi(md.m * y), smx = v.sinpi(md.m * x), sny = v.sinpi(md.n * y);
    const float p = 3.14159265f;
    gx = -p * (md.n * snx * cmy + md.s * md.m * smx * cny);
    gy = -p * (md.m * cnx * smy + md.s * md.n * cmx * sny);
    return cnx * cmy + md.s * cmx * cny;
  }

  void advanceMode() {
    // Figuras elegidas por su simetría: pares (n, m) y signo de la mezcla.
    static const Mode modes[10] = {{3, 5, -1}, {1, 5, 1}, {3, 7, -1}, {2, 6, 1}, {5, 7, -1},
                                   {1, 7, -1}, {4, 6, 1}, {3, 9, 1}, {2, 4, -1}, {5, 9, -1}};
    modeIndex = (modeIndex + 1) % 10;
    modeA = modeB;
    modeB = modes[modeIndex];
    morph = 0;
    stepsSinceMode = 0;
  }

  void step() {
    float jolt = pendingJolt;
    pendingJolt = 0;
    if (pendingMode > 0 || stepsSinceMode > int(kHz * 9.0)) {
      advanceMode();
      jolt = std::max(jolt, 0.8f);
      pendingMode = 0;
    }
    stepsSinceMode++;
    morph = std::min(1.0f, morph + kStep * 1.4f);
    t += kStep;
    float w = morph * morph * (3.0f - 2.0f * morph);
    float agitation = 0.0010f + 0.0012f * bass + 0.0006f * drive;
    float pull = 0.05f;  // fracción de la distancia a la línea por paso
    for (auto& g : grains) {
      g.px = g.x;
      g.py = g.y;
      float bx, by;
      float fv = plate(modeB, g.x, g.y, bx, by, *this);
      float gx = bx, gy = by;
      // La figura anterior sólo se calcula durante la transición.
      if (w < 1.0f) {
        float ax, ay;
        float fa = plate(modeA, g.x, g.y, ax, ay, *this);
        fv = fa + (fv - fa) * w;
        gx = ax + (bx - ax) * w;
        gy = ay + (by - ay) * w;
      }
      float gl = std::sqrt(gx * gx + gy * gy) + 1e-3f;
      // La arena baja por la pendiente de |f| hacia las líneas quietas y salta
      // más donde la placa vibra con fuerza.
      float stepLen = std::min(std::fabs(fv) / gl, 0.06f);
      float dir = fv > 0 ? -1.0f : 1.0f;
      g.x += dir * gx / gl * stepLen * pull;
      g.y += dir * gy / gl * stepLen * pull;
      float shake = agitation * (0.6f + 2.5f * std::fabs(fv)) + jolt * 0.06f * (0.3f + std::fabs(fv));
      g.x += (rng.unit() - 0.5f) * shake;
      g.y += (rng.unit() - 0.5f) * shake;
      if (g.x < 0) g.x = -g.x;
      if (g.x > 1) g.x = 2.0f - g.x;
      if (g.y < 0) g.y = -g.y;
      if (g.y > 1) g.y = 2.0f - g.y;
    }
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    for (int i = 0; i <= kLut; i++) table[i] = float(std::cos(2.0 * pi * double(i) / kLut));
    grains.clear();
    modeA = modeB = Mode{3, 5, -1};
    morph = 1;
    modeIndex = beats = stepsSinceMode = 0;
    steps = -1;
    frac = pendingJolt = pendingMode = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    t = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    if (grains.empty()) {
      int count = int(5000.0f + 2500.0f * std::clamp(f.detail, 0.25f, 2.0f));
      grains.resize(count);
      for (auto& g : grains) {
        g.x = g.px = rng.unit();
        g.y = g.py = rng.unit();
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
    if (hit > kick + 0.2f) {
      beats++;
      pendingJolt = std::max(pendingJolt, hit);
      if (beats % 4 == 0) pendingMode = 1;
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
    float w = morph * morph * (3.0f - 2.0f * morph);
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {t, bass * amp, kick * amp, energy});
    u.insert(u.end(), {modeA.n, modeA.m, modeA.s, modeB.n});
    u.insert(u.end(), {modeB.m, modeB.s, w, f.glow});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("plate", {0, 0, f.width, f.height}, u);
    if (grains.empty()) return;

    float px = std::min(f.width, f.height) / 400.0f;
    std::vector<Vec2> gold, white;
    gold.reserve(grains.size());
    white.reserve(grains.size() / 3 + 1);
    for (size_t i = 0; i < grains.size(); i++) {
      const Grain& g = grains[i];
      Vec2 p{(g.px + (g.x - g.px) * frac) * f.width, (g.py + (g.y - g.py) * frac) * f.height};
      if (i % 3 == 0) white.push_back(p); else gold.push_back(p);
    }
    const Color& sand = f.colors[2];
    const Color& hot = f.colors[3];
    float gain = std::clamp((0.75f + 0.5f * bass + 0.6f * kick) * amp, 0.0f, 1.6f);
    Paint halo;
    halo.blend = Blend::plus;
    halo.color = {sand.r, sand.g, sand.b, std::clamp(0.07f * gain * f.glow, 0.0f, 1.0f)};
    c.points(gold, 4.4f * px, halo);
    Paint core;
    core.blend = Blend::plus;
    core.color = {sand.r, sand.g, sand.b, std::clamp(0.7f * gain, 0.0f, 1.0f)};
    c.points(gold, 1.3f * px, core);
    float twinkle = 0.7f + 0.3f * spark;
    Paint bright;
    bright.blend = Blend::plus;
    bright.color = {hot.r, hot.g, hot.b, std::clamp(0.75f * gain * twinkle, 0.0f, 1.0f)};
    c.points(white, (1.0f + 0.6f * spark * amp + 0.6f * kick * amp) * px, bright);
  }
};
''';

const shaderSources = <String, String>{
  'plate': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // tiempo, graves, golpe, energía
uniform vec4 uM;   // modo anterior (n, m, signo) y n del modo nuevo
uniform vec4 uN;   // m y signo del modo nuevo, transición, glow
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

float plate(vec2 uv, float n, float m, float s) {
  return cos(n * PI * uv.x) * cos(m * PI * uv.y) + s * cos(m * PI * uv.x) * cos(n * PI * uv.y);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  float scale = min(uSize.x, uSize.y);
  vec2 p = (frag - 0.5 * uSize) / scale;
  float f = mix(plate(uv, uM.x, uM.y, uM.z), plate(uv, uM.w, uN.x, uN.y), uN.z);

  // Placa metálica oscura con un brillo frío que sigue la figura: las líneas
  // quietas brillan suave y las zonas que vibran tiemblan con los graves.
  float lines = exp(-abs(f) * 9.0);
  float shimmer = abs(f) * (0.5 + 0.5 * sin(uA.x * 40.0 + f * 6.0));
  vec3 col = uC0 * (1.0 + 0.6 * smoothstep(1.2, 0.0, length(p)));
  col += uC1 * lines * (0.16 + 0.22 * uA.y + 0.35 * uA.z) * uN.w;
  // Resplandor dorado de la arena sobre las líneas.
  col += uC2 * exp(-abs(f) * 40.0) * (0.05 + 0.08 * uA.y + 0.18 * uA.z) * uN.w;
  col += uC1 * shimmer * (0.02 + 0.06 * uA.y) * uN.w;
  // Onda del golpe que recorre la placa.
  col += uC1 * uA.z * 0.08 * smoothstep(0.9, 0.0, length(p));

  col *= 1.0 - 0.45 * smoothstep(0.5, 1.3, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
