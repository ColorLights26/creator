// Espectrograma — la música vista como un mapa de calor en cascada.
// Muchas veces por segundo se guarda el espectro de la música como una fila
// de celdas (graves a un lado, agudos al otro) coloreadas del negro al rojo,
// naranja, amarillo y blanco según su fuerza; las filas nuevas entran por
// arriba y bajan, así la canción queda dibujada. En espejo, los graves van
// en el centro. Sin música se dibujan barridos y pulsos de demostración. Y de
// vez en cuando aparece en el sonido una figura escondida (una cara, un
// corazón, una estrella, un ojo), como la cara que Aphex Twin escondió en
// una de sus canciones.
// Caída cambia cómo bajan las filas: frenando (llegan grandes y se alejan),
// parejas o acelerando (nacen finas y caen hacia ti). Pulso elige qué hace la
// música además del calor: Calor enciende el borde con cada golpe, Golpes
// marca cada golpe como una franja que baja por la cascada y Graves ensancha
// la zona de graves al ritmo del bajo. Figuras escondidas decide cuántas
// figuras viajan en cada vuelta de la cascada (0 = ninguna).
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MOVIMIENTO: el carácter de la caída (1 = filas parejas de siempre).
  CreatorModifier.slider('velocidad', 'Caída', min: .4, max: 2.5, value: 1),
  // MÚSICA: qué parte de la cascada reacciona.
  CreatorModifier.choice('paleta', 'Pulso', options: ['Calor', 'Golpes', 'Graves']),
  // MODO: graves en el centro.
  CreatorModifier.toggle('espejo', 'Espejo', value: true),
  // FORMA: cuántas figuras escondidas viajan en cada vuelta.
  CreatorModifier.steps('figuras', 'Figuras escondidas', min: 0, max: 3, value: 1),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kRows = 130;
  static constexpr int kBins = 32;
  static constexpr int kFig = 16;
  // Figuras escondidas: cada vuelta de kCycle filas tiene kSlots huecos fijos;
  // el ajuste decide cuántos se llenan. Todo sale del número de fila.
  static constexpr int kCycle = 192;
  static constexpr int kSlots = 3;
  // Golpes: anillo fijo de las últimas filas donde cayó un golpe.
  static constexpr int kHits = 16;
  struct Hit { int64_t row; float strength; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double rowClock = 0;
  int64_t captured = 0;
  int head = 0, figureSeed = 0, hitHead = 0;
  std::array<std::array<float, kBins>, kRows> rows{};
  std::array<Hit, kHits> hits{};
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

  void capture() {
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
  }

 public:
  void reset(uint32_t seed) override {
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    rowClock = 0;
    captured = 0;
    head = 0;
    figureSeed = int(seed % 4u);
    hitHead = 0;
    for (auto& r : rows) r.fill(0);
    hits.fill(Hit{-1000000, 0.0f});
    live.fill(0);
    active = false;
  }

  void update(const Frame& f) override {
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
    const bool fresh = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    active = mu.active;
    for (int i = 0; i < 31; i++) live[size_t(i)] = mu.smoothSpectrum[size_t(i)];
    rowClock += f.delta * f.speed;
    int64_t target = int64_t(std::floor(rowClock * 30.0 + 1e-6));
    if (target - captured > kRows) captured = target - kRows;
    while (captured < target) {
      captured++;
      capture();
    }
    // El golpe queda anotado en la fila más nueva; render dibuja su franja.
    if (fresh) {
      hits[size_t(hitHead)] = Hit{captured, hit};
      hitHead = (hitHead + 1) % kHits;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const bool mirror = modifiers(f).espejo;
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    Paint back;
    back.color = Color{bg.r, bg.g, bg.b, 1.0f};
    c.rect({0, 0, f.width, f.height}, back);
    const int buckets = 8;
    std::array<Color, buckets> ramp;
    for (int k = 0; k < buckets; k++) {
      float v = (float(k) + 1.0f) / float(buckets);
      const Color& a = f.colors[1];
      const Color& b = f.colors[2];
      const Color& d = f.colors[3];
      Color col;
      if (v < 0.4f) col = Color{a.r * v / 0.4f, a.g * v / 0.4f, a.b * v / 0.4f, 1.0f};
      else if (v < 0.7f) { float u = (v - 0.4f) / 0.3f; col = Color{a.r + (b.r - a.r) * u, a.g + (b.g - a.g) * u, a.b + (b.b - a.b) * u, 1.0f}; }
      else if (v < 0.9f) { float u = (v - 0.7f) / 0.2f; col = Color{b.r + (d.r - b.r) * u, b.g + (d.g - b.g) * u, b.b + (d.b - b.b) * u, 1.0f}; }
      else col = Color{1.0f, 1.0f, 0.92f, 1.0f};
      ramp[size_t(k)] = col;
    }
    // Pulso: cada opción mueve algo distinto; sus pesos funden el cambio.
    const float calor = std::clamp(g.paleta.weight(0), 0.0f, 1.0f);
    const float golpes = std::clamp(g.paleta.weight(1), 0.0f, 1.0f);
    const float graves = std::clamp(g.paleta.weight(2), 0.0f, 1.0f);
    // Caída: proyección de cada fila (u va de 0 arriba a 1 abajo). Con 1 las
    // filas son parejas; por debajo llegan grandes y se alejan frenando; por
    // encima nacen finas y se agrandan acelerando hacia abajo.
    const float lean = std::pow(std::clamp(g.velocidad, 0.4f, 2.5f), -1.5f);
    const float bend = lean - 1.0f;
    auto rowY = [&](float u) { return f.height * u * lean / (1.0f + bend * u); };
    const float rowU = 1.0f / float(kRows - 2);
    // Graves: el bajo ensancha la zona de graves y empuja los agudos.
    const float swell = graves * std::clamp(bass * amp, 0.0f, 1.0f) * 0.85f;
    const float span = mirror ? f.width * 0.5f : f.width;
    std::array<float, kBins + 1> edge;
    for (int b = 0; b <= kBins; b++) {
      float u = float(b) / float(kBins);
      edge[size_t(b)] = span * (u + swell * u * (1.0f - u));
    }
    // Sub-fila coherente con la fila capturada (mismo redondeo que update).
    float frac = std::clamp(float(rowClock * 30.0 + 1e-6 - double(captured)), 0.0f, 1.0f);
    std::array<Path, buckets> paths;
    std::array<float, kBins> cell;
    const int figStart = std::max(0, (kBins - kFig) / 2);
    for (int a = 0; a < kRows; a++) {
      const auto& row = rows[size_t(((head - a) % kRows + kRows) % kRows)];
      float u0 = (float(a) - 1.0f + frac) * rowU;
      float y = rowY(u0);
      if (y > f.height) break;
      float rowH = rowY(u0 + rowU) - y;
      const int64_t idx = captured - int64_t(a);
      for (int b = 0; b < kBins; b++) cell[size_t(b)] = row[size_t(b)];
      if (idx >= 0) {
        // Figura escondida: hueco fijo de la vuelta; se lee de abajo arriba
        // para que se vea derecha.
        const int64_t cycle = idx / kCycle;
        const int o = int(idx % kCycle);
        for (int k = 0; k < kSlots; k++) {
          const int start = 24 + k * 64;
          if (o < start || o >= start + kFig) continue;
          const float show = std::clamp(g.figuras - float(k), 0.0f, 1.0f);
          if (show <= 0.0f) break;
          const int fig = int((cycle * kSlots + k + figureSeed) % 4);
          const uint16_t bits = figureRowBits(fig, kFig - 1 - (o - start));
          for (int q = 0; q < kFig; q++) {
            if (bits & (0x8000 >> q)) cell[size_t(figStart + q)] = std::max(cell[size_t(figStart + q)], 0.95f * show);
          }
          break;
        }
        // Golpes: una franja caliente en la fila del golpe que se apaga hacia
        // las filas más nuevas.
        if (golpes > 0.0f) {
          float line = 0.0f;
          for (const auto& h : hits) {
            const int64_t d = idx - h.row;
            if (d >= 0 && d < 8) line = std::max(line, h.strength * std::exp(-float(d) * 0.3f));
          }
          line = std::min(line, 1.0f) * golpes * 0.85f;
          if (line > 0.0f) {
            for (int b = 0; b < kBins; b++) cell[size_t(b)] = std::max(cell[size_t(b)], line * (0.88f + 0.12f * row[size_t(b)]));
          }
        }
      }
      int b = 0;
      while (b < kBins) {
        int k = std::min(buckets - 1, int(cell[size_t(b)] * amp * float(buckets)));
        if (cell[size_t(b)] * amp < 0.08f) {
          b++;
          continue;
        }
        int startB = b;
        while (b < kBins && std::min(buckets - 1, int(cell[size_t(b)] * amp * float(buckets))) == k && cell[size_t(b)] * amp >= 0.08f) b++;
        float x0 = edge[size_t(startB)], x1 = edge[size_t(b)];
        if (mirror) {
          paths[size_t(k)].rect({f.width * 0.5f + x0, y, x1 - x0 + 0.5f, rowH + 0.5f});
          paths[size_t(k)].rect({f.width * 0.5f - x1, y, x1 - x0 + 0.5f, rowH + 0.5f});
        } else {
          paths[size_t(k)].rect({x0, y, x1 - x0 + 0.5f, rowH + 0.5f});
        }
      }
    }
    for (int k = 0; k < buckets; k++) {
      Paint p;
      p.color = ramp[size_t(k)];
      c.path(paths[size_t(k)], p);
    }
    // Brillo de la fila que está entrando; con Calor, cada golpe lo enciende.
    const float edgeH = std::max(1.0f, rowY(8.0f * rowU));
    Paint edgeGlow = Paint::linear({0, 0}, {0, edgeH}, {f.colors[3].opacity(std::clamp((0.25f + 0.3f * kick * calor) * amp, 0.0f, 1.0f)), f.colors[3].opacity(0.0f)});
    edgeGlow.blend = Blend::plus;
    c.rect({0, 0, f.width, edgeH}, edgeGlow);
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = f.colors[2].opacity(std::clamp(flash * 0.05f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
