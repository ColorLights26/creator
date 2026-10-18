// Luciérnagas Simples — capa transparente de lucecitas que parpadean.
// Sólo partículas, sin fondo: puntos verde amarillo que vagan despacio por
// la pantalla y se encienden y se apagan. Parpadeo las hace lentas, rápidas
// o encenderse todas a la vez; Profundidad pone algunas cerca de la cámara.
// Pulso: Golpes enciende un grupo de luciérnagas juntas; Graves las hincha;
// Brillos hace centellear algunas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA
  CreatorModifier.slider('tamano', 'Tamaño', min: .5, max: 2, value: 1),
  // MOVIMIENTO: cómo se encienden.
  CreatorModifier.choice('parpadeo', 'Parpadeo', options: ['Lento', 'Rápido', 'A la vez']),
  // ATMÓSFERA: luciérnagas cerca de la cámara, grandes y suaves.
  CreatorModifier.slider('profundidad', 'Profundidad', min: 0, max: 1, value: .35),
  // MÚSICA
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Brillos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Noche de Verano', {'parpadeo': 'Lento', 'profundidad': .8, 'detail': 1.6}),
  CreatorVariation('Señales', {'parpadeo': 'A la vez', 'profundidad': .1, 'tamano': 1.2}),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Reservado para detail 2: cambiar un ajuste nunca reserva memoria.
  static constexpr int kMax = 150;
  // Ráfagas de los golpes: un anillo fijo de ranuras {inicio, fuerza}.
  static constexpr int kSlots = 6;
  static constexpr int kPerBurst = 14;
  static constexpr int kLevels = 4;
  static constexpr int kGroups = 3 * kLevels;
  struct Mote { float a, b, c, life, phase, speed, size, depth, flick, twk, ox, oy, cl; };
  struct Burst { double at; float power; uint32_t id; float cx, cy; };
  struct Look { float W, H, side, px, size, s1, s2, s3, w0, w1, w2; };
  std::array<Mote, kMax> motes{};
  std::array<Burst, kSlots> bursts{};
  uint32_t burstCount = 0;
  double clock = 0, lastBurst = -100;
  float bass = 0, spark = 0, kick = 0, slowBass = 0;
  // Lotes por profundidad y nivel de brillo: un points() por lote, nunca uno
  // por partícula. Las estelas van en pares (desde, hasta).
  mutable std::array<std::vector<Vec2>, kGroups> dots;
  mutable std::array<std::vector<Vec2>, kGroups> tails;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  static float mixf(float a, float b, float t) { return a + (b - a) * t; }
  static Color mixc(const Color& a, const Color& b, float t) {
    return {mixf(a.r, b.r, t), mixf(a.g, b.g, t), mixf(a.b, b.b, t), 1.0f};
  }
  // Brillo bajo: el color tenue; brillo alto: el más caliente.
  static Color tint(const Frame& f, float lv) {
    return lv < 0.5f ? mixc(f.colors[1], f.colors[2], lv * 2.0f) : mixc(f.colors[2], f.colors[3], (lv - 0.5f) * 2.0f);
  }
  int bucket(const Mote&, float alpha, const Look&) const {
    return std::min(kLevels - 1, int(std::sqrt(alpha) * float(kLevels)));
  }
  Color bucketColor(const Frame& f, int level) const { return tint(f, bucketAlpha(level)); }
  float bucketAlpha(int level) const { return (float(level) + 0.75f) / float(kLevels); }
  float haloK(int) const { return 1.0f; }
  static constexpr bool kSquares = false;
  static constexpr float kCoreMix = 0.35f;
  void glints(Vec2, float, int, size_t, const Look&) const {}
  int layerOf(const Mote& m, const Look& L) const {
    return m.depth > 0.97f - 0.3f * L.s3 ? 2 : (m.depth < 0.55f ? 0 : 1);
  }
  float coreRadius(int layer, const Look& L) const {
    return L.px * L.size * (layer == 0 ? 1.1f : (layer == 1 ? 1.8f : 3.6f));
  }
  float trail(const Look&) const { return 0.0f; }
  // Luciérnagas: vagan despacio por toda la pantalla.
  Vec2 pos(const Mote& m, uint32_t key, float age, const Look& L) const {
    const float hx = hashU(key * 3u + 1u), hy = hashU(key * 3u + 2u), hz = hashU(key * 3u + 3u);
    const float ph = (m.c + hz) * 6.2832f;
    float x = mixf(hx, m.ox + (hx - 0.5f) * 0.3f, m.cl) * L.W, y = mixf(hy, m.oy + (hy - 0.5f) * 0.3f, m.cl) * L.H;
    x += 0.05f * L.side * (std::sin(age * 0.35f + ph) + 0.5f * std::sin(age * 0.9f + ph * 2.0f));
    y += 0.04f * L.side * (std::cos(age * 0.3f + ph * 1.7f) + 0.5f * std::sin(age * 0.8f + ph));
    return {x, y};
  }
  // Parpadeo: lento, rápido o todas a la vez.
  float shine(const Mote& m, float age, float t, const Look& L) const {
    float e = 4.0f * t * (1.0f - t);
    e = std::min(e * 2.0f, 1.0f);
    const float slow = std::max(std::sin(age * (0.9f + 0.6f * m.flick) + m.c * 30.0f), 0.0f);
    const float quick = std::max(std::sin(age * (4.0f + 3.0f * m.flick) + m.c * 30.0f), 0.0f);
    const float sync = std::max(std::sin(float(clock) * 2.2f + m.c * 0.6f), 0.0f);
    const float s2 = slow * slow, q2 = quick * quick, y2 = sync * sync;
    return e * (0.12f + 0.88f * (L.w0 * s2 * s2 + L.w1 * q2 * q2 + L.w2 * y2 * y2));
  }
  // Golpe: un grupo de luciérnagas se enciende junto.
  Mote burstMote(uint32_t key, const Burst& b) const {
    Mote m{};
    m.c = hashU(key + 1u);
    m.life = 1.6f + 1.0f * hashU(key + 3u);
    m.depth = 0.3f + 0.6f * hashU(key + 5u);
    m.flick = hashU(key + 6u);
    m.twk = hashU(key + 7u);
    m.ox = 0.15f + 0.7f * b.cx;
    m.oy = 0.15f + 0.7f * b.cy;
    m.cl = 1.0f;
    return m;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    for (auto& m : motes) {
      m.a = rng.unit();
      m.b = rng.unit();
      m.c = rng.unit();
      m.speed = rng.unit();
      m.depth = rng.unit();
      m.life = 8.0f + 6.0f * rng.unit();
      m.phase = rng.unit();
      m.size = 0.55f + 0.9f * rng.unit();
      m.flick = rng.unit();
      m.twk = rng.unit();
      m.ox = m.oy = m.cl = 0.0f;
    }
    for (auto& b : bursts) b = {-100.0, 0.0f, 0u, 0.5f, 0.5f};
    burstCount = 0;
    clock = 0;
    lastBurst = -100;
    bass = spark = kick = slowBass = 0;
    for (auto& d : dots) {
      d.clear();
      d.reserve(size_t(kMax + kSlots * kPerBurst));
    }
    for (auto& t : tails) {
      t.clear();
      t.reserve(size_t(4 * (kMax + kSlots * kPerBurst)));
    }
  }

  void update(const Frame& f) override {
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    float hit = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    const bool fresh = hit > kick + 0.2f;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    // Reloj propio: el movimiento es el mismo a 30 y a 60 FPS.
    clock += f.delta * f.speed;
    // Cada golpe guarda una ráfaga: su inicio en el reloj, su fuerza y su sitio.
    if (fresh && mu.active && clock - lastBurst > 0.12) {
      const uint32_t id = burstCount++;
      bursts[size_t(id % uint32_t(kSlots))] = {clock, hit, id, hashU(id * 7u + 3u), hashU(id * 7u + 5u)};
      lastBurst = clock;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float amp = f.intensity;
    Look L{};
    L.W = f.width;
    L.H = f.height;
    L.side = std::min(f.width, f.height);
    L.px = L.side / 400.0f;
    L.size = g.tamano;
    L.s3 = g.profundidad;
    L.w0 = g.parpadeo.weight(0);
    L.w1 = g.parpadeo.weight(1);
    L.w2 = g.parpadeo.weight(2);
    // Pulso: Golpes lanza ráfagas, Graves hincha las partículas, Brillos las
    // hace centellear.
    const float golpes = g.pulso.weight(0) * amp;
    const float graves = g.pulso.weight(1) * amp;
    const float brillos = g.pulso.weight(2) * amp;
    float pulse = 0;
    for (const Burst& b : bursts) {
      const double age = clock - b.at;
      if (age >= 0.0 && age < 2.0) pulse = std::max(pulse, b.power * float(std::exp(-age * 6.0)));
    }
    const float boost = 1.0f + 0.5f * std::min(pulse * golpes, 1.0f);
    const float swell = 1.0f + 0.3f * std::min(bass * graves, 1.0f);
    const float shimmer = std::min(spark * brillos, 1.2f);
    for (auto& d : dots) d.clear();
    for (auto& t : tails) t.clear();
    const float tl = trail(L);
    auto add = [&](const Mote& m, uint32_t key, float age, float t, float extra) {
      float alpha = shine(m, age, t, L) * extra;
      // Brillos: algunas partículas centellean con los agudos.
      if (m.twk > 0.5f) alpha *= 1.0f + shimmer * (0.6f + 0.6f * std::sin(float(clock) * 23.0f + m.twk * 40.0f));
      alpha = std::clamp(alpha * boost, 0.0f, 1.0f);
      if (alpha < 0.03f) return;
      const Vec2 p = pos(m, key, age, L);
      const float margin = 60.0f * L.px;
      if (p.x < -margin || p.y < -margin || p.x > L.W + margin || p.y > L.H + margin) return;
      const int layer = layerOf(m, L);
      const int level = bucket(m, alpha, L);
      const size_t group = size_t(layer * kLevels + level);
      dots[group].push_back(p);
      if (tl > 0.0f && age > 0.0f) {
        const Vec2 q = pos(m, key, std::max(age - tl, 0.0f), L);
        tails[group].push_back(q);
        tails[group].push_back(p);
      }
      glints(p, alpha, layer, group, L);
    };
    // Partículas de siempre: renacen por ciclo en otro sitio, sin crear ni
    // borrar nada.
    const int visible = std::clamp(int(float(kMax) * 0.5f * f.detail), 1, kMax);
    for (int i = 0; i < visible; i++) {
      const Mote& m = motes[size_t(i)];
      const double s = clock + double(m.phase * m.life);
      const double n = std::floor(s / double(m.life));
      const float age = float(s - n * double(m.life));
      const uint32_t key = uint32_t(i) * 2654435761u + uint32_t(int64_t(n)) * 40503u + 17u;
      add(m, key, age, age / m.life, 1.0f);
    }
    // Ráfagas de los golpes (sólo con Pulso en Golpes).
    for (const Burst& b : bursts) {
      const double bage = clock - b.at;
      if (b.power <= 0.0f || bage < 0.0 || bage > 6.0) continue;
      const int count = std::clamp(int(float(kPerBurst) * (0.4f + 0.6f * b.power) * std::min(golpes, 1.5f)), 0, kPerBurst);
      for (int k = 0; k < count; k++) {
        const uint32_t key = (b.id * 977u + uint32_t(k)) * 2246822519u + 0x9e3779b9u;
        const Mote m = burstMote(key, b);
        const float age = float(bage);
        if (age > m.life) continue;
        add(m, key ^ 0x5bd1e995u, age, age / m.life, 1.0f + 0.4f * b.power);
      }
    }
    // Sin fondo: sólo la luz de las partículas, sumada encima del visual.
    // Figuras primero (estelas) y puntos después.
    for (int layer = 0; layer < 3; layer++) {
      for (int level = 0; level < kLevels; level++) {
        const auto& seg = tails[size_t(layer * kLevels + level)];
        const float lv = bucketAlpha(level);
        const Color col = bucketColor(f, level);
        if (kSquares && !dots[size_t(layer * kLevels + level)].empty()) {
          // Cuadraditos de luz: todos los del lote en una sola figura.
          const float half = coreRadius(layer, L) * swell;
          Path squares;
          for (const Vec2& q : dots[size_t(layer * kLevels + level)]) squares.rect({q.x - half, q.y - half, 2.0f * half, 2.0f * half});
          Paint sp;
          sp.blend = Blend::plus;
          sp.color = mixc(col, f.colors[3], kCoreMix).opacity(std::clamp(lv * 0.95f * 1.2f, 0.0f, 1.0f));
          c.path(squares, sp);
        }
        if (seg.empty()) continue;
        Path path;
        for (size_t s = 0; s + 1 < seg.size(); s += 2) {
          path.moveTo(seg[s].x, seg[s].y);
          path.lineTo(seg[s + 1].x, seg[s + 1].y);
        }
        Paint p;
        p.blend = Blend::plus;
        p.strokeWidth = std::max(0.6f, coreRadius(layer, L) * 1.9f * swell);
        p.strokeCap = 1;
        p.color = col.opacity(std::clamp(lv * 0.8f, 0.0f, 1.0f));
        c.path(path, p);
      }
    }
    for (int layer = 0; layer < 3; layer++) {
      const float r = coreRadius(layer, L) * swell;
      for (int level = 0; level < kLevels; level++) {
        const auto& pts = dots[size_t(layer * kLevels + level)];
        if (pts.empty()) continue;
        const float lv = bucketAlpha(level);
        const Color col = bucketColor(f, level);
        const float hk = haloK(level);
        Paint wide;
        wide.blend = Blend::plus;
        wide.color = col.opacity(std::clamp(lv * hk * 0.05f * f.glow * (1.0f + 0.6f * std::min(bass * graves, 1.0f)), 0.0f, 1.0f));
        c.points(pts, r * 4.2f, wide);
        Paint near;
        near.blend = Blend::plus;
        near.color = col.opacity(std::clamp(lv * hk * 0.22f * f.glow, 0.0f, 1.0f));
        c.points(pts, r * 2.2f, near);
        Paint core;
        core.blend = Blend::plus;
        core.color = mixc(col, f.colors[3], kCoreMix).opacity(std::clamp(lv * 0.95f * 1.2f, 0.0f, 1.0f));
        if (!kSquares) c.points(pts, r, core);
      }
    }
  }
};
''';
