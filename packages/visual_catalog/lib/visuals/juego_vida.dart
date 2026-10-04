// Juego de la Vida — el autómata de Conway en neón.
// Una rejilla de células que siguen las cuatro reglas de Conway: una célula
// viva con dos o tres vecinas sigue viva, una muerta con tres vecinas nace y
// el resto muere. Las recién nacidas brillan blanco-amarillo, las maduras en
// naranja y las veteranas en rojo; al morir dejan una brasa que se apaga. La
// rejilla se cierra sobre sí misma, así las naves que salen por un lado
// entran por el otro. La energía acelera las generaciones, cada golpe siembra
// una figura viva (naves, la R-pentominó, la bellota o una sopa) y, si la
// vida se estanca o se extingue, vuelve a sembrarse sola.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('tamano', 'Células a lo ancho', min: 24, max: 80, value: 46),
  CreatorModifier.slider('velocidad', 'Generaciones por segundo', min: .4, max: 2.5, value: 1),
  CreatorModifier.toggle('siembra', 'Siembra con los golpes', value: true),
  CreatorModifier.toggle('brasas', 'Brasas al morir', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxCols = 80;
  static constexpr int kMaxRows = 200;
  static constexpr int kMaxCells = kMaxCols * kMaxRows;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double gens = 0;
  int64_t done = 0;
  int cols = 0, rows = 0, quiet = 0;
  Random rng{1};
  std::vector<uint8_t> alive, next, age, ember;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  int at(int x, int y) const {
    x = (x % cols + cols) % cols;
    y = (y % rows + rows) % rows;
    return y * cols + x;
  }

  void soup(int x0, int y0, int w, int h, float density) {
    for (int y = y0; y < y0 + h; y++) {
      for (int x = x0; x < x0 + w; x++) {
        if (rng.unit() < density) {
          int i = at(x, y);
          alive[size_t(i)] = 1;
          age[size_t(i)] = 0;
        }
      }
    }
  }

  void stamp(int kind, int x0, int y0) {
    // Figuras clásicas: nave, R-pentominó, bellota, nave ligera.
    static const int glider[5][2] = {{1, 0}, {2, 1}, {0, 2}, {1, 2}, {2, 2}};
    static const int rpent[5][2] = {{1, 0}, {2, 0}, {0, 1}, {1, 1}, {1, 2}};
    static const int acorn[7][2] = {{1, 0}, {3, 1}, {0, 2}, {1, 2}, {4, 2}, {5, 2}, {6, 2}};
    static const int lwss[9][2] = {{1, 0}, {4, 0}, {0, 1}, {0, 2}, {4, 2}, {0, 3}, {1, 3}, {2, 3}, {3, 3}};
    auto put = [&](const int (*cells)[2], int count) {
      bool flipX = rng.unit() < 0.5f, flipY = rng.unit() < 0.5f;
      for (int k = 0; k < count; k++) {
        int i = at(x0 + (flipX ? -cells[k][0] : cells[k][0]), y0 + (flipY ? -cells[k][1] : cells[k][1]));
        alive[size_t(i)] = 1;
        age[size_t(i)] = 0;
      }
    };
    switch (kind) {
      case 0: put(glider, 5); put(glider, 5); break;
      case 1: put(rpent, 5); break;
      case 2: put(acorn, 7); break;
      case 3: put(lwss, 9); break;
      default: soup(x0 - 4, y0 - 4, 9, 9, 0.45f); break;
    }
  }

  void seedAll() {
    std::fill(alive.begin(), alive.end(), 0);
    std::fill(age.begin(), age.end(), 0);
    std::fill(ember.begin(), ember.end(), 0);
    soup(0, 0, cols, rows, 0.28f);
  }

  void step() {
    int born = 0, died = 0, population = 0;
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        int n = alive[size_t(at(x - 1, y - 1))] + alive[size_t(at(x, y - 1))] + alive[size_t(at(x + 1, y - 1))] +
                alive[size_t(at(x - 1, y))] + alive[size_t(at(x + 1, y))] +
                alive[size_t(at(x - 1, y + 1))] + alive[size_t(at(x, y + 1))] + alive[size_t(at(x + 1, y + 1))];
        int i = y * cols + x;
        uint8_t live = alive[size_t(i)] ? (n == 2 || n == 3) : (n == 3);
        next[size_t(i)] = live;
      }
    }
    for (int i = 0; i < cols * rows; i++) {
      if (next[size_t(i)]) {
        if (!alive[size_t(i)]) {
          age[size_t(i)] = 0;
          born++;
        } else if (age[size_t(i)] < 250) {
          age[size_t(i)]++;
        }
        ember[size_t(i)] = 0;
        population++;
      } else if (alive[size_t(i)]) {
        ember[size_t(i)] = 6;
        died++;
      } else if (ember[size_t(i)] > 0) {
        ember[size_t(i)]--;
      }
      alive[size_t(i)] = next[size_t(i)];
    }
    // Si la vida se apaga o se queda quieta, se vuelve a sembrar.
    int cells = cols * rows;
    quiet = (born + died) * 400 < cells ? quiet + 1 : 0;
    if (population * 60 < cells || quiet > 24) {
      for (int k = 0; k < 4; k++) stamp(int(rng.unit() * 5.0f) % 5, int(rng.unit() * float(cols)), int(rng.unit() * float(rows)));
      quiet = 0;
    }
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    gens = 0;
    done = 0;
    cols = rows = 0;
    quiet = 0;
    alive.assign(kMaxCells, 0);
    next.assign(kMaxCells, 0);
    age.assign(kMaxCells, 0);
    ember.assign(kMaxCells, 0);
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

    // Tamaño de la rejilla según la pantalla; si cambia, se siembra de nuevo.
    int c = std::clamp(m.tamano, 24, kMaxCols);
    float cell = f.width / float(c);
    int r = std::clamp(int(std::ceil(f.height / std::max(cell, 1.0f))), 1, kMaxRows);
    if (c != cols || r != rows) {
      cols = c;
      rows = r;
      seedAll();
    }
    if (beat && m.siembra) {
      int kind = int(rng.unit() * 5.0f) % 5;
      stamp(kind, int(rng.unit() * float(cols)), int(rng.unit() * float(rows)));
      if (hit > 0.75f) stamp(4, int(rng.unit() * float(cols)), int(rng.unit() * float(rows)));
    }
    gens += f.delta * f.speed * m.velocidad * (7.0 + 9.0 * drive);
    int64_t target = int64_t(std::floor(gens + 1e-6));
    if (target - done > 8) done = target - 8;
    while (done < target) {
      step();
      done++;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.75f,
                                                   {Color{std::min(1.0f, bg.r + f.colors[1].r * 0.06f), std::min(1.0f, bg.g + 0.01f), bg.b, 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    if (cols <= 0) return;
    float cell = f.width / float(cols);
    float gap = cell * 0.12f;
    // Cinco grupos: recién nacidas, jóvenes, veteranas y dos tonos de brasa.
    std::array<Path, 5> groups;
    std::array<std::vector<Vec2>, 3> glow;
    for (auto& g : glow) g.reserve(size_t(cols * rows / 4));
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        int i = y * cols + x;
        Rect r{float(x) * cell + gap, float(y) * cell + gap, cell - 2.0f * gap, cell - 2.0f * gap};
        if (alive[size_t(i)]) {
          int a = age[size_t(i)];
          int g = a < 2 ? 0 : (a < 7 ? 1 : 2);
          groups[size_t(g)].rect(r);
          glow[size_t(g)].push_back({r.x + r.width * 0.5f, r.y + r.height * 0.5f});
        } else if (m.brasas && ember[size_t(i)] > 0) {
          groups[ember[size_t(i)] > 3 ? 3 : 4].rect(r);
        }
      }
    }
    const Color& red = f.colors[1];
    const Color& orange = f.colors[2];
    const Color& hot = f.colors[3];
    std::array<Color, 5> cols5 = {hot, orange, red, Color{red.r * 0.55f, red.g * 0.3f, red.b * 0.3f, 1.0f},
                                  Color{red.r * 0.28f, red.g * 0.12f, red.b * 0.1f, 1.0f}};
    float lit = (0.85f + 0.3f * bass + 0.35f * kick) * amp;
    for (int g = 0; g < 3; g++) {
      Paint halo;
      halo.blend = Blend::plus;
      halo.color = cols5[size_t(g)].opacity(std::clamp((0.07f + 0.05f * bass) * f.glow * amp, 0.0f, 1.0f));
      c.points(glow[size_t(g)], cell * 1.1f, halo);
    }
    for (int g = 4; g >= 0; g--) {
      Paint p;
      const Color& col = cols5[size_t(g)];
      float k = g < 3 ? lit : amp;
      p.color = {std::min(1.0f, col.r * k), std::min(1.0f, col.g * k), std::min(1.0f, col.b * k), 1.0f};
      c.path(groups[size_t(g)], p);
    }
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = orange.opacity(std::clamp(flash * 0.05f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
