// Tablero de Galton — el azar dibuja la campana de Gauss.
// Bolas que caen desde arriba por un triángulo de clavos: en cada fila
// rebotan a la izquierda o a la derecha al azar y acaban en una de las
// casillas de abajo, donde se apilan. Aunque cada bola es impredecible, el
// montón forma siempre la misma campana; una línea de luz muestra la forma
// teórica. Las bolas cambian de color cada pocos segundos (o en cada golpe),
// así el montón queda en capas de colores. Con estela, cada bola deja su
// camino de luz, como una foto de larga exposición. Cuando una casilla se
// llena, el suelo se abre y todo cae. La energía hace caer más bolas, cada
// golpe suelta una ráfaga y los graves hacen brillar los clavos.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('filas', 'Filas de clavos', min: 8, max: 16, value: 12),
  CreatorModifier.slider('caudal', 'Bolas por segundo', min: .4, max: 2.5, value: 1),
  // ATMÓSFERA: de bolas nítidas (0) a una larga exposición donde cada bola
  // deja encendido el zigzag que acaba de recorrer (1).
  CreatorModifier.slider('estela', 'Estela', min: 0, max: 1, value: .25),
  CreatorModifier.toggle('curva', 'Curva teórica', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxBins = 17;
  static constexpr int kSlots = 420;
  static constexpr int kActive = 480;
  struct Ball { double t0; uint32_t path; int bin, slot; uint8_t color; bool landed; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // La simulación avanza en pasos fijos de 1/120 s contados con enteros:
  // nacimientos, aterrizajes y capas de color caen en el mismo paso a 30 y a
  // 60 FPS. El reloj continuo sólo sitúa las bolas en el dibujo.
  static constexpr double kTick = 1.0 / 120.0;
  static constexpr int kLayerTicks = 300;  // una capa de color cada 2,5 s
  double clock = 0, emitted = 0, drainStart = -100;
  int64_t ticks = 0;
  int colorTicks = 0;
  int rowsUsed = 0, layer = 0, burst = 0;
  uint32_t seedBase = 1, born = 0;
  std::vector<Ball> balls;
  std::array<int, kMaxBins> count{}, drainCount{};
  std::array<std::array<uint8_t, kSlots>, kMaxBins> colorOf{}, drainColor{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static constexpr double kDrop = 0.14, kHop = 0.085, kFall = 0.32;
  // Una bola que ya descansa sigue un rato en la lista: su estela se recoge.
  static constexpr double kTrailMax = 0.6;

  int binOf(uint32_t path, int rows) const {
    int j = 0;
    for (int r = 0; r < rows; r++) j += int((path >> r) & 1u);
    return j;
  }

  // Camino de la bola número [serial]: un bit por fila (izquierda o derecha).
  // Es una fórmula de la semilla, sin Random fuera de reset.
  uint32_t pathOf(uint32_t serial) const {
    uint32_t x = seedBase ^ (serial * 0x9E3779B9u);
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
  }

 public:
  void reset(uint32_t seed) override {
    seedBase = seed ? seed : 1u;
    born = 0;
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = 0;
    ticks = 0;
    emitted = 0;
    drainStart = -100;
    colorTicks = 0;
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
    clock += f.delta * f.speed;
    // Un golpe empieza una capa de color nueva y suelta una ráfaga.
    if (beat) {
      layer++;
      colorTicks = 0;
      burst += 6 + int(8.0f * hit);
    }
    const double rate = 16.0 * double(m.caudal) * (1.0 + 1.5 * double(drive));
    const double entry = kDrop + double(rows) * kHop;
    // Capacidad real de una casilla según el tamaño de la pantalla.
    float px = std::min(f.width, f.height) / 400.0f;
    float binW = f.width * 0.92f / float(rows + 1);
    float ballR = std::min(binW * 0.16f, 5.5f * px);
    int perRow = std::max(1, int(binW * 0.9f / (2.0f * ballR)));
    int capacity = std::min(kSlots, perRow * int((f.height * (0.965f - 0.55f)) / (1.85f * ballR)));

    const int64_t target = int64_t(std::floor(clock / kTick + 1e-6));
    // Tras un salto largo no se pone al día bola a bola.
    if (target - ticks > 240) ticks = target - 240;
    while (ticks < target) {
      ticks++;
      const double now = double(ticks) * kTick;
      // Color por capas: cambia cada 2,5 s (o con un golpe, arriba).
      if (++colorTicks >= kLayerTicks) {
        colorTicks = 0;
        layer++;
      }
      // Nacimientos en su instante exacto dentro del paso.
      const double before = emitted;
      emitted += kTick * rate;
      for (double k = std::floor(before) + 1.0; k <= emitted + 1e-9; k += 1.0) {
        if (int(balls.size()) >= kActive) break;
        balls.push_back({now - (emitted - k) / rate, pathOf(born++), 0, 0, uint8_t(layer % 6), false});
      }
      // Al entrar en su casilla la bola reserva su hueco del montón.
      for (auto& b : balls) {
        if (b.landed || now - b.t0 < entry) continue;
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
    }
    // Las que ya descansan en el montón (y recogieron su estela) se van.
    const double now = double(ticks) * kTick;
    balls.erase(std::remove_if(balls.begin(), balls.end(),
                               [&](const Ball& b) { return b.landed && now - b.t0 > entry + kFall + kTrailMax; }),
                balls.end());
    // Ráfaga del golpe: bolas que ya van en camino, en orden de salida.
    if (burst > 0) {
      while (burst > 0 && int(balls.size()) < kActive) {
        balls.push_back({clock - 0.02 * double(burst), pathOf(born++), 0, 0, uint8_t(layer % 6), false});
        burst--;
      }
      burst = 0;
      std::stable_sort(balls.begin(), balls.end(), [](const Ball& a, const Ball& b) { return a.t0 < b.t0; });
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto g = glide(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::linear({0, 0}, {0, f.height},
                                                   {Color{std::min(1.0f, bg.r + 0.05f), std::min(1.0f, bg.g + 0.035f), std::min(1.0f, bg.b + 0.06f), 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
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
    // Tiempo de la simulación: decide qué ya pasó; el reloj continuo, dónde se ve.
    const double simNow = double(ticks) * kTick;
    std::array<Color, 6> layers = {f.colors[1], f.colors[2], f.colors[3], Color{1.0f, 0.35f, 0.55f, 1.0f},
                                   Color{1.0f, 0.97f, 0.88f, 1.0f}, Color{1.0f, 0.55f, 0.1f, 1.0f}};
    auto ballColor = [&](uint8_t layerIdx) { return layers[size_t(layerIdx % 6)]; };
    auto slotPos = [&](int bin, int slot) {
      int row = slot / perRow, col = slot % perRow;
      float left = cx + (float(bin) - float(bins) * 0.5f) * binW + (binW - float(perRow) * 2.0f * ballR) * 0.5f;
      float x = left + ballR + float(col) * 2.0f * ballR + ((row & 1) ? ballR * 0.5f : 0.0f);
      return Vec2{std::min(x, cx + (float(bin) - float(bins) * 0.5f + 1.0f) * binW - ballR), binBottom - ballR - float(row) * 1.8f * ballR};
    };
    double entry = kDrop + double(rows) * kHop;
    // Dónde está una bola a cualquier edad: la usan la bola y su estela.
    auto ballAt = [&](const Ball& b, double age) {
      Vec2 p;
      if (age < kDrop) {
        float t = float(age / kDrop);
        p = {cx, pegTop - dy * 1.4f + dy * 1.4f * t * t - ballR * 2.0f};
      } else if (age < entry) {
        double u = (age - kDrop) / kHop;
        int level = std::min(int(u), rows - 1);
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
      return p;
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

    // Estela: el camino reciente de cada bola, en muestras fijas de su propio
    // recorrido (no tiemblan) y en tres tramos que se apagan hacia atrás.
    const float trail = std::clamp(g.estela, 0.0f, 1.0f);
    if (trail > 0.02f) {
      std::array<Path, 18> streaks;  // 6 colores × 3 tramos
      const double h = kHop * 0.25;
      const int window = std::max(1, int(std::ceil(kTrailMax * double(trail) / h)));
      for (const auto& b : balls) {
        const double age = std::max(0.0, clock - b.t0);
        const int qHi = int(std::floor(age / h + 1e-6));
        const int qLo = std::max(0, qHi - window);
        if (qHi <= qLo) continue;
        Vec2 prev = ballAt(b, age);
        int open = -1;
        for (int q = qHi; q >= qLo; q--) {
          const int part = std::min(2, (qHi - q) * 3 / window);
          Path& path = streaks[size_t(b.color % 6) * 3 + size_t(part)];
          if (part != open) {
            path.moveTo(prev.x, prev.y);
            open = part;
          }
          const Vec2 p = ballAt(b, double(q) * h);
          path.lineTo(p.x, p.y);
          prev = p;
        }
      }
      const float strength = (0.3f + 0.4f * trail) * std::min(1.0f, 0.6f + 0.4f * f.glow);
      for (size_t i = 0; i < streaks.size(); i++) {
        if (streaks[i].data().empty()) continue;
        const float part = float(i % 3);
        Paint sp;
        sp.strokeWidth = ballR * (0.95f - 0.2f * part);
        sp.strokeCap = 1;
        sp.strokeJoin = 1;
        sp.color = ballColor(uint8_t(i / 3)).opacity(std::clamp(strength * (1.0f - 0.32f * part), 0.0f, 1.0f));
        c.path(streaks[i], sp);
      }
    }

    // Montón actual y el que se vacía.
    std::array<std::vector<Vec2>, 8> groups;
    std::array<Color, 8> groupColor{};
    for (auto& gr : groups) gr.reserve(512);
    auto add = [&](Vec2 p, Color col) {
      // Agrupa por color cuantizado: hasta 8 grupos por frame.
      for (int i = 0; i < 8; i++) {
        if (groups[size_t(i)].empty()) {
          groupColor[size_t(i)] = col;
          groups[size_t(i)].push_back(p);
          return;
        }
        const Color& gc = groupColor[size_t(i)];
        if (std::fabs(gc.r - col.r) + std::fabs(gc.g - col.g) + std::fabs(gc.b - col.b) < 0.08f) {
          groups[size_t(i)].push_back(p);
          return;
        }
      }
      groups[7].push_back(p);
    };
    for (int b = 0; b < bins; b++) {
      for (int s = 0; s < count[size_t(b)]; s++) add(slotPos(b, s), ballColor(colorOf[size_t(b)][size_t(s)]));
    }
    if (simNow - drainStart < 1.2) {
      float drainT = float(std::max(0.0, clock - drainStart));
      float drop = 0.5f * 2600.0f * px * drainT * drainT;
      for (int b = 0; b < bins; b++) {
        for (int s = 0; s < drainCount[size_t(b)]; s++) {
          Vec2 p = slotPos(b, s);
          p.y += drop * (1.0f + 0.002f * float(s));
          if (p.y < f.height + ballR) add(p, ballColor(drainColor[size_t(b)][size_t(s)]));
        }
      }
    }
    // Bolas en el aire (las que ya descansan se dibujan en el montón).
    std::vector<Vec2> flying;
    flying.reserve(balls.size());
    for (const auto& b : balls) {
      if (b.landed && simNow - b.t0 > entry + kFall) continue;
      Vec2 p = ballAt(b, std::max(0.0, clock - b.t0));
      add(p, ballColor(b.color));
      flying.push_back(p);
    }
    float lit = (0.85f + 0.2f * bass + 0.25f * kick) * amp;
    for (int i = 0; i < 8; i++) {
      if (groups[size_t(i)].empty()) continue;
      const Color& col = groupColor[size_t(i)];
      Paint p;
      p.color = Color{std::min(1.0f, col.r * lit), std::min(1.0f, col.g * lit), std::min(1.0f, col.b * lit), 1.0f};
      c.points(groups[size_t(i)], ballR * 0.92f, p);
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
          float hgt = float(expect) / float(perRow) * 1.8f * ballR;
          float x = cx + (float(xb) + 0.5f - float(bins) * 0.5f) * binW;
          float y = binBottom - hgt;
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
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = f.colors[2].opacity(std::clamp(flash * 0.05f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
