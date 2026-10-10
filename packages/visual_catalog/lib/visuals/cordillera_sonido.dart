// Cordillera de Sonido — la canción convertida en una cordillera que avanza.
// Varias veces por segundo se guarda el espectro como una fila de montañas,
// más altas en el centro como en la portada de Unknown Pleasures; las filas
// viajan hacia la cámara en perspectiva y cada una tapa a las de detrás. Los
// golpes levantan picos, las cumbres altas se encienden en violeta y, sin
// música, un relieve suave mantiene viva la cordillera.
const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kRows = 44, kCols = 60;
  // Filas a ritmo fijo contadas con el tiempo absoluto: idéntico a 30 y 60 FPS.
  static constexpr double kRate = 16.0;
  std::vector<float> grid;
  std::vector<float> peaks;
  int64_t pushed = -1;
  float frac = 0;
  std::array<float, 31> spec{};
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Geometría y pinturas de las filas del cuadro (memoria reservada en reset).
  mutable std::vector<Path> crests, fills;
  const Path blank;
  mutable std::vector<Paint> auras, strokes;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float hash(float n) {
    float x = std::sin(n) * 43758.5453f;
    return x - std::floor(x);
  }

  void push(int64_t n) {
    int row = int(((n % kRows) + kRows) % kRows);
    float fn = float(n % 100000);
    float best = 0;
    for (int c = 0; c < kCols; c++) {
      float x = float(c) / float(kCols - 1);
      // Graves en el centro y agudos hacia los lados, en espejo.
      float d = std::fabs(x - 0.5f) * 2.0f;
      float bandPos = d * 24.0f;
      int b0 = std::min(30, int(bandPos));
      int b1 = std::min(30, b0 + 1);
      float sv = spec[b0] + (spec[b1] - spec[b0]) * (bandPos - float(b0));
      float env = std::exp(-(x - 0.5f) * (x - 0.5f) / (0.23f * 0.23f));
      float ambient = 0.10f + 0.06f * std::sin(x * 11.0f + fn * 0.23f) + 0.05f * std::sin(x * 23.0f - fn * 0.17f) +
                      0.05f * hash(fn * 1.3f + float(c) * 7.1f);
      float value = env * (ambient + 0.95f * sv * (0.8f + 0.7f * kick));
      grid[size_t(row * kCols + c)] = value;
      best = std::max(best, value);
    }
    peaks[size_t(row)] = best;
  }

 public:
  void reset(uint32_t seed) override {
    grid.assign(size_t(kRows * kCols), 0.0f);
    peaks.assign(size_t(kRows), 0.0f);
    pushed = -1;
    frac = 0;
    spec.fill(0);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    crests.assign(size_t(kRows), Path());
    fills.assign(size_t(kRows), Path());
    auras.assign(size_t(kRows), Paint());
    strokes.assign(size_t(kRows), Paint());
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& m = f.music;
    bass = follow(bass, m.bass, 22.0f, 4.5f, dt);
    body = follow(body, m.body, 12.0f, 3.0f, dt);
    spark = follow(spark, m.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, m.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, m.active ? std::pow(std::clamp(m.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    for (int i = 0; i < 31; i++) spec[i] = follow(spec[i], m.smoothSpectrum[i], 30.0f, 6.0f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : m.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : m.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : m.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((m.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, m.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    double rate = kRate * std::clamp(double(f.speed), 0.25, 3.0);
    int64_t target = int64_t(std::floor(f.time * rate + 1e-6));
    if (pushed < 0 || target < pushed || target - pushed > kRows) {
      // Primera vez o salto: se llena la cordillera con relieve ambiental.
      int64_t start = target - kRows + 1;
      for (int64_t n = start; n <= target; n++) push(n);
      pushed = target;
    }
    while (pushed < target) push(++pushed);
    frac = std::clamp(float(f.time * rate - double(pushed)), 0.0f, 1.0f);
  }

  void render(const Frame& f, Canvas& c) const override {
    float amp = f.intensity;
    float w = f.width, h = f.height;
    std::vector<float> u;
    u.reserve(20);
    u.insert(u.end(), {bass * amp, kick * amp, energy, f.glow});
    u.insert(u.end(), {spark * amp, flash * amp, 0.0f, 0.0f});
    for (int i = 0; i < 4; i++) u.insert(u.end(), {f.colors[i].r, f.colors[i].g, f.colors[i].b});
    c.material("ridge_sky", {0, 0, w, h}, u);
    if (pushed < 0) return;

    float s = std::min(w, h);
    float px = s / 400.0f;
    const Color& bg = f.colors[0];
    const Color& line = f.colors[1];
    const Color& glow = f.colors[2];
    // De la fila más antigua (al fondo) a la más reciente (delante).
    int count = 0;
    for (int k = kRows - 1; k >= 0; k--) {
      int64_t n = pushed - k;
      int row = int(((n % kRows) + kRows) % kRows);
      float age = float(k) + frac;
      float z = age / float(kRows);
      if (z >= 1.0f) continue;
      float persp = 1.0f / (1.0f + 1.4f * z);
      float yBase = h * 0.16f + h * 0.74f * std::pow(1.0f - z, 1.3f);
      float hs = h * 0.24f * persp * (0.9f + 0.4f * amp);
      float spread = w * 1.25f * persp;
      Path& crest = crests[size_t(count)];
      Path& fill = fills[size_t(count)];
      crest = blank;  // copia de un trazo vacío: conserva la memoria del cuadro anterior
      for (int col = 0; col < kCols; col++) {
        float x = w * 0.5f + (float(col) / float(kCols - 1) - 0.5f) * spread;
        float y = yBase - grid[size_t(row * kCols + col)] * hs;
        if (col == 0) crest.moveTo(x, y); else crest.lineTo(x, y);
      }
      fill = crest;
      fill.lineTo(w * 0.5f + 0.5f * spread, yBase + h);
      fill.lineTo(w * 0.5f - 0.5f * spread, yBase + h);
      fill.close();
      float fade = std::pow(1.0f - z, 0.8f) * std::clamp((1.0f - z) * 6.0f, 0.0f, 1.0f);
      float peak = peaks[size_t(row)];
      Paint& aura = auras[size_t(count)];
      aura = Paint();
      aura.strokeWidth = 5.0f * px * persp;
      aura.strokeJoin = 1;
      aura.color = {glow.r, glow.g, glow.b, std::clamp((0.06f + 0.5f * peak) * fade * f.glow * (0.8f + 0.6f * kick), 0.0f, 1.0f)};
      Paint& stroke = strokes[size_t(count)];
      stroke = Paint();
      stroke.strokeWidth = (1.1f + 0.6f * kick * amp) * px * (0.6f + 0.4f * persp);
      stroke.strokeJoin = 1;
      stroke.color = {line.r, line.g, line.b, std::clamp(fade * (0.75f + 0.25f * flash), 0.0f, 1.0f)};
      count++;
    }
    // Cada fila tapa a las de detrás con su relleno opaco y encima va su
    // línea: todo eso es sourceOver y va en un solo lote, en el mismo orden.
    Paint cover;
    cover.color = {bg.r, bg.g, bg.b, 1.0f};
    for (int i = 0; i < count; i++) {
      c.path(fills[size_t(i)], cover);
      c.path(crests[size_t(i)], strokes[size_t(i)]);
    }
    // El halo de cada cresta se suma a la luz (plus) entre su relleno y su
    // línea. Va en una capa aditiva aparte con el mismo orden: allí el relleno
    // se repite en negro opaco (tapa los halos de detrás) y la línea en negro
    // con su opacidad (atenúa lo que cubre), así la suma final es la misma.
    c.saveLayer(1.0f, Blend::plus);
    Paint hide;
    hide.color = {0.0f, 0.0f, 0.0f, 1.0f};
    bool lit = false;  // antes del primer halo no hay nada que tapar en la capa
    for (int i = 0; i < count; i++) {
      if (lit) c.path(fills[size_t(i)], hide);
      if (auras[size_t(i)].color.a > 0.0f) {
        c.path(crests[size_t(i)], auras[size_t(i)]);
        lit = true;
      }
      if (!lit) continue;
      Paint shade = strokes[size_t(i)];
      shade.color = {0.0f, 0.0f, 0.0f, shade.color.a};
      c.path(crests[size_t(i)], shade);
    }
    c.restore();
  }
};
''';

const shaderSources = <String, String>{
  'ridge_sky': r"""
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
  vec2 uv = frag / uSize;
  // Cielo negro con un resplandor violeta en el horizonte.
  float horizon = exp(-(uv.y - 0.16) * (uv.y - 0.16) * 60.0);
  vec3 col = uC0 + uC3 * horizon * (0.35 + 0.3 * uA.x + 0.4 * uA.y) * uA.w;
  col += uC2 * uB.y * 0.03;
  col += (hash12(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
""",
};
