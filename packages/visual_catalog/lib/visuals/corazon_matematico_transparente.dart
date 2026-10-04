// Corazón Matemático Transparente — las tablas de multiplicar dibujadas con líneas de luz.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Hay 240 puntos en un círculo y cada punto k se une con el punto k × m: con
// m = 2 aparece un corazón (cardioide), con 3 una nefroide y con números más
// altos flores y estrellas. El multiplicador avanza sin parar y las figuras se
// transforman unas en otras; cada golpe salta a la siguiente tabla con un
// muelle, la energía acelera el cambio y los graves encienden las líneas.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kPoints = 240;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Multiplicador en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double base = 0, spin = 0;
  float jump = 0, jumpVel = 0, jumpTarget = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    base = rng.unit() * 3.0;
    spin = rng.unit() * 6.2831853;
    jump = jumpVel = jumpTarget = 0;
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
    // Cada golpe salta a la siguiente tabla entera, donde la figura es nítida.
    if (hit > kick + 0.2f) jumpTarget = std::floor(float(std::fmod(base, 24.0)) + jumpTarget) + 1.0f - float(std::fmod(base, 24.0));
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    // Salto a la siguiente tabla con un muelle amortiguado.
    jumpVel += ((jumpTarget - jump) * 40.0f - jumpVel * 11.0f) * dt;
    jump += jumpVel * dt;
    base += f.delta * f.speed * (0.04 + 0.08 * drive);
    spin += f.delta * f.speed * (0.05 + 0.12 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float w = f.width, h = f.height, s = std::min(w, h);
    float cx = w * 0.5f, cy = h * 0.5f;
    float R = s * 0.43f * (1.0f + 0.03f * bass * amp + 0.02f * kick * amp);
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {bass * amp, kick * amp, energy, f.glow});
    u.insert(u.end(), {spark * amp, flash * amp, R / s, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("heart_ring", {0, 0, w, h}, u);

    // Multiplicador entre 2 y 14 en ida y vuelta, sin saltos: las tablas
    // bajas dan las figuras más reconocibles (corazón, nefroide, flores).
    double raw = std::fmod(base + double(jump), 24.0);
    double mult = 2.0 + (raw < 12.0 ? raw : 24.0 - raw);
    float rot = float(std::fmod(spin, 6.2831853));
    std::array<Vec2, kPoints> pts;
    for (int k = 0; k < kPoints; k++) {
      float a = 6.2831853f * float(k) / float(kPoints) - 1.5707963f + rot;
      pts[size_t(k)] = {cx + std::cos(a) * R, cy + std::sin(a) * R};
    }
    // Seis tramos de color alrededor del círculo: rojo, magenta, violeta y vuelta.
    const int kGroups = 6;
    std::array<Path, kGroups> paths;
    for (int k = 0; k < kPoints; k++) {
      double target = std::fmod(double(k) * mult, double(kPoints));
      float a = 6.2831853f * float(target / double(kPoints)) - 1.5707963f + rot;
      Vec2 q{cx + std::cos(a) * R, cy + std::sin(a) * R};
      Path& p = paths[size_t(k * kGroups / kPoints)];
      p.moveTo(pts[size_t(k)].x, pts[size_t(k)].y);
      p.lineTo(q.x, q.y);
    }
    static const float mixes[kGroups][3] = {{1, 0, 0}, {0.5f, 0.5f, 0}, {0, 1, 0}, {0, 0.5f, 0.5f}, {0, 0, 1}, {0.5f, 0, 0.5f}};
    float px = s / 400.0f;
    float gain = std::clamp((0.8f + 0.6f * bass + 0.6f * kick + 0.3f * flash) * amp, 0.0f, 1.8f);
    for (int g = 0; g < kGroups; g++) {
      const float* mx = mixes[g];
      Color col{f.colors[1].r * mx[0] + f.colors[2].r * mx[1] + f.colors[3].r * mx[2],
                f.colors[1].g * mx[0] + f.colors[2].g * mx[1] + f.colors[3].g * mx[2],
                f.colors[1].b * mx[0] + f.colors[2].b * mx[1] + f.colors[3].b * mx[2], 1.0f};
      Paint glow;
      glow.blend = Blend::plus;
      glow.strokeWidth = 5.0f * px;
      glow.strokeCap = 1;
      glow.color = {col.r, col.g, col.b, std::clamp(0.05f * gain * f.glow, 0.0f, 1.0f)};
      c.path(paths[size_t(g)], glow);
      Paint core = glow;
      core.strokeWidth = (1.0f + 0.5f * bass * amp) * px;
      core.color = {std::min(1.0f, col.r + 0.15f), std::min(1.0f, col.g + 0.15f), std::min(1.0f, col.b + 0.15f),
                    std::clamp(0.42f * gain, 0.0f, 1.0f)};
      c.path(paths[size_t(g)], core);
    }
    // Puntos del círculo que titilan con los agudos.
    std::vector<Vec2> dots(pts.begin(), pts.end());
    Paint dot;
    dot.blend = Blend::plus;
    dot.color = {1.0f, 0.85f, 0.95f, std::clamp((0.35f + 0.6f * spark) * amp, 0.0f, 1.0f)};
    c.points(dots, (1.1f + 0.8f * spark * amp) * px, dot);
  }
};
''';

const shaderSources = <String, String>{
  'heart_ring': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // graves, golpe, energía, glow
uniform vec4 uB;   // agudos, destello, radio del círculo
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
  float r = length(p);
  // Resplandor dentro del círculo y aro de luz en el borde.
  vec3 col = uC0 + mix(uC1, uC3, 0.5) * smoothstep(uB.z, 0.0, r) * (0.04 + 0.05 * uA.x + 0.1 * uA.y) * uA.w;
  col += uC2 * exp(-(r - uB.z) * (r - uB.z) * 4000.0) * (0.25 + 0.4 * uA.y) * uA.w;
  col *= 1.0 - 0.4 * smoothstep(0.5, 1.4, length(p * vec2(0.9, 0.65)));
  // Fondo transparente: color premultiplicado y opacidad según el brillo; la
  // luz muy tenue se vuelve transparente del todo para no dejar velo.
  col = clamp(col, 0.0, 1.0);
  float veilPeak = max(col.r, max(col.g, col.b));
  float clearCut = smoothstep(0.04, 0.12, veilPeak);
  col *= clearCut;
  float alpha = clamp(veilPeak * 1.25, 0.0, 1.0) * clearCut;
  fragColor = vec4(col, alpha);
}
""",
};
