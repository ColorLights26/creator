// Tres Cuerpos — estrellas que bailan con su gravedad real.
// Tres (o cinco) estrellas de igual masa se atraen según la ley de Newton,
// calculada paso a paso. Hay cuatro coreografías: la órbita en forma de
// ocho (descubierta en 1993, las tres estrellas se persiguen por la misma
// curva), un triángulo que gira, un caos de tres estrellas que se lanzan
// unas a otras y cinco estrellas enredadas. Cada estrella deja una estela de
// fuego. La cámara sigue al grupo y se aleja si se separan; si una estrella
// sale despedida o pasa un rato, empieza otra coreografía. La energía
// acelera el tiempo, cada golpe hace estallar el brillo y los graves
// engordan las estrellas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('baile', 'Coreografía', options: ['Auto', 'Ocho', 'Triángulo', 'Caos', 'Cinco']),
  CreatorModifier.slider('estela', 'Largo de la estela', min: .2, max: 1, value: .7),
  CreatorModifier.toggle('estrellas', 'Estrellas de fondo', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 5;
  static constexpr int kTrail = 360;
  static constexpr double kStep = 1.0 / 480.0;
  struct Body { double x, y, vx, vy; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double sim = 0, sceneTime = 0, camX = 0, camY = 0, camR = 1.2;
  int64_t steps = 0;
  int count = 3, scene = 0, autoScene = 0, trailHead = 0, trailCount = 0;
  Random rng{1};
  std::array<Body, kMax> b{};
  std::array<std::array<Vec2, kTrail>, kMax> trail{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void start(int which) {
    scene = which;
    sceneTime = 0;
    trailHead = 0;
    trailCount = 0;
    if (which == 0) {
      // Órbita en ocho de Chenciner y Montgomery (G = m = 1).
      count = 3;
      b[0] = {-0.97000436, 0.24308753, 0.46620368, 0.43236573};
      b[1] = {0.97000436, -0.24308753, 0.46620368, 0.43236573};
      b[2] = {0.0, 0.0, -0.93240737, -0.86473146};
    } else if (which == 1) {
      // Triángulo de Lagrange con un pequeño empujón: gira y acaba rompiéndose.
      count = 3;
      double r = 1.0, v = std::sqrt(1.0 / (std::sqrt(3.0) * r)) * 1.0;
      for (int i = 0; i < 3; i++) {
        double a = 6.283185307 * double(i) / 3.0 + 0.3;
        b[size_t(i)] = {r * std::cos(a), r * std::sin(a), -v * std::sin(a), v * std::cos(a)};
      }
      b[0].vx *= 1.004;
    } else {
      count = which == 2 ? 3 : 5;
      double px = 0, py = 0;
      for (int i = 0; i < count; i++) {
        b[size_t(i)] = {double(rng.unit() * 2.0f - 1.0f), double(rng.unit() * 2.0f - 1.0f),
                        double(rng.unit() - 0.5f) * 0.6, double(rng.unit() - 0.5f) * 0.6};
        px += b[size_t(i)].vx;
        py += b[size_t(i)].vy;
      }
      for (int i = 0; i < count; i++) {
        b[size_t(i)].vx -= px / count;
        b[size_t(i)].vy -= py / count;
      }
    }
  }

  void accel(const std::array<Body, kMax>& s, std::array<double, kMax>& ax, std::array<double, kMax>& ay) const {
    for (int i = 0; i < count; i++) ax[size_t(i)] = ay[size_t(i)] = 0;
    for (int i = 0; i < count; i++) {
      for (int j = i + 1; j < count; j++) {
        double dx = s[size_t(j)].x - s[size_t(i)].x, dy = s[size_t(j)].y - s[size_t(i)].y;
        double r2 = dx * dx + dy * dy + 0.0004;
        double inv = 1.0 / (r2 * std::sqrt(r2));
        ax[size_t(i)] += dx * inv;
        ay[size_t(i)] += dy * inv;
        ax[size_t(j)] -= dx * inv;
        ay[size_t(j)] -= dy * inv;
      }
    }
  }

  void step() {
    std::array<double, kMax> ax{}, ay{};
    accel(b, ax, ay);
    for (int i = 0; i < count; i++) {
      b[size_t(i)].vx += ax[size_t(i)] * kStep * 0.5;
      b[size_t(i)].vy += ay[size_t(i)] * kStep * 0.5;
      b[size_t(i)].x += b[size_t(i)].vx * kStep;
      b[size_t(i)].y += b[size_t(i)].vy * kStep;
    }
    accel(b, ax, ay);
    for (int i = 0; i < count; i++) {
      b[size_t(i)].vx += ax[size_t(i)] * kStep * 0.5;
      b[size_t(i)].vy += ay[size_t(i)] * kStep * 0.5;
    }
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    sim = 0;
    steps = 0;
    autoScene = 0;
    camX = camY = 0;
    camR = 1.2;
    start(0);
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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    int wanted = m.baile == 0 ? -1 : m.baile - 1;
    if (wanted >= 0 && wanted != scene) start(wanted);
    sim += f.delta * f.speed * (1.0 + 0.8 * drive);
    int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > 960) steps = target - 960;
    while (steps < target) {
      step();
      steps++;
      sceneTime += kStep;
      // Cámara: sigue al centro de masas y abarca a todas las estrellas.
      double cx = 0, cy = 0;
      for (int i = 0; i < count; i++) {
        cx += b[size_t(i)].x;
        cy += b[size_t(i)].y;
      }
      cx /= count;
      cy /= count;
      double far = 0.6;
      for (int i = 0; i < count; i++) far = std::max(far, std::hypot(b[size_t(i)].x - cx, b[size_t(i)].y - cy));
      double k = 1.0 - std::exp(-kStep * 1.5);
      camX += (cx - camX) * k;
      camY += (cy - camY) * k;
      camR += (std::min(far * 1.25, 6.0) - camR) * k;
      if (steps % 4 == 0) {
        trailHead = (trailHead + 1) % kTrail;
        trailCount = std::min(trailCount + 1, kTrail);
        for (int i = 0; i < count; i++) trail[size_t(i)][size_t(trailHead)] = {float(b[size_t(i)].x), float(b[size_t(i)].y)};
      }
      // Otra coreografía si una estrella escapa o pasa demasiado tiempo.
      bool escaped = far > 5.0;
      double limit = scene == 0 ? 40.0 : 24.0;
      if (escaped || sceneTime > limit) {
        if (m.baile == 0) {
          autoScene = (autoScene + 1) % 4;
          start(autoScene);
        } else {
          start(scene);
        }
      }
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.7f,
                                                   {Color{std::min(1.0f, bg.r + 0.05f), std::min(1.0f, bg.g + 0.025f), std::min(1.0f, bg.b + 0.05f), 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    if (m.estrellas) {
      std::vector<Vec2> stars;
      stars.reserve(160);
      for (int i = 0; i < 160; i++) {
        uint32_t hsh = uint32_t(i) * 2654435761u;
        float x = float(hsh & 0xffff) / 65535.0f, y = float((hsh >> 16) & 0xffff) / 65535.0f;
        stars.push_back({x * f.width, y * f.height});
      }
      Paint sp;
      sp.color = Color{0.9f, 0.85f, 0.8f, 0.35f};
      c.points(stars, 0.9f * px, sp);
    }
    float scale = side * 0.62f / float(camR);
    auto toPx = [&](float x, float y) { return Vec2{f.width * 0.5f + (x - float(camX)) * scale, f.height * 0.5f + (y - float(camY)) * scale}; };
    std::array<Color, kMax> cols = {f.colors[1], f.colors[2], f.colors[3], Color{1.0f, 0.4f, 0.6f, 1.0f}, Color{1.0f, 0.6f, 0.2f, 1.0f}};
    int len = std::max(2, int(float(trailCount) * m.estela));
    const int chunks = 8;
    for (int i = 0; i < count; i++) {
      const Color& col = cols[size_t(i)];
      for (int ch = 0; ch < chunks; ch++) {
        int a = len * ch / chunks, e = std::min(len - 1, len * (ch + 1) / chunks);
        if (e <= a) continue;
        Path p;
        for (int k = a; k <= e; k++) {
          int idx = ((trailHead - (len - 1 - k)) % kTrail + kTrail) % kTrail;
          const Vec2& tp = trail[size_t(i)][size_t(idx)];
          Vec2 q = toPx(tp.x, tp.y);
          if (k == a) p.moveTo(q.x, q.y); else p.lineTo(q.x, q.y);
        }
        float t = float(ch + 1) / float(chunks);
        Paint glow;
        glow.blend = Blend::plus;
        glow.strokeWidth = (7.0f + 9.0f * t) * px;
        glow.strokeCap = 1;
        glow.strokeJoin = 1;
        glow.color = col.opacity(std::clamp(0.14f * t * f.glow * amp, 0.0f, 1.0f));
        c.path(p, glow);
        Paint line;
        line.blend = Blend::plus;
        line.strokeWidth = (1.2f + 3.2f * t) * px;
        line.strokeCap = 1;
        line.strokeJoin = 1;
        line.color = col.opacity(std::clamp((0.15f + 0.75f * t) * amp, 0.0f, 1.0f));
        c.path(p, line);
      }
    }
    for (int i = 0; i < count; i++) {
      Vec2 q = toPx(float(b[size_t(i)].x), float(b[size_t(i)].y));
      const Color& col = cols[size_t(i)];
      float r = (7.0f + 5.0f * bass * amp) * px;
      Paint halo = Paint::radial(q, r * (4.0f + 3.0f * kick), {col.opacity(std::clamp((0.55f + 0.4f * kick) * f.glow * amp, 0.0f, 1.0f)), col.opacity(0.0f)});
      halo.blend = Blend::plus;
      c.circle(q, r * (4.0f + 3.0f * kick), halo);
      Paint core = Paint::radial(q, r, {Color{1.0f, 1.0f, 0.95f, 1.0f}, col, col.opacity(0.0f)}, {0.0f, 0.55f, 1.0f});
      c.circle(q, r, core);
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
