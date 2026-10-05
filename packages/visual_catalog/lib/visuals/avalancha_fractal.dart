// Avalancha Fractal — el montón de arena abeliano dibuja un mandala.
// Se dejan caer granos en el centro de una rejilla. Cuando una celda junta
// cuatro granos se derrumba y reparte uno a cada vecina, que a su vez puede
// derrumbarse, en avalanchas que pueden recorrer todo el montón. De esa regla
// tan simple crece un dibujo fractal con simetría perfecta: cada celda se
// pinta según le queden 0, 1, 2 ó 3 granos. Los granos caen a ritmo
// constante, la energía los multiplica y cada golpe deja caer un puñado que
// hace crecer el mandala de golpe. Cuando llega al borde se apaga y empieza
// otro, con una, dos o cuatro semillas. La textura cambia el material del
// mandala: mosaico de teselas, cuentas redondas como un bordado de chaquira, o
// encaje, donde sólo quedan los bordes de cada zona y las zonas lisas se vacían.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('grano', 'Tamaño de grano', min: 1, max: 4, value: 2),
  CreatorModifier.slider('caudal', 'Caudal', min: .3, max: 3, value: 1),
  CreatorModifier.choice('semillas', 'Semillas', options: ['Auto', 'Una', 'Dos', 'Cuatro']),
  // ATMÓSFERA: el material del mandala.
  CreatorModifier.choice('textura', 'Textura', options: ['Mosaico', 'Cuentas', 'Encaje']),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxCells = 30000;
  static constexpr double kStep = 1.0 / 60.0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double sim = 0, fadeStart = -1;
  int64_t steps = 0;
  int w = 0, h = 0, cellMode = 0, seedsUsed = 1, cycle = 0, burst = 0;
  float grainAcc = 0;
  std::vector<uint32_t> grid;
  std::vector<int> stack;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void drop(int cell, uint32_t grains) {
    grid[size_t(cell)] += grains;
    if (grid[size_t(cell)] >= 4) stack.push_back(cell);
    while (!stack.empty()) {
      int c = stack.back();
      stack.pop_back();
      uint32_t v = grid[size_t(c)];
      if (v < 4) continue;
      uint32_t q = v / 4;
      grid[size_t(c)] = v - 4 * q;
      int x = c % w, y = c / w;
      // Los granos que salen del borde se pierden.
      if (x > 0) { if ((grid[size_t(c - 1)] += q) >= 4) stack.push_back(c - 1); }
      if (x < w - 1) { if ((grid[size_t(c + 1)] += q) >= 4) stack.push_back(c + 1); }
      if (y > 0) { if ((grid[size_t(c - w)] += q) >= 4) stack.push_back(c - w); }
      if (y < h - 1) { if ((grid[size_t(c + w)] += q) >= 4) stack.push_back(c + w); }
    }
  }

  void seeds(std::array<int, 4>& out, int& n) const {
    int cx = w / 2, cy = h / 2, d = std::max(4, w / 6);
    n = seedsUsed;
    if (n == 1) {
      out[0] = cy * w + cx;
    } else if (n == 2) {
      out[0] = (cy - d) * w + cx;
      out[1] = (cy + d) * w + cx;
    } else {
      out[0] = (cy - d) * w + cx - d;
      out[1] = (cy - d) * w + cx + d;
      out[2] = (cy + d) * w + cx - d;
      out[3] = (cy + d) * w + cx + d;
    }
  }

  bool touchesEdge() const {
    for (int x = 0; x < w; x++) if (grid[size_t(x)] || grid[size_t((h - 1) * w + x)]) return true;
    for (int y = 0; y < h; y++) if (grid[size_t(y * w)] || grid[size_t(y * w + w - 1)]) return true;
    return false;
  }

 public:
  void reset(uint32_t seed) override {
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    sim = 0;
    fadeStart = -1;
    steps = 0;
    w = h = 0;
    cellMode = 0;
    seedsUsed = 1;
    cycle = int(seed % 3u);
    burst = 0;
    grainAcc = 0;
    grid.assign(kMaxCells, 0);
    stack.reserve(kMaxCells);
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
    if (hit > kick + 0.2f) burst += int(250.0f + 500.0f * hit);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    // Rejilla de unas 30 000 celdas como mucho, con lados impares (simetría).
    float area = f.width * f.height;
    float cell = std::max(std::sqrt(area / float(kMaxCells)), std::min(f.width, f.height) / 400.0f * (1.5f + float(m.grano)));
    int nw = (int(f.width / cell) | 1), nh = (int(f.height / cell) | 1);
    nw = std::max(nw, 11);
    nh = std::max(nh, 11);
    while (nw * nh > kMaxCells) {
      nw -= 2;
      nh -= 2;
    }
    int wantSeeds = m.semillas == 0 ? (cycle % 3 == 0 ? 1 : (cycle % 3 == 1 ? 4 : 2)) : (m.semillas == 1 ? 1 : (m.semillas == 2 ? 2 : 4));
    if (nw != w || nh != h || m.grano != cellMode || (m.semillas != 0 && wantSeeds != seedsUsed)) {
      w = nw;
      h = nh;
      cellMode = m.grano;
      seedsUsed = wantSeeds;
      std::fill(grid.begin(), grid.end(), 0);
      fadeStart = -1;
    }
    sim += f.delta * f.speed;
    int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > 30) steps = target - 30;
    std::array<int, 4> s{};
    int ns = 1;
    while (steps < target) {
      steps++;
      double now = double(steps) * kStep;
      if (fadeStart >= 0.0) {
        if (now - fadeStart > 1.5) {
          // Montón nuevo: limpio y, en Auto, con otra disposición de semillas.
          std::fill(grid.begin(), grid.end(), 0);
          fadeStart = -1;
          cycle++;
          if (m.semillas == 0) seedsUsed = cycle % 3 == 0 ? 1 : (cycle % 3 == 1 ? 4 : 2);
        }
        continue;
      }
      seeds(s, ns);
      grainAcc += m.caudal * (14.0f + 40.0f * drive) * float(w * h) / 20000.0f;
      uint32_t grains = uint32_t(grainAcc);
      grainAcc -= float(grains);
      if (burst > 0) {
        grains += uint32_t(burst);
        burst = 0;
      }
      if (grains == 0) continue;
      for (int k = 0; k < ns; k++) drop(s[size_t(k)], std::max(1u, grains / uint32_t(ns)));
      if (steps % 30 == 0 && touchesEdge()) fadeStart = now;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    Paint back;
    back.color = Color{bg.r, bg.g, bg.b, 1.0f};
    c.rect({0, 0, f.width, f.height}, back);
    if (w <= 0) return;
    float cw = f.width / float(w), ch = f.height / float(h);
    float fade = fadeStart >= 0.0 ? float(std::clamp(1.0 - (sim - fadeStart) / 1.5, 0.0, 1.0)) : 1.0f;
    // Textura: cada celda se pinta como tesela, como cuenta redonda o, en
    // encaje, sólo si es borde (alguna vecina tiene otros granos). Al cambiar,
    // las celdas se reparten entre las texturas según sus pesos.
    const std::array<float, 3> weight = {g.textura.weight(0), g.textura.weight(1), g.textura.weight(2)};
    auto level = [&](int x, int y) {
      return (x < 0 || y < 0 || x >= w || y >= h) ? 0u : std::min(grid[size_t(y * w + x)], 3u);
    };
    auto finish = [&](int x, int y) {
      if (weight[0] >= 1.0f) return 0;
      if (weight[1] >= 1.0f) return 1;
      if (weight[2] >= 1.0f) return 2;
      uint32_t k = uint32_t(x) * 73856093u ^ uint32_t(y) * 19349663u;
      k ^= k >> 13;
      k *= 0x5bd1e995u;
      k ^= k >> 15;
      float u = float(k & 0xffffu) / 65536.0f;
      return u < weight[0] ? 0 : (u < weight[0] + weight[1] ? 1 : 2);
    };
    // Tipo de cada celda: -1 nada, 0..2 tesela del nivel, 3..5 cuenta del nivel.
    auto kind = [&](int x, int y) {
      uint32_t v = level(x, y);
      if (v == 0) return -1;
      int t = finish(x, y);
      if (t == 1) return int(v) + 2;
      if (t == 2 && level(x - 1, y) == v && level(x + 1, y) == v && level(x, y - 1) == v && level(x, y + 1) == v) return -1;
      return int(v) - 1;
    };
    std::array<Path, 3> paths;
    std::array<std::vector<Vec2>, 3> beads;
    for (int y = 0; y < h; y++) {
      int x = 0;
      while (x < w) {
        int k = kind(x, y);
        if (k < 0) {
          x++;
          continue;
        }
        if (k >= 3) {
          beads[size_t(k - 3)].push_back({(float(x) + 0.5f) * cw, (float(y) + 0.5f) * ch});
          x++;
          continue;
        }
        int start = x;
        while (x < w && kind(x, y) == k) x++;
        paths[size_t(k)].rect({float(start) * cw, float(y) * ch, float(x - start) * cw + 0.5f, ch + 0.5f});
      }
    }
    const std::array<Color, 3> pal = {f.colors[1], f.colors[2], f.colors[3]};
    float lit = (0.85f + 0.3f * bass + 0.25f * kick) * amp * fade;
    for (int k = 0; k < 3; k++) {
      const Color& col = pal[size_t(k)];
      Paint p;
      p.color = Color{std::min(1.0f, col.r * lit + bg.r * (1.0f - fade)), std::min(1.0f, col.g * lit + bg.g * (1.0f - fade)),
                      std::min(1.0f, col.b * lit + bg.b * (1.0f - fade)), 1.0f};
      c.path(paths[size_t(k)], p);
      if (!beads[size_t(k)].empty()) c.points(beads[size_t(k)], 0.46f * std::min(cw, ch), p);
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
