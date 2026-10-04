// Tablero de Galton Transparente — el azar dibuja la campana de Gauss.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Bolas que caen desde arriba por un triángulo de clavos: en cada fila
// rebotan a la izquierda o a la derecha al azar y acaban en una de las
// casillas de abajo, donde se apilan. Aunque cada bola es impredecible, el
// montón forma siempre la misma campana; una línea de luz muestra la forma
// teórica. Las bolas cambian de color cada pocos segundos (o en cada golpe),
// así el montón queda en capas de colores. Cuando una casilla se llena, el
// suelo se abre y todo cae. La energía hace caer más bolas, cada golpe suelta
// una ráfaga y los graves hacen brillar los clavos.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('filas', 'Filas de clavos', min: 8, max: 16, value: 12),
  CreatorModifier.slider('caudal', 'Bolas por segundo', min: .4, max: 2.5, value: 1),
  CreatorModifier.choice('color', 'Color', options: ['Por capas', 'Por casilla', 'Arcoíris']),
  CreatorModifier.toggle('curva', 'Curva teórica', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxBins = 17;
  static constexpr int kSlots = 420;
  static constexpr int kActive = 360;
  struct Ball { double t0; uint32_t path; int bin, slot; uint8_t color; bool landed; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, emitted = 0, drainStart = -100, colorClock = 0;
  int rowsUsed = 0, layer = 0, burst = 0;
  Random rng{1};
  std::vector<Ball> balls;
  std::array<int, kMaxBins> count{}, drainCount{};
  std::array<std::array<uint8_t, kSlots>, kMaxBins> colorOf{}, drainColor{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static constexpr double kDrop = 0.14, kHop = 0.085, kFall = 0.32;

  int binOf(uint32_t path, int rows) const {
    int j = 0;
    for (int r = 0; r < rows; r++) j += int((path >> r) & 1u);
    return j;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = 0;
    emitted = 0;
    drainStart = -100;
    colorClock = 0;
    rowsUsed = 0;
    layer = 0;
    burst = 0;
    balls.clear();
    balls.reserve(kActive);
    count.fill(0);
    drainCount.fill(0);
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
    bool beat = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    int rows = std::clamp(m.filas, 4, kMaxBins - 1);
    if (rows != rowsUsed) {
      rowsUsed = rows;
      balls.clear();
      count.fill(0);
      drainCount.fill(0);
    }
    double step = f.delta * f.speed;
    clock += step;
    // Color por capas: cambia cada 2,5 s o con un golpe.
    colorClock += step;
    if (beat) {
      layer++;
      colorClock = 0;
      burst += 6 + int(8.0f * hit);
    }
    while (colorClock >= 2.5) {
      colorClock -= 2.5;
      layer++;
    }
    double rate = 16.0 * double(m.caudal) * (1.0 + 1.5 * double(drive));
    double before = emitted;
    emitted += step * rate;
    // Nacimientos en su instante exacto dentro del frame.
    for (double k = std::floor(before) + 1.0; k <= emitted + 1e-9; k += 1.0) {
      if (int(balls.size()) >= kActive) break;
      double t0 = clock - (emitted - k) / rate;
      balls.push_back({t0, rng.next(), 0, 0, uint8_t(layer % 6), false});
    }
    while (burst > 0 && int(balls.size()) < kActive) {
      balls.push_back({clock - 0.02 * double(burst), rng.next(), 0, 0, uint8_t(layer % 6), false});
      burst--;
    }
    burst = 0;

    // Al entrar en su casilla la bola reserva su hueco del montón.
    double entry = kDrop + double(rows) * kHop;
    std::sort(balls.begin(), balls.end(), [](const Ball& a, const Ball& b) { return a.t0 < b.t0; });
    // Capacidad real de una casilla según el tamaño de la pantalla.
    float px = std::min(f.width, f.height) / 400.0f;
    float binW = f.width * 0.92f / float(rows + 1);
    float ballR = std::min(binW * 0.16f, 5.5f * px);
    int perRow = std::max(1, int(binW * 0.9f / (2.0f * ballR)));
    int capacity = std::min(kSlots, perRow * int((f.height * (0.965f - 0.55f)) / (1.85f * ballR)));
    for (auto& b : balls) {
      if (b.landed || clock - b.t0 < entry) continue;
      double when = b.t0 + entry;
      b.bin = binOf(b.path, rows);
      if (count[size_t(b.bin)] >= capacity) {
        // Casilla llena: el suelo se abre y el montón cae.
        drainCount = count;
        drainColor = colorOf;
        drainStart = when;
        count.fill(0);
      }
      b.slot = count[size_t(b.bin)]++;
      colorOf[size_t(b.bin)][size_t(b.slot)] = b.color;
      b.landed = true;
    }
    // Las que ya terminaron de caer pasan a ser parte del montón.
    balls.erase(std::remove_if(balls.begin(), balls.end(), [&](const Ball& b) { return b.landed && clock - b.t0 > entry + kFall; }),
                balls.end());
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    int rows = rowsUsed;
    if (rows <= 0) return;
    int bins = rows + 1;
    float px = std::min(f.width, f.height) / 400.0f;
    float binW = f.width * 0.92f / float(bins);
    float cx = f.width * 0.5f;
    float pegTop = f.height * 0.13f, pegBottom = f.height * 0.5f;
    float dy = (pegBottom - pegTop) / float(rows);
    float binTop = f.height * 0.55f, binBottom = f.height * 0.965f;
    float ballR = std::min(binW * 0.16f, 5.5f * px);
    int perRow = std::max(1, int(binW * 0.9f / (2.0f * ballR)));
    std::array<Color, 6> layers = {f.colors[1], f.colors[2], f.colors[3], Color{1.0f, 0.35f, 0.55f, 1.0f},
                                   Color{1.0f, 0.97f, 0.88f, 1.0f}, Color{1.0f, 0.55f, 0.1f, 1.0f}};
    auto ballColor = [&](uint8_t layerIdx, int bin) {
      if (m.color == 1) {
        float t = float(bin) / float(bins - 1);
        const Color& a = f.colors[1];
        const Color& b = f.colors[3];
        float u = 1.0f - std::fabs(t - 0.5f) * 2.0f;
        return Color{a.r + (b.r - a.r) * u, a.g + (b.g - a.g) * u, a.b + (b.b - a.b) * u, 1.0f};
      }
      if (m.color == 2) {
        float h = float(layerIdx) / 6.0f;
        float r = std::clamp(std::fabs(h * 6.0f - 3.0f) - 1.0f, 0.0f, 1.0f);
        float g = std::clamp(2.0f - std::fabs(h * 6.0f - 2.0f), 0.0f, 1.0f);
        float bl = std::clamp(2.0f - std::fabs(h * 6.0f - 4.0f), 0.0f, 1.0f);
        return Color{r, g, bl, 1.0f};
      }
      return layers[size_t(layerIdx % 6)];
    };
    auto slotPos = [&](int bin, int slot) {
      int row = slot / perRow, col = slot % perRow;
      float left = cx + (float(bin) - float(bins) * 0.5f) * binW + (binW - float(perRow) * 2.0f * ballR) * 0.5f;
      float x = left + ballR + float(col) * 2.0f * ballR + ((row & 1) ? ballR * 0.5f : 0.0f);
      return Vec2{std::min(x, cx + (float(bin) - float(bins) * 0.5f + 1.0f) * binW - ballR), binBottom - ballR - float(row) * 1.8f * ballR};
    };

    // Casillas: paredes finas y suelo.
    Path walls;
    for (int b = 0; b <= bins; b++) {
      float x = cx + (float(b) - float(bins) * 0.5f) * binW;
      walls.moveTo(x, binTop).lineTo(x, binBottom);
    }
    walls.moveTo(cx - float(bins) * 0.5f * binW, binBottom).lineTo(cx + float(bins) * 0.5f * binW, binBottom);
    Paint wp;
    wp.strokeWidth = 1.4f * px;
    wp.color = Color{0.75f, 0.72f, 0.78f, 0.35f};
    c.path(walls, wp);
    // Clavos.
    std::vector<Vec2> pegs;
    pegs.reserve(size_t((rows + 1) * (rows + 2) / 2));
    for (int r = 0; r < rows; r++) {
      for (int k = 0; k <= r; k++) pegs.push_back({cx + (float(k) - float(r) * 0.5f) * binW, pegTop + float(r) * dy});
    }
    Paint pegGlow;
    pegGlow.blend = Blend::plus;
    pegGlow.color = f.colors[2].opacity(std::clamp((0.1f + 0.25f * bass + 0.2f * kick) * f.glow * amp, 0.0f, 1.0f));
    c.points(pegs, 5.5f * px, pegGlow);
    Paint pegDot;
    pegDot.color = Color{0.86f, 0.84f, 0.9f, 1.0f};
    c.points(pegs, 2.2f * px, pegDot);

    // Montón actual y el que se vacía.
    std::array<std::vector<Vec2>, 8> groups;
    std::array<Color, 8> groupColor{};
    for (auto& g : groups) g.reserve(512);
    auto add = [&](Vec2 p, Color col) {
      // Agrupa por color cuantizado: hasta 8 grupos por frame.
      for (int g = 0; g < 8; g++) {
        if (groups[size_t(g)].empty()) {
          groupColor[size_t(g)] = col;
          groups[size_t(g)].push_back(p);
          return;
        }
        const Color& gc = groupColor[size_t(g)];
        if (std::fabs(gc.r - col.r) + std::fabs(gc.g - col.g) + std::fabs(gc.b - col.b) < 0.08f) {
          groups[size_t(g)].push_back(p);
          return;
        }
      }
      groups[7].push_back(p);
    };
    for (int b = 0; b < bins; b++) {
      for (int s = 0; s < count[size_t(b)]; s++) add(slotPos(b, s), ballColor(colorOf[size_t(b)][size_t(s)], b));
    }
    float drainT = float(clock - drainStart);
    if (drainT >= 0.0f && drainT < 1.2f) {
      float drop = 0.5f * 2600.0f * px * drainT * drainT;
      for (int b = 0; b < bins; b++) {
        for (int s = 0; s < drainCount[size_t(b)]; s++) {
          Vec2 p = slotPos(b, s);
          p.y += drop * (1.0f + 0.002f * float(s));
          if (p.y < f.height + ballR) add(p, ballColor(drainColor[size_t(b)][size_t(s)], b));
        }
      }
    }
    // Bolas en el aire.
    double entry = kDrop + double(rows) * kHop;
    std::vector<Vec2> flying;
    flying.reserve(balls.size());
    for (const auto& b : balls) {
      double age = clock - b.t0;
      if (age < 0.0) continue;
      Vec2 p;
      if (age < kDrop) {
        float t = float(age / kDrop);
        p = {cx, pegTop - dy * 1.4f + dy * 1.4f * t * t - ballR * 2.0f};
      } else if (age < entry) {
        double u = (age - kDrop) / kHop;
        int level = int(u);
        float t = float(u - double(level));
        int j0 = 0;
        for (int r = 0; r < level; r++) j0 += int((b.path >> r) & 1u);
        int j1 = j0 + int((b.path >> level) & 1u);
        float x0 = cx + (float(j0) - float(level) * 0.5f) * binW;
        float x1 = cx + (float(j1) - float(level + 1) * 0.5f) * binW;
        float y0 = pegTop + float(level) * dy - ballR * 2.0f;
        float y1 = y0 + dy;
        p = {x0 + (x1 - x0) * t, y0 + (y1 - y0) * t * t - dy * 0.55f * std::sin(t * 3.14159265f)};
      } else {
        float t = std::min(float((age - entry) / kFall), 1.0f);
        int bin = binOf(b.path, rows);
        float x0 = cx + (float(bin) - float(rows) * 0.5f) * binW;
        Vec2 target = b.landed ? slotPos(b.bin, b.slot) : Vec2{x0, binBottom - ballR};
        float y0 = pegTop + float(rows) * dy - ballR * 2.0f;
        p = {x0 + (target.x - x0) * t, y0 + (target.y - y0) * t * t};
      }
      add(p, ballColor(b.color, binOf(b.path, rows)));
      flying.push_back(p);
    }
    float lit = (0.85f + 0.2f * bass + 0.25f * kick) * amp;
    for (int g = 0; g < 8; g++) {
      if (groups[size_t(g)].empty()) continue;
      const Color& col = groupColor[size_t(g)];
      Paint p;
      p.color = Color{std::min(1.0f, col.r * lit), std::min(1.0f, col.g * lit), std::min(1.0f, col.b * lit), 1.0f};
      c.points(groups[size_t(g)], ballR * 0.92f, p);
    }
    Paint shine;
    shine.blend = Blend::plus;
    shine.color = Color{1.0f, 0.95f, 0.85f, std::clamp(0.35f * amp, 0.0f, 1.0f)};
    c.points(flying, ballR * 0.45f, shine);
    // Curva teórica: la campana que el montón va dibujando.
    if (m.curva) {
      int total = 0;
      for (int b = 0; b < bins; b++) total += count[size_t(b)];
      if (total > bins) {
        Path curve;
        double mean = double(rows) * 0.5, var = double(rows) * 0.25;
        for (int i = 0; i <= 80; i++) {
          double xb = double(i) / 80.0 * double(bins) - 0.5;
          double expect = double(total) * std::exp(-(xb - mean) * (xb - mean) / (2.0 * var)) / std::sqrt(6.283185307 * var);
          float h = float(expect) / float(perRow) * 1.8f * ballR;
          float x = cx + (float(xb) + 0.5f - float(bins) * 0.5f) * binW;
          float y = binBottom - h;
          if (i == 0) curve.moveTo(x, y); else curve.lineTo(x, y);
        }
        Paint cp;
        cp.blend = Blend::plus;
        cp.strokeWidth = 2.0f * px;
        cp.strokeJoin = 1;
        cp.color = Color{1.0f, 1.0f, 1.0f, std::clamp((0.35f + 0.3f * kick) * amp, 0.0f, 1.0f)};
        c.path(curve, cp);
      }
    }
  }
};
''';
