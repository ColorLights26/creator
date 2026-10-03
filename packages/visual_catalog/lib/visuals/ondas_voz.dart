// Ondas de Voz — ondas de color translúcidas como las de un asistente de voz.
// Tres colores, con dos ondas cada uno, se dibujan rellenas y en espejo sobre
// una línea central, se atenúan hacia los lados y se suman donde se cruzan;
// una onda blanca fina las acompaña. Los graves mueven la onda rosa, los
// medios la azul y los agudos la verde; cada golpe las dispara y la energía
// acelera su baile. Sin música queda una onda suave en reposo.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0, mids = 0, highs = 0;
  // Fase en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double phase = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = mids = highs = 0;
    phase = rng.unit() * 10.0;
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 20.0f, 4.0f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    float mi = 0, hi = 0;
    for (int i = 9; i < 21; i++) mi = std::max(mi, m.smoothSpectrum[i]);
    for (int i = 21; i < 31; i++) hi = std::max(hi, m.smoothSpectrum[i]);
    mids = follow(mids, mi, 16.0f, 4.0f, dt);
    highs = follow(highs, hi, 20.0f, 5.0f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    phase += f.delta * f.speed * (1.6 + 3.0 * drive + 1.5 * kick);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float idle = 0.06f;
    float aLow = idle + (0.45f * bass + 0.18f * kick) * amp;
    float aMid = idle * 0.8f + (0.38f * mids + 0.15f * kick) * amp;
    float aHigh = idle * 0.6f + (0.32f * highs + 0.12f * kick) * amp;
    std::vector<float> u;
    u.reserve(24);
    u.insert(u.end(), {float(std::fmod(phase, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {aLow, aMid, aHigh, 0.0f});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("voice_waves", {0, 0, f.width, f.height}, u);
  }
};
''';

const shaderSources = <String, String>{
  'voice_waves': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // fase, graves, golpe, energía
uniform vec4 uW;   // amplitudes de graves, medios y agudos
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

// Una onda rellena en espejo: interior translúcido y borde luminoso.
vec3 wave(float X, float Y, float att, float a, float freq, float ph, vec3 c) {
  float yc = abs(a * att * sin(freq * X - ph));
  float ay = abs(Y);
  float fill = smoothstep(yc + 0.004, yc - 0.004, ay);
  float edge = exp(-abs(ay - yc) * 55.0) * smoothstep(0.0, 0.01, yc);
  return c * (fill * 0.32 + edge * 0.55);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  float X = frag.x / uSize.x * 3.2 - 1.6;
  float Y = (frag.y - 0.5 * uSize.y) / scale;
  float X2 = X * X;
  float att = pow(4.0 / (4.0 + X2 * X2), 4.0);
  float ph = uA.x;
  vec3 col = uC0;
  // Resplandor detrás de las ondas.
  col += mix(uC1, uC2, 0.5) * exp(-Y * Y * 9.0) * att * (0.05 + 0.10 * uA.y + 0.12 * uA.z) * uB.x;
  col += wave(X, Y, att, uW.x, 2.2, ph * 1.0, uC1);
  col += wave(X, Y, att, uW.x * 0.75, 3.1, ph * 1.3 + 2.1, uC1);
  col += wave(X, Y, att, uW.y, 2.8, ph * 1.15 + 1.2, uC2);
  col += wave(X, Y, att, uW.y * 0.75, 3.9, ph * 1.45 + 3.4, uC2);
  col += wave(X, Y, att, uW.z, 3.4, ph * 1.3 + 0.6, uC3);
  col += wave(X, Y, att, uW.z * 0.75, 4.6, ph * 1.7 + 4.2, uC3);
  // Onda blanca de apoyo.
  float y0 = 0.018 * att * sin(X * 4.0 - ph * 1.2);
  col += vec3(1.0) * exp(-abs(Y - y0) * 350.0) * (0.35 + 0.4 * uA.z) * att;
  col += mix(uC2, uC3, 0.5) * uB.z * 0.03;
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
