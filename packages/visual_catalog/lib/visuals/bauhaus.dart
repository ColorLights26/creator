// Bauhaus — un póster de formas geométricas que baila.
// La pantalla es una retícula de celdas cuadradas, cada una con un fondo y
// una figura plana: círculo, media luna, cuarto de círculo, cuadrado,
// triángulo, franjas, anillo o puntos, en rojo, amarillo, azul, negro y
// crema, como en los carteles de la Bauhaus. Con cada golpe algunas celdas
// cambian: la figura gira un cuarto de vuelta con rebote, o se encoge y
// vuelve convertida en otra forma de otro color. Sin música cambian solas a
// ritmo tranquilo. Los graves hacen respirar todas las figuras. La agitación
// decide cuántas celdas cambian: de un póster quieto en el que sólo una
// figura se mueve a la vez, a uno que se baraja casi entero con cada golpe.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('columnas', 'Columnas', min: 2, max: 6, value: 3),
  CreatorModifier.slider('ritmo', 'Agitación', min: .3, max: 2.5, value: 1),
  CreatorModifier.toggle('lineas', 'Líneas negras', value: true),
  CreatorModifier.toggle('negro', 'Usar negro', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxCells = 6 * 16;
  static constexpr int kShapes = 8;
  struct Cell { int bg, shape, color, turns; int nShape, nColor, nBg; double start; int mode; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, idle = 0;
  int cols = 0, rows = 0;
  bool useBlack = true;
  Random rng{1};
  std::array<Cell, kMaxCells> cells{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  int randomColor(int avoid) {
    int n = useBlack ? 5 : 4;
    int c = std::min(int(rng.unit() * float(n)), n - 1);
    if (c == avoid) c = (c + 1 + std::min(int(rng.unit() * float(n - 1)), n - 2)) % n;
    return c;
  }

  void randomize(Cell& c) {
    c.bg = std::min(int(rng.unit() * 5.0f), 4);
    if (!useBlack && c.bg == 4) c.bg = 0;
    if (rng.unit() < 0.45f) c.bg = 0;
    c.shape = std::min(int(rng.unit() * float(kShapes)), kShapes - 1);
    c.color = randomColor(c.bg);
    c.turns = std::min(int(rng.unit() * 4.0f), 3);
    c.mode = 0;
    c.start = -10;
  }

  // Una celda al azar que no esté a medio cambio, para que ninguna salte.
  int pickIdle(int count) {
    int first = std::min(int(rng.unit() * float(count)), count - 1);
    for (int k = 0; k < count; k++) {
      int i = (first + k) % count;
      if (cells[size_t(i)].mode == 0) return i;
    }
    return first;
  }

  // Cambio de una celda: girar, o encoger y volver con otra forma.
  void change(int i, double when) {
    Cell& c = cells[size_t(i)];
    finish(c);
    c.start = when;
    if (rng.unit() < 0.45f) {
      c.mode = 1;
    } else {
      c.mode = 2;
      c.nShape = std::min(int(rng.unit() * float(kShapes)), kShapes - 1);
      c.nBg = rng.unit() < 0.5f ? c.bg : std::min(int(rng.unit() * (useBlack ? 5.0f : 4.0f)), useBlack ? 4 : 3);
      c.nColor = randomColor(c.nBg);
    }
  }

  void finish(Cell& c) {
    if (c.mode == 1) c.turns = (c.turns + 1) % 4;
    if (c.mode == 2) {
      c.shape = c.nShape;
      c.color = c.nColor;
      c.bg = c.nBg;
    }
    c.mode = 0;
  }

  Color colorOf(const Frame& f, int k) const {
    if (k == 4) return Color{0.07f, 0.07f, 0.08f, 1.0f};
    return f.colors[size_t(k)];
  }

  static float easeBack(float t) {
    const float s = 1.9f;
    t -= 1.0f;
    return t * t * ((s + 1.0f) * t + s) + 1.0f;
  }

  void shapePath(Path& p, int shape, float h) const {
    auto arc = [&](float cx, float cy, float r, float a0, float a1, bool first) {
      const int n = 24;
      for (int k = 0; k <= n; k++) {
        float a = a0 + (a1 - a0) * float(k) / float(n);
        float x = cx + r * std::cos(a), y = cy + r * std::sin(a);
        if (first && k == 0) p.moveTo(x, y); else p.lineTo(x, y);
      }
    };
    switch (shape) {
      case 0: p.circle({0, 0}, h * 0.78f); break;
      case 1: arc(0, h, h, 3.14159265f, 6.2831853f, true); p.close(); break;
      case 2: p.moveTo(-h, h); arc(-h, h, h * 2.0f, -1.5707963f, 0.0f, false); p.close(); break;
      case 3: p.rect({-h * 0.55f, -h * 0.55f, h * 1.1f, h * 1.1f}); break;
      case 4: p.moveTo(-h, -h).lineTo(h, h).lineTo(-h, h).close(); break;
      case 5:
        for (int k = 0; k < 3; k++) p.rect({-h, -h + float(k) * h * 0.7f + h * 0.1f, h * 2.0f, h * 0.38f});
        break;
      case 6:
        p.fillRule = FillRule::evenOdd;
        p.circle({0, 0}, h * 0.8f);
        p.circle({0, 0}, h * 0.42f);
        break;
      default:
        for (int k = 0; k < 4; k++) p.circle({(k % 2 == 0 ? -0.45f : 0.45f) * h, (k < 2 ? -0.45f : 0.45f) * h}, h * 0.3f);
        break;
    }
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = 0;
    idle = 0;
    cols = rows = 0;
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

    int c = std::clamp(m.columnas, 2, 6);
    float size = f.width / float(c);
    int r = std::clamp(int(std::ceil(f.height / size)), 1, kMaxCells / c);
    if (c != cols || r != rows || m.negro != useBlack) {
      cols = c;
      rows = r;
      useBlack = m.negro;
      for (int i = 0; i < cols * rows; i++) randomize(cells[size_t(i)]);
    }
    clock += f.delta * f.speed;
    int count = cols * rows;
    // Agitación: cuántas celdas cambia cada golpe (con música) y cada cuánto
    // cambia una sola (sin música).
    if (beat) {
      int n = std::clamp(int(std::lround(float(1 + int(hit * 3.0f)) * m.ritmo)), 1, count);
      for (int k = 0; k < n; k++) change(pickIdle(count), clock);
    }
    // Sin música, un cambio a ritmo tranquilo, en su instante exacto.
    double period = 0.7 / double(m.ritmo);
    idle += f.delta * f.speed;
    while (idle >= period) {
      idle -= period;
      if (!mu.active) change(pickIdle(count), clock - idle);
    }
    for (int i = 0; i < count; i++) {
      Cell& cell = cells[size_t(i)];
      if (cell.mode != 0 && clock - cell.start >= 0.5) finish(cell);
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    Paint paper;
    paper.color = colorOf(f, 0);
    c.rect({0, 0, f.width, f.height}, paper);
    if (cols <= 0) return;
    float size = f.width / float(cols);
    float top = (f.height - float(rows) * size) * 0.5f;
    float h = size * 0.5f;
    for (int i = 0; i < cols * rows; i++) {
      const Cell& cell = cells[size_t(i)];
      float x = float(i % cols) * size, y = top + float(i / cols) * size;
      float t = cell.mode != 0 ? std::clamp(float((clock - cell.start) / 0.5), 0.0f, 1.0f) : 1.0f;
      int bg = cell.bg, shape = cell.shape, color = cell.color;
      float angle = float(cell.turns) * 1.5707963f;
      float s = 1.0f;
      if (cell.mode == 1) {
        angle += 1.5707963f * easeBack(t);
      } else if (cell.mode == 2) {
        if (t < 0.4f) {
          s = 1.0f - t / 0.4f;
        } else {
          bg = cell.nBg;
          shape = cell.nShape;
          color = cell.nColor;
          s = easeBack((t - 0.4f) / 0.6f);
        }
      }
      Paint bp;
      bp.color = colorOf(f, bg);
      c.rect({x, y, size + 0.5f, size + 0.5f}, bp);
      c.save();
      Path clip;
      clip.rect({x, y, size, size});
      c.clip(clip);
      c.translate(x + h, y + h);
      c.rotate(angle);
      float breathe = 1.0f + 0.05f * bass * amp;
      c.scale(s * breathe, s * breathe);
      Path p;
      shapePath(p, shape, h);
      Paint sp;
      sp.color = colorOf(f, color);
      c.path(p, sp);
      c.restore();
    }
    if (m.lineas) {
      Path grid;
      for (int k = 0; k <= cols; k++) grid.moveTo(float(k) * size, 0).lineTo(float(k) * size, f.height);
      for (int k = 0; k <= rows; k++) grid.moveTo(0, top + float(k) * size).lineTo(f.width, top + float(k) * size);
      Paint gp;
      gp.strokeWidth = std::max(1.5f, size * 0.025f);
      gp.color = Color{0.07f, 0.07f, 0.08f, 1.0f};
      c.path(grid, gp);
    }
    if (flash > 0.01f) {
      Paint fl;
      fl.color = Color{1.0f, 1.0f, 1.0f, std::clamp(flash * 0.06f * amp, 0.0f, 1.0f)};
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
