// Olas de Cubos — tablero isométrico de columnas que ondulan.
// Una cuadrícula de cubos vista en isométrico sube y baja en ondas que salen
// del centro, como el clásico "cube wave". Las caras superiores son de marfil
// y las laterales de coral con luz y sombra; las columnas altas brillan más.
// Cada golpe lanza una ola extra desde el centro y enciende las caras, los
// graves aumentan la altura y la energía acelera las ondas.
const nativeSource = r'''
class Visual final : public Scene {
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Fase en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double phase = 0, swirl = 0;
  float ringR = 30.0f, ringAmp = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static Color shade(const Color& c, float g) {
    return {std::min(1.0f, c.r * g), std::min(1.0f, c.g * g), std::min(1.0f, c.b * g), 1.0f};
  }

  static Color blend(const Color& a, const Color& b, float t) {
    return {a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1.0f};
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    phase = rng.unit() * 6.2831853;
    swirl = rng.unit() * 6.2831853;
    ringR = 30.0f;
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
      ringR = 0.0f;
      ringAmp = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    ringR += dt * (9.0f + 4.0f * drive);
    ringAmp *= std::exp(-dt * 1.4f);
    phase += f.delta * f.speed * (1.4 + 2.2 * drive);
    swirl += f.delta * f.speed * 0.15;
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {float(std::fmod(phase, 1000.0)), bass * amp, kick * amp, energy});
    u.insert(u.end(), {f.glow, spark * amp, flash * amp, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("cube_floor", {0, 0, f.width, f.height}, u);

    int n = int(15.0f + 4.0f * std::clamp(f.detail, 0.25f, 2.0f));
    float hw = f.width / (float(n) * 0.82f);  // medio ancho de una baldosa
    float hh = hw * 0.5f;
    float cx = f.width * 0.5f;
    float top = f.height * 0.5f - float(n) * hh + hw * 1.2f;
    float center = float(n - 1) * 0.5f;
    float t = float(std::fmod(phase, 6283.0));
    float baseH = hw * 1.2f;
    float waveH = hw * (1.6f + 1.4f * bass) * amp;
    const Color& coral = f.colors[1];
    const Color& ivory = f.colors[2];
    const Color& deep = f.colors[3];
    float glowKick = 1.0f + 0.35f * kick * amp + 0.25f * flash * amp;
    float sw = float(std::sin(swirl));
    // Pintor: diagonales de atrás hacia delante.
    for (int sum = 0; sum <= 2 * (n - 1); sum++) {
      for (int i = std::max(0, sum - (n - 1)); i <= std::min(n - 1, sum); i++) {
        int j = sum - i;
        float X = cx + float(i - j) * hw;
        float Y = top + float(i + j) * hh;
        float di = float(i) - center, dj = float(j) - center;
        float d = std::sqrt(di * di + dj * dj);
        float wave = 0.5f + 0.5f * std::sin(d * 0.55f - t + sw * 0.4f * di * 0.1f);
        float ring = ringAmp * std::exp(-(d - ringR) * (d - ringR) * 0.25f);
        float k = std::clamp(wave + 0.9f * ring * amp, 0.0f, 1.8f);
        float H = baseH + waveH * k;
        // Recorte: columnas fuera de la pantalla no se dibujan.
        if (X + hw < 0 || X - hw > f.width || Y - hh - H > f.height || Y + hh < 0) continue;
        float lift = std::clamp(k / 1.2f, 0.0f, 1.0f);
        Color topC = shade(blend(blend(coral, ivory, 0.8f), ivory, lift), (0.82f + 0.25f * lift) * glowKick);
        Color leftC = shade(blend(coral, deep, 0.15f - 0.15f * lift), (0.75f + 0.3f * lift) * glowKick);
        Color rightC = shade(blend(coral, deep, 0.55f), (0.6f + 0.2f * lift) * glowKick);
        Path left, right, cap;
        left.moveTo(X - hw, Y - H).lineTo(X, Y + hh - H).lineTo(X, Y + hh).lineTo(X - hw, Y).close();
        right.moveTo(X, Y + hh - H).lineTo(X + hw, Y - H).lineTo(X + hw, Y).lineTo(X, Y + hh).close();
        cap.moveTo(X, Y - hh - H).lineTo(X + hw, Y - H).lineTo(X, Y + hh - H).lineTo(X - hw, Y - H).close();
        Paint pl, pr, pt;
        pl.color = leftC;
        pr.color = rightC;
        pt.color = topC;
        c.path(left, pl);
        c.path(right, pr);
        c.path(cap, pt);
      }
    }
  }
};
''';

const shaderSources = <String, String>{
  'cube_floor': r"""
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uA;   // fase, graves, golpe, energía
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
  // Fondo azul petróleo con un resplandor coral detrás del tablero.
  vec3 col = mix(uC3, uC0, smoothstep(1.1, -0.2, p.y));
  col += uC1 * exp(-dot(p, p) * 1.6) * (0.06 + 0.06 * uA.y + 0.1 * uA.z) * uB.x;
  col *= 1.0 - 0.35 * smoothstep(0.6, 1.4, length(p * vec2(0.9, 0.65)));
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
