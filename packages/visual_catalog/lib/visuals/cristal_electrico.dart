// Cristal Eléctrico — una figura de Lichtenberg que crece al rojo vivo.
// Como el rayo que la alta tensión quema en la madera: desde uno o varios
// puntos crecen canales que serpentean hacia fuera y se dividen una y otra
// vez sin tocarse nunca, hasta formar un helecho fractal que llena la
// pantalla. Lo recién quemado brilla blanco-amarillo y se enfría a naranja y
// a brasa roja; el canal principal es más grueso que las ramas. Cada golpe
// manda una descarga blanca desde el origen que recorre todas las ramas a la
// vez. Al completarse, la figura se apaga y otra empieza a crecer.
// Pulso elige qué más hace la música: en Golpes, además de la descarga,
// cada golpe enciende la figura entera un instante, como un rayo, engorda
// sus canales y un resplandor estalla en el origen; en Graves las brasas se
// avivan, los canales engordan y el halo y el resplandor del origen respiran
// con los graves; en Agudos la figura chisporrotea: muchos tramos sueltos
// saltan al blanco y las puntas echan chispas más grandes.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('origen', 'Origen', options: ['Centro', 'Abajo', 'Arriba y abajo']),
  CreatorModifier.slider('ramas', 'Ramificación', min: .4, max: 2, value: 1),
  // MOVIMIENTO: de agujas de cristal casi rectas (mín.) a canales que se
  // retuercen en zigzag (máx.). Conserva el id: las apariencias guardadas lo usan.
  CreatorModifier.slider('velocidad', 'Serpenteo', min: .4, max: 2.5, value: 1),
  CreatorModifier.toggle('descargas', 'Descargas', value: true),
  // MÚSICA: qué parte del rayo reacciona.
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Tormenta', {
    'origen': 'Arriba y abajo',
    'ramas': 1.6,
    'velocidad': 1.8,
    'pulso': 'Golpes',
  }),
  CreatorVariation('Brasa Viva', {
    'origen': 'Abajo',
    'ramas': .7,
    'velocidad': .6,
    'pulso': 'Graves',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxSegments = 7000;
  static constexpr int kMaxTips = 220;
  static constexpr double kRate = 45.0;
  struct Segment { float x0, y0, x1, y1; int depth; uint8_t level; int64_t born; };
  struct Tip { float x, y, dir; int depth; uint8_t level; float rx, ry; };
  enum Phase { kGrow, kHold, kFade };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double growth = 0, phaseTime = 0, pulseAge = 100, autoPulse = 0;
  int64_t steps = 0, lastAdd = 0;
  int phase = kGrow, gw = 0, gh = 0, maxDepth = 1, origin = -1;
  float cell = 4, width = 1, height = 1, pulsePower = 0;
  // Reloj del chisporroteo de los agudos.
  double zap = 0;
  Random rng{1};
  std::vector<Segment> segs;
  std::vector<Tip> tips, born;
  std::vector<uint8_t> grid;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }

  int gi(float x, float y) const {
    int ix = int(x / cell), iy = int(y / cell);
    if (ix < 0 || iy < 0 || ix >= gw || iy >= gh) return -1;
    return iy * gw + ix;
  }

  void mark(float x, float y) {
    int i = gi(x, y);
    if (i >= 0) grid[size_t(i)] = 1;
  }

  // Libre si la celda y sus vecinas están vacías (salvo la de procedencia).
  bool freeAt(float x, float y, float fromX, float fromY) const {
    int ix = int(x / cell), iy = int(y / cell);
    int fx = int(fromX / cell), fy = int(fromY / cell);
    if (ix < 1 || iy < 1 || ix >= gw - 1 || iy >= gh - 1) return false;
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        int cx = ix + dx, cy = iy + dy;
        if (std::abs(cx - fx) <= 1 && std::abs(cy - fy) <= 1) continue;
        if (grid[size_t(cy * gw + cx)]) return false;
      }
    }
    return true;
  }

  void seed(int mode) {
    segs.clear();
    tips.clear();
    std::fill(grid.begin(), grid.end(), 0);
    maxDepth = 1;
    auto root = [&](float x, float y, float baseDir, int count, float spread) {
      mark(x, y);
      for (int k = 0; k < count; k++) {
        float d = baseDir + (float(k) - float(count - 1) * 0.5f) * spread + (rng.unit() - 0.5f) * 0.3f;
        tips.push_back({x, y, d, 0, 0, x, y});
      }
    };
    if (mode == 0) {
      root(width * 0.5f, height * 0.5f, 0.0f, 6, 6.2831853f / 6.0f);
    } else if (mode == 1) {
      root(width * 0.5f, height * 0.97f, -1.5707963f, 3, 0.5f);
    } else {
      root(width * 0.5f, height * 0.03f, 1.5707963f, 3, 0.5f);
      root(width * 0.5f, height * 0.97f, -1.5707963f, 3, 0.5f);
    }
  }

  void grow(float branching, float wander) {
    steps++;
    born.clear();
    float len = cell * 1.5f;
    for (auto& t : tips) {
      // Serpentea según Serpenteo, siempre empujado hacia fuera desde su origen.
      float out = std::atan2(t.y - t.ry, t.x - t.rx);
      if (t.depth < 2) out = t.dir;
      float diff = std::remainder(out - t.dir, 6.2831853f);
      float nd = t.dir + diff * 0.14f + (rng.unit() - 0.5f) * 0.6f * wander;
      float nx = t.x + std::cos(nd) * len, ny = t.y + std::sin(nd) * len;
      bool ok = freeAt(nx, ny, t.x, t.y);
      if (!ok) {
        nd = t.dir + (rng.unit() - 0.5f) * 1.4f;
        nx = t.x + std::cos(nd) * len;
        ny = t.y + std::sin(nd) * len;
        ok = freeAt(nx, ny, t.x, t.y);
      }
      if (!ok || int(segs.size()) >= kMaxSegments) {
        t.depth = -1;
        continue;
      }
      segs.push_back({t.x, t.y, nx, ny, t.depth + 1, t.level, steps});
      lastAdd = steps;
      mark(nx, ny);
      t.x = nx;
      t.y = ny;
      t.dir = nd;
      t.depth++;
      maxDepth = std::max(maxDepth, t.depth);
      if (rng.unit() < 0.09f * branching && int(tips.size() + born.size()) < kMaxTips) {
        float side = rng.unit() < 0.5f ? -1.0f : 1.0f;
        born.push_back({nx, ny, nd + side * (0.35f + 0.4f * rng.unit()), t.depth, uint8_t(std::min(3, int(t.level) + 1)), t.rx, t.ry});
      }
      // Las ramas finas mueren antes: así el canal principal llega más lejos.
      if (rng.unit() < 0.004f + 0.006f * float(t.level)) t.depth = -1;
    }
    tips.erase(std::remove_if(tips.begin(), tips.end(), [](const Tip& t) { return t.depth < 0; }), tips.end());
    tips.insert(tips.end(), born.begin(), born.end());
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    growth = phaseTime = 0;
    pulseAge = 100;
    autoPulse = 0;
    pulsePower = 0;
    zap = 0;
    steps = 0;
    phase = kGrow;
    gw = gh = 0;
    origin = -1;
    segs.reserve(kMaxSegments + kMaxTips);
    tips.reserve(kMaxTips * 2);
    born.reserve(kMaxTips * 2);
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

    float side = std::min(f.width, f.height);
    float want = side / 150.0f;
    int w = int(f.width / want) + 1, h = int(f.height / want) + 1;
    if (w != gw || h != gh || m.origen != origin) {
      cell = want;
      width = f.width;
      height = f.height;
      gw = w;
      gh = h;
      origin = m.origen;
      grid.assign(size_t(gw * gh), 0);
      seed(origin);
      phase = kGrow;
      growth = 0;
      steps = 0;
      lastAdd = 0;
    }
    double scaled = f.delta * f.speed * (1.0 + 1.2 * drive);
    pulseAge += f.delta;
    autoPulse += f.delta;
    zap += f.delta;
    if (m.descargas && beat) {
      pulseAge = 0;
      pulsePower = hit;
    }
    // Sin música también hay una descarga cada 3 s.
    if (m.descargas && !mu.active && autoPulse > 3.0) {
      autoPulse -= 3.0;
      pulseAge = autoPulse;
      pulsePower = 0.8f;
    }
    if (phase == kGrow) {
      growth += scaled * kRate;
      int64_t target = int64_t(std::floor(growth + 1e-6));
      while (steps < target && !tips.empty()) {
        grow(m.ramas, m.velocidad);
        // Sin sitio para crecer: la figura está completa.
        if (steps - lastAdd > 40) tips.clear();
      }
      if (tips.empty()) {
        phase = kHold;
        phaseTime = std::max(0.0, growth - double(steps)) / kRate;
      }
      return;
    }
    phaseTime += scaled;
    if (phase == kHold && phaseTime >= 3.0) {
      phaseTime -= 3.0;
      phase = kFade;
    }
    if (phase == kFade && phaseTime >= 1.2) {
      double carry = phaseTime - 1.2;
      seed(origin);
      phase = kGrow;
      steps = 0;
      lastAdd = 0;
      growth = carry * kRate;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto gl = glide(f);
    float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto; sin música todo vale cero.
    const float kickP = std::min(kick * amp, 1.0f) * gl.pulso.weight(0);
    const float bassP = std::min(bass * amp, 1.0f) * gl.pulso.weight(1);
    const float sparkP = std::min(spark * amp, 1.0f) * gl.pulso.weight(2);
    const uint32_t tick = uint32_t(std::fmod(zap, 100000.0) * 15.0);
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.75f,
                                                   {Color{std::min(1.0f, bg.r + 0.06f), std::min(1.0f, bg.g + 0.03f), std::min(1.0f, bg.b + 0.015f), 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    float px = std::min(f.width, f.height) / 400.0f;
    // Resplandor local en el origen del rayo: Golpes lo hace estallar y Graves
    // lo hace respirar.
    const float aura = std::clamp((0.35f * kickP + 0.22f * bassP) * f.glow, 0.0f, 0.6f);
    if (aura > 0.002f) {
      const float span = std::min(f.width, f.height);
      auto bloom = [&](Vec2 at, float radius) {
        Paint ap = Paint::radial(at, radius, {f.colors[3].opacity(aura), f.colors[2].opacity(aura * 0.45f), f.colors[1].opacity(0.0f)},
                                 {0.0f, 0.4f, 1.0f});
        ap.blend = Blend::plus;
        c.circle(at, radius, ap);
      };
      if (origin <= 0) {
        bloom({f.width * 0.5f, f.height * 0.5f}, span * 0.55f);
      } else {
        bloom({f.width * 0.5f, f.height * 0.97f}, span * 0.65f);
        if (origin == 2) bloom({f.width * 0.5f, f.height * 0.03f}, span * 0.65f);
      }
    }
    float fade = phase == kFade ? float(std::max(0.0, 1.0 - phaseTime / 1.2)) : 1.0f;
    const Color& ember = f.colors[1];
    const Color& orange = f.colors[2];
    const Color& hot = f.colors[3];
    // Brillo: recién quemado (blanco) → naranja → brasa; más la descarga.
    std::array<Color, 6> heat = {Color{ember.r * 0.45f, ember.g * 0.4f, ember.b * 0.4f, 1.0f}, ember, orange,
                                 hot, Color{1.0f, 0.97f, 0.85f, 1.0f}, Color{1.0f, 1.0f, 1.0f, 1.0f}};
    const int levels = 3;
    std::array<Path, 6 * levels> paths;
    std::array<bool, 6 * levels> used{};
    float front = float(pulseAge) * 110.0f;
    float pulseFade = pulseAge < 2.5 ? float(1.0 - pulseAge / 2.5) * pulsePower : 0.0f;
    // Tiempo actual en pasos de crecimiento, también durante la pausa.
    double now = phase == kGrow ? double(steps) : double(steps) + (phase == kHold ? phaseTime : 3.0 + phaseTime) * kRate;
    for (const auto& s : segs) {
      float age = float((now - double(s.born)) / kRate);
      float b = age < 0.25f ? 4.6f : (age < 1.2f ? 3.6f - (age - 0.25f) * 1.6f : (age < 3.0f ? 2.1f - (age - 1.2f) * 0.55f : 1.05f));
      float d = std::fabs(float(s.depth) - front);
      if (d < 7.0f) b += (1.0f - d / 7.0f) * 3.5f * pulseFade;
      // Golpes: la figura entera se enciende un instante; Graves: las brasas
      // se avivan con los graves.
      b += 2.4f * kickP + 1.0f * bassP;
      // Agudos: tramos sueltos chisporrotean al blanco.
      if (sparkP > 0.002f && hashU(uint32_t(&s - segs.data()) * 2654435761u + tick * 40503u) < 0.25f * sparkP) b = std::max(b, 4.6f);
      int bi = std::clamp(int(b + 0.5f), 0, 5);
      int lv = std::min(int(s.level), levels - 1);
      int k = bi * levels + lv;
      paths[size_t(k)].moveTo(s.x0, s.y0).lineTo(s.x1, s.y1);
      used[size_t(k)] = true;
    }
    static const float widths[3] = {3.0f, 1.9f, 1.15f};
    for (int bi = 0; bi < 6; bi++) {
      for (int lv = 0; lv < levels; lv++) {
        int k = bi * levels + lv;
        if (!used[size_t(k)]) continue;
        const Color& col = heat[size_t(bi)];
        float w = widths[lv] * px * (1.0f + 0.25f * bass * amp) * (1.0f + 0.7f * bassP + 0.9f * kickP);
        if (bi >= 2) {
          Paint halo;
          halo.blend = Blend::plus;
          halo.strokeWidth = w * 4.0f;
          halo.strokeCap = 1;
          halo.color = col.opacity(std::clamp(0.06f * float(bi) * f.glow * fade * amp * (1.0f + 1.5f * kickP + 1.6f * bassP + 0.6f * sparkP), 0.0f, 1.0f));
          c.path(paths[size_t(k)], halo);
        }
        Paint p;
        p.strokeWidth = w;
        p.strokeCap = 1;
        p.strokeJoin = 1;
        p.color = col.opacity(std::clamp(fade * amp, 0.0f, 1.0f));
        c.path(paths[size_t(k)], p);
      }
    }
    // Puntas activas: chispas.
    if (phase == kGrow && !tips.empty()) {
      std::vector<Vec2> pts;
      pts.reserve(tips.size());
      for (const auto& t : tips) pts.push_back({t.x, t.y});
      Paint tp;
      tp.blend = Blend::plus;
      tp.color = hot.opacity(std::clamp((0.6f + 0.4f * spark) * amp, 0.0f, 1.0f));
      c.points(pts, 2.2f * px * (1.0f + 2.0f * sparkP + 0.6f * kickP), tp);
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
