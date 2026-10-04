// Osciloscopio — figuras vectoriales dibujadas por un haz de luz.
// Como en la música de osciloscopio, un haz verde dibuja una figura cerrada:
// Lissajous, rosas, espirógrafos y un nudo toroidal que gira en 3D. Cada
// cuatro golpes la figura se transforma en la siguiente (o cada seis segundos
// sin música); las bandas del espectro la deforman, cada golpe la hace saltar
// y una copia tenue detrás imita la persistencia del fósforo.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kSamples = 520;
  static constexpr int kShapes = 6;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 6> bands{};
  // Fase en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double phase = 0, sinceShape = 0;
  int shapeA = 0, shapeB = 0, beats = 0;
  float morph = 1, punch = 0, punchVel = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Figura s evaluada en tau (0..2π) y fase t; devuelve x, y en -1..1.
  static void shape(int s, float tau, float t, float& x, float& y) {
    switch (s) {
      case 0: x = std::sin(3.0f * tau + t * 0.6f); y = std::sin(2.0f * tau); break;
      case 1: {
        float r = std::cos(5.0f * tau + t * 0.2f);
        x = r * std::cos(tau);
        y = r * std::sin(tau);
        break;
      }
      case 2: {
        // Espirógrafo (epitrocoide) cerrado en tres vueltas.
        float a = tau * 3.0f;
        x = (std::cos(a) * 0.6f + 0.4f * std::cos(a * 5.0f / 3.0f + t * 0.4f));
        y = (std::sin(a) * 0.6f - 0.4f * std::sin(a * 5.0f / 3.0f + t * 0.4f));
        break;
      }
      case 3: {
        // Nudo toroidal (2, 3) que gira en 3D.
        float r = 0.55f + 0.3f * std::cos(3.0f * tau);
        float px = r * std::cos(2.0f * tau), py = r * std::sin(2.0f * tau), pz = 0.3f * std::sin(3.0f * tau);
        float ca = std::cos(t * 0.5f), sa = std::sin(t * 0.5f);
        float ry = py * std::cos(0.6f) - pz * std::sin(0.6f);
        x = px * ca + pz * sa;
        y = ry;
        break;
      }
      case 4: x = std::sin(5.0f * tau + t * 0.45f); y = std::sin(4.0f * tau); break;
      default: {
        float r = 0.5f + 0.45f * std::sin(7.0f * tau + t * 0.3f);
        x = r * std::cos(tau);
        y = r * std::sin(tau);
        break;
      }
    }
  }

  void next() {
    shapeA = shapeB;
    shapeB = (shapeB + 1) % kShapes;
    morph = 0;
    sinceShape = 0;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    phase = rng.unit() * 20.0;
    sinceShape = 0;
    shapeA = shapeB = int(rng.unit() * float(kShapes)) % kShapes;
    beats = 0;
    morph = 1;
    punch = punchVel = 0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    for (int i = 0; i < 6; i++) {
      float v = 0;
      for (int k = i * 5; k < i * 5 + 5 && k < 31; k++) v = std::max(v, m.smoothSpectrum[k]);
      bands[size_t(i)] = follow(bands[size_t(i)], v, 25.0f, 5.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) {
      beats++;
      punchVel += 2.2f * hit;
      if (beats % 4 == 0) next();
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    punchVel += (-punch * 50.0f - punchVel * 8.0f) * dt;
    punch += punchVel * dt;
    morph = std::min(1.0f, morph + dt * 1.3f);
    sinceShape += f.delta;
    if (!m.active && sinceShape > 6.0) next();
    phase += f.delta * f.speed * (0.8 + 1.6 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float w = f.width, h = f.height, s = std::min(w, h);
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {bass * amp, kick * amp, energy, f.glow});
    u.insert(u.end(), {spark * amp, flash * amp, float(std::fmod(phase, 1000.0)), 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("crt_screen", {0, 0, w, h}, u);

    float e = morph * morph * (3.0f - 2.0f * morph);
    float R = s * 0.45f * (1.0f + 0.12f * std::max(-0.3f, punch) * amp);
    float cx = w * 0.5f, cy = h * 0.5f;
    auto trace = [&](float t, Path& path) {
      for (int i = 0; i <= kSamples; i++) {
        float tau = 6.2831853f * float(i) / float(kSamples);
        float ax, ay, bx, by;
        shape(shapeA, tau, t, ax, ay);
        shape(shapeB, tau, t, bx, by);
        float x = ax + (bx - ax) * e, y = ay + (by - ay) * e;
        // El espectro deforma la figura con ondulaciones de distinta frecuencia.
        float wob = 1.0f + amp * (0.10f * bands[0] * std::sin(tau * 2.0f + t) + 0.07f * bands[2] * std::sin(tau * 9.0f - t * 1.7f) +
                                  0.05f * bands[4] * std::sin(tau * 23.0f + t * 2.3f));
        float X = cx + x * R * wob, Y = cy + y * R * wob;
        if (i == 0) path.moveTo(X, Y); else path.lineTo(X, Y);
      }
    };
    float t = float(std::fmod(phase, 6283.0));
    Path ghost, beam;
    trace(t - 0.12f, ghost);
    trace(t, beam);
    float px = s / 400.0f;
    float gain = std::clamp((0.85f + 0.5f * bass + 0.6f * kick) * amp, 0.0f, 1.6f);
    const Color& green = f.colors[1];
    const Color& light = f.colors[2];
    const Color& white = f.colors[3];
    Paint ghostPaint;
    ghostPaint.blend = Blend::plus;
    ghostPaint.strokeWidth = 2.0f * px;
    ghostPaint.strokeJoin = 1;
    ghostPaint.color = {green.r, green.g, green.b, std::clamp(0.18f * gain, 0.0f, 1.0f)};
    c.path(ghost, ghostPaint);
    Paint glow = ghostPaint;
    glow.strokeWidth = 12.0f * px;
    glow.color = {green.r, green.g, green.b, std::clamp(0.16f * gain * f.glow, 0.0f, 1.0f)};
    c.path(beam, glow);
    Paint mid = ghostPaint;
    mid.strokeWidth = 3.6f * px;
    mid.color = {green.r, green.g, green.b, std::clamp(0.75f * gain, 0.0f, 1.0f)};
    c.path(beam, mid);
    Paint core = ghostPaint;
    core.strokeWidth = 1.2f * px;
    core.color = {light.r, light.g, light.b, std::clamp(0.8f * gain, 0.0f, 1.0f)};
    c.path(beam, core);
  }
};
''';

const shaderSources = <String, String>{
  'crt_screen': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // graves, golpe, energía, glow
uniform vec4 uB;   // agudos, destello, fase
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
  // Pantalla de tubo: retícula tenue, brillo central y líneas de barrido.
  vec2 g = abs(fract(p * 8.0 + 0.5) - 0.5) * scale / 8.0;
  float grid = (1.0 - smoothstep(0.0, 1.2, min(g.x, g.y))) * 0.05;
  float axes = (1.0 - smoothstep(0.0, 1.5, min(abs(p.x), abs(p.y)) * scale)) * 0.08;
  vec3 col = uC0 + uC1 * (grid + axes) * (0.6 + 0.4 * uA.w);
  col += uC1 * exp(-dot(p, p) * 3.0) * (0.03 + 0.04 * uA.x + 0.1 * uA.y) * uA.w;
  col *= 0.92 + 0.08 * sin(frag.y * 1.6);
  col += uC2 * uB.y * 0.04;
  col *= 1.0 - 0.5 * smoothstep(0.45, 1.3, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
