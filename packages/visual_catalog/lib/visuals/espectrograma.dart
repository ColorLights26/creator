// Espectrograma — la música vista como un mapa de calor en cascada.
// Muchas veces por segundo se guarda el espectro de la música como una fila
// de celdas (graves a un lado, agudos al otro) coloreadas del negro al rojo,
// naranja, amarillo y blanco según su fuerza; las filas nuevas entran por
// arriba y bajan, así la canción queda dibujada. En espejo, los graves van
// en el centro. Sin música se dibujan barridos y pulsos de demostración. Y de
// vez en cuando aparece en el sonido una figura escondida (una cara, un
// corazón, una estrella, un ojo), como la cara que Aphex Twin escondió en
// una de sus canciones.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('velocidad', 'Velocidad', min: .4, max: 2.5, value: 1),
  CreatorModifier.choice('paleta', 'Colores', options: ['Fuego', 'Ácido', 'Paleta']),
  CreatorModifier.toggle('espejo', 'Espejo', value: true),
  CreatorModifier.toggle('figuras', 'Figuras escondidas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kRows = 130;
  static constexpr int kBins = 32;
  static constexpr int kFig = 16;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double rowClock = 0;
  int64_t captured = 0;
  int head = 0, figure = -1, figureRow = 0, beats = 0, figureCount = 0;
  bool figureQueued = false;
  std::array<std::array<float, kBins>, kRows> rows{};
  std::array<float, 31> live{};
  bool active = false;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Figuras de 16×16 escondidas: cara, corazón, estrella y ojo.
  static uint16_t figureRowBits(int fig, int row) {
    static const uint16_t art[4][kFig] = {
        {0x07E0, 0x1818, 0x2004, 0x4002, 0x4C32, 0x8C31, 0x8001, 0x8001, 0x8001, 0x9009, 0x8811, 0x47E2, 0x4002, 0x2004, 0x1818, 0x07E0},
        {0x0000, 0x1C38, 0x3E7C, 0x7FFE, 0x7FFE, 0x7FFE, 0x7FFE, 0x3FFC, 0x1FF8, 0x0FF0, 0x07E0, 0x03C0, 0x0180, 0x0000, 0x0000, 0x0000},
        {0x0180, 0x0180, 0x03C0, 0x03C0, 0x07E0, 0xFFFF, 0x7FFE, 0x3FFC, 0x1FF8, 0x0FF0, 0x1FF8, 0x1E78, 0x3C3C, 0x381C, 0x700E, 0x6006},
        {0x0000, 0x0000, 0x07E0, 0x1FF8, 0x3C3C, 0x700E, 0x63C6, 0xC7E3, 0xC7E3, 0x63C6, 0x700E, 0x3C3C, 0x1FF8, 0x07E0, 0x0000, 0x0000}};
    return art[fig % 4][std::clamp(row, 0, kFig - 1)];
  }

  // Fila de demostración sin música, calculada sólo del tiempo de la fila.
  static float idleBin(int b, double t) {
    float x = float(b) / float(kBins - 1);
    float sweep = float(std::fmod(t * 0.18, 1.0));
    float chirp = std::exp(-std::pow((x - sweep) * 14.0f, 2.0f));
    float wob = 0.5f + 0.35f * float(std::sin(t * 0.7));
    float tone = std::exp(-std::pow((x - wob) * 20.0f, 2.0f)) * 0.8f;
    float beat = std::fmod(t, 0.5) < 0.06 ? std::exp(-x * 4.0f) * 0.9f : 0.0f;
    float noise = 0.05f + 0.05f * float(std::sin(double(b) * 12.9898 + t * 78.233 - std::floor(double(b) * 12.9898 + t * 78.233)));
    return std::clamp(chirp * 0.9f + tone + beat + noise * 0.5f, 0.0f, 1.0f);
  }

  void capture(const Frame& f, bool figuresOn) {
    head = (head + 1) % kRows;
    double t = double(captured) / 30.0;
    auto& row = rows[size_t(head)];
    for (int b = 0; b < kBins; b++) {
      float v;
      if (active) {
        float pos = float(b) / float(kBins - 1) * 29.5f;
        int i0 = int(pos);
        float fr = pos - float(i0);
        v = (live[size_t(i0)] * (1.0f - fr) + live[size_t(std::min(i0 + 1, 30))] * fr) * 1.25f;
      } else {
        v = idleBin(b, t);
      }
      row[size_t(b)] = std::clamp(v, 0.0f, 1.0f);
    }
    // Figura escondida: se escribe de abajo arriba para que se vea derecha.
    if (figuresOn && figure >= 0) {
      uint16_t bits = figureRowBits(figure, kFig - 1 - figureRow);
      int start = std::max(0, (kBins - kFig) / 2);
      for (int k = 0; k < kFig; k++) {
        if (bits & (0x8000 >> k)) row[size_t(start + k)] = std::max(row[size_t(start + k)], 0.95f);
      }
      if (++figureRow >= kFig) {
        figure = -1;
        figureRow = 0;
      }
    }
    (void)f;
  }

 public:
  void reset(uint32_t seed) override {
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    rowClock = 0;
    captured = 0;
    head = 0;
    figure = -1;
    figureRow = 0;
    beats = 0;
    figureCount = int(seed % 4u);
    figureQueued = false;
    for (auto& r : rows) r.fill(0);
    live.fill(0);
    active = false;
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f && ++beats % 16 == 0) figureQueued = true;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    active = mu.active;
    for (int i = 0; i < 31; i++) live[size_t(i)] = mu.smoothSpectrum[size_t(i)];
    rowClock += f.delta * f.speed * m.velocidad;
    int64_t target = int64_t(std::floor(rowClock * 30.0 + 1e-6));
    if (target - captured > kRows) captured = target - kRows;
    while (captured < target) {
      captured++;
      // Sin música, una figura cada 12 s de filas.
      if (!active && captured % 360 == 0) figureQueued = true;
      if (figureQueued && figure < 0) {
        figure = figureCount++ % 4;
        figureRow = 0;
        figureQueued = false;
      }
      capture(f, m.figuras);
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    Paint back;
    back.color = Color{bg.r, bg.g, bg.b, 1.0f};
    c.rect({0, 0, f.width, f.height}, back);
    const int buckets = 8;
    std::array<Color, buckets> ramp;
    for (int k = 0; k < buckets; k++) {
      float v = (float(k) + 1.0f) / float(buckets);
      Color col;
      if (m.paleta == 1) {
        col = v < 0.5f ? Color{0.0f, v * 1.6f, 0.05f, 1.0f} : Color{std::min(1.0f, (v - 0.5f) * 2.0f), std::min(1.0f, 0.8f + v * 0.2f), std::max(0.0f, (v - 0.8f) * 3.0f), 1.0f};
      } else {
        const Color& a = f.colors[1];
        const Color& b = f.colors[2];
        const Color& d = f.colors[3];
        if (v < 0.4f) col = Color{a.r * v / 0.4f, a.g * v / 0.4f, a.b * v / 0.4f, 1.0f};
        else if (v < 0.7f) { float u = (v - 0.4f) / 0.3f; col = Color{a.r + (b.r - a.r) * u, a.g + (b.g - a.g) * u, a.b + (b.b - a.b) * u, 1.0f}; }
        else if (v < 0.9f) { float u = (v - 0.7f) / 0.2f; col = Color{b.r + (d.r - b.r) * u, b.g + (d.g - b.g) * u, b.b + (d.b - b.b) * u, 1.0f}; }
        else col = Color{1.0f, 1.0f, 0.92f, 1.0f};
        if (m.paleta == 2) col = Color{col.g, col.r * 0.6f, col.r, 1.0f};
      }
      ramp[size_t(k)] = col;
    }
    float rowH = f.height / float(kRows - 2);
    float frac = float(rowClock * 30.0 - std::floor(rowClock * 30.0));
    float binW = m.espejo ? f.width * 0.5f / float(kBins) : f.width / float(kBins);
    std::array<Path, buckets> paths;
    for (int a = 0; a < kRows; a++) {
      const auto& row = rows[size_t(((head - a) % kRows + kRows) % kRows)];
      float y = (float(a) - 1.0f + frac) * rowH;
      if (y > f.height) break;
      int b = 0;
      while (b < kBins) {
        int k = std::min(buckets - 1, int(row[size_t(b)] * amp * float(buckets)));
        if (row[size_t(b)] * amp < 0.08f) {
          b++;
          continue;
        }
        int startB = b;
        while (b < kBins && std::min(buckets - 1, int(row[size_t(b)] * amp * float(buckets))) == k && row[size_t(b)] * amp >= 0.08f) b++;
        float w = float(b - startB) * binW;
        if (m.espejo) {
          float x0 = f.width * 0.5f + float(startB) * binW;
          paths[size_t(k)].rect({x0, y, w + 0.5f, rowH + 0.5f});
          paths[size_t(k)].rect({f.width * 0.5f - float(b) * binW, y, w + 0.5f, rowH + 0.5f});
        } else {
          paths[size_t(k)].rect({float(startB) * binW, y, w + 0.5f, rowH + 0.5f});
        }
      }
    }
    for (int k = 0; k < buckets; k++) {
      Paint p;
      p.color = ramp[size_t(k)];
      c.path(paths[size_t(k)], p);
    }
    // Brillo de la fila que está entrando.
    Paint edge = Paint::linear({0, 0}, {0, rowH * 8.0f}, {f.colors[3].opacity(std::clamp((0.25f + 0.3f * kick) * amp, 0.0f, 1.0f)), f.colors[3].opacity(0.0f)});
    edge.blend = Blend::plus;
    c.rect({0, 0, f.width, rowH * 8.0f}, edge);
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = f.colors[2].opacity(std::clamp(flash * 0.05f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
