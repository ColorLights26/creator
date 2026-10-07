// Medidores VU — el panel ámbar de un equipo de música antiguo.
// Una rejilla de medidores analógicos con su cristal iluminado en ámbar,
// la escala curva con marcas, la zona roja al final y una aguja negra. Cada
// medidor escucha una banda de la música (de graves a agudos); la aguja
// tiene masa y muelle de verdad, así sube rápido, se pasa un poco y vuelve
// meciéndose como las de los VU reales. El piloto rojo de cada medidor se
// enciende cuando la aguja entra en la zona roja o con cada golpe. Sin
// música las agujas descansan respirando suavemente.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('medidores', 'Medidores', min: 2, max: 10, value: 8),
  CreatorModifier.slider('sensibilidad', 'Sensibilidad', min: .5, max: 2, value: 1),
  CreatorModifier.slider('inercia', 'Inercia de la aguja', min: .3, max: 2, value: 1),
  CreatorModifier.toggle('pilotos', 'Pilotos rojos', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 10;
  static constexpr double kStep = 1.0 / 240.0;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, kMax> bands{};
  std::array<double, kMax> angle{}, vel{};
  std::array<float, kMax> peak{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, sim = 0;
  int64_t steps = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Colores siempre dentro de 0..1, también con intensity 2 y golpes fuertes.
  static Color rgba(float r, float g, float b, float a) {
    return Color{std::clamp(r, 0.0f, 1.0f), std::clamp(g, 0.0f, 1.0f), std::clamp(b, 0.0f, 1.0f), std::clamp(a, 0.0f, 1.0f)};
  }

 public:
  void reset(uint32_t seed) override {
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    angle.fill(0);
    vel.fill(0);
    peak.fill(0);
    clock = double(seed % 97u) * 0.37;
    sim = 0;
    steps = 0;
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
    int n = std::clamp(m.medidores, 1, kMax);
    for (int i = 0; i < n; i++) {
      int b0 = i * 28 / n, b1 = std::max(b0 + 1, (i + 1) * 28 / n);
      float v = 0;
      for (int b = b0; b < b1; b++) v = std::max(v, mu.spectrum[size_t(b)]);
      bands[size_t(i)] = v;
    }

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed;
    // Aguja con masa y muelle, integrada a paso fijo.
    double stiffness = 120.0 / double(m.inercia);
    double damping = 11.0 / std::sqrt(double(m.inercia));
    sim += f.delta * f.speed;
    int64_t want = int64_t(std::floor(sim / kStep + 1e-6));
    if (want - steps > 120) steps = want - 120;
    while (steps < want) {
      double t = double(steps) * kStep;
      for (int i = 0; i < n; i++) {
        // Sin música: respiración suave alrededor de −20 dB.
        double idle = 0.3 + 0.14 * std::sin(t * 1.7 + double(i) * 1.3) + 0.08 * std::sin(t * 3.1 + double(i) * 2.0);
        double goal = mu.active ? std::clamp(std::pow(double(bands[size_t(i)]), 0.6) * double(m.sensibilidad) * 1.1, 0.0, 1.08) : idle;
        double acc = stiffness * (goal - angle[size_t(i)]) - damping * vel[size_t(i)];
        vel[size_t(i)] += acc * kStep;
        angle[size_t(i)] += vel[size_t(i)] * kStep;
        if (angle[size_t(i)] < -0.02) {
          angle[size_t(i)] = -0.02;
          vel[size_t(i)] = std::max(0.0, vel[size_t(i)]);
        }
      }
      steps++;
    }
    for (int i = 0; i < n; i++) {
      float red = angle[size_t(i)] > 0.82 ? 1.0f : 0.0f;
      peak[size_t(i)] = std::max(peak[size_t(i)] * std::exp(-dt * 4.0f), std::max(red, kick * 0.8f));
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    const Color& amber = f.colors[1];
    const Color& red = f.colors[2];
    const Color& face = f.colors[3];
    // Panel de metal oscuro.
    c.rect({0, 0, f.width, f.height}, Paint::linear({0, 0}, {f.width, f.height},
                                                   {rgba(bg.r + 0.05f, bg.g + 0.045f, bg.b + 0.04f, 1.0f),
                                                    rgba(bg.r, bg.g, bg.b, 1.0f)}));
    int n = std::clamp(m.medidores, 1, kMax);
    int cols = n <= 3 ? 1 : 2;
    int rows = (n + cols - 1) / cols;
    float px = std::min(f.width, f.height) / 400.0f;
    float margin = f.width * 0.06f;
    float cellW = (f.width - margin * float(cols + 1)) / float(cols);
    float cellH = std::min(cellW * 0.95f, (f.height - margin * float(rows + 1)) / float(rows));
    cellW = std::min(cellW, cellH / 0.72f);
    float totalH = cellH * float(rows) + margin * float(rows - 1);
    float startY = (f.height - totalH) * 0.5f;
    float startX = (f.width - cellW * float(cols) - margin * float(cols - 1)) * 0.5f;
    auto cellAt = [&](int i) { return Vec2{startX + float(i % cols) * (cellW + margin), startY + float(i / cols) * (cellH + margin)}; };
    const float a0 = -2.35f, a1 = -0.79f;
    float R = std::min(cellH * 0.72f, cellW * 0.62f);
    // Los medidores no se tocan: el margen entre ellos es mayor que el halo
    // del piloto y que lo que la aguja sobresale del cristal. Por eso se
    // pintan por capas para todos a la vez (marcos y escalas, agujas,
    // reflejos, halos, pilotos) y cada uno se ve igual que pintado entero.
    for (int i = 0; i < n; i++) {
      Vec2 cell = cellAt(i);
      float x = cell.x, y = cell.y;
      // Marco y cristal iluminado.
      Paint frame;
      frame.color = Color{0.13f, 0.12f, 0.11f, 1.0f};
      c.rect({x - 4.0f * px, y - 4.0f * px, cellW + 8.0f * px, cellH + 8.0f * px}, frame);
      float glowAmt = (0.75f + 0.25f * body + 0.2f * kick) * amp;
      Paint glass = Paint::radial({x + cellW * 0.5f, y + cellH * 0.9f}, cellW * 0.85f,
                                  {rgba(amber.r * glowAmt, amber.g * glowAmt, amber.b * glowAmt, 1.0f),
                                   rgba(amber.r * 0.45f * glowAmt, amber.g * 0.35f * glowAmt, amber.b * 0.25f * glowAmt, 1.0f)});
      c.rect({x, y, cellW, cellH}, glass);
      // Escala curva con marcas; la última parte en rojo.
      Vec2 pivot{x + cellW * 0.5f, y + cellH * 0.92f};
      Path arc, arcRed, ticks, ticksRed;
      for (int k = 0; k <= 40; k++) {
        float t = float(k) / 40.0f;
        float a = a0 + (a1 - a0) * t;
        float xx = pivot.x + R * std::cos(a), yy = pivot.y + R * std::sin(a);
        Path& dst = t < 0.78f ? arc : arcRed;
        if (k == 0 || (t >= 0.78f && t - 1.0f / 40.0f < 0.78f)) dst.moveTo(xx, yy); else dst.lineTo(xx, yy);
      }
      for (int k = 0; k <= 10; k++) {
        float t = float(k) / 10.0f;
        float a = a0 + (a1 - a0) * t;
        float inner = R * (k % 2 == 0 ? 0.86f : 0.92f);
        Path& dst = t < 0.78f ? ticks : ticksRed;
        dst.moveTo(pivot.x + inner * std::cos(a), pivot.y + inner * std::sin(a)).lineTo(pivot.x + R * std::cos(a), pivot.y + R * std::sin(a));
      }
      Paint ink;
      ink.strokeWidth = 1.8f * px;
      ink.color = face;
      c.path(arc, ink);
      c.path(ticks, ink);
      Paint redInk;
      redInk.strokeWidth = 3.2f * px;
      redInk.color = red;
      c.path(arcRed, redInk);
      redInk.strokeWidth = 1.8f * px;
      c.path(ticksRed, redInk);
    }
    // Agujas con su sombra, recortadas al cristal: un solo recorte para todas.
    Path glassClip;
    for (int i = 0; i < n; i++) {
      Vec2 cell = cellAt(i);
      glassClip.rect({cell.x, cell.y, cellW, cellH});
    }
    Paint shadow;
    shadow.strokeWidth = 2.6f * px;
    shadow.strokeCap = 1;
    shadow.color = Color{0, 0, 0, 0.25f};
    Paint np;
    np.strokeWidth = 2.0f * px;
    np.strokeCap = 1;
    np.color = Color{0.06f, 0.05f, 0.05f, 1.0f};
    float drop = 3.0f * px;
    c.save();
    c.clip(glassClip);
    for (int i = 0; i < n; i++) {
      Vec2 cell = cellAt(i);
      Vec2 pivot{cell.x + cellW * 0.5f, cell.y + cellH * 0.92f};
      float v = float(std::clamp(angle[size_t(i)], -0.02, 1.1));
      float a = a0 + (a1 - a0) * v;
      Vec2 tip{pivot.x + R * 1.04f * std::cos(a), pivot.y + R * 1.04f * std::sin(a)};
      Path shade, needle;
      shade.moveTo(pivot.x + drop, pivot.y + drop).lineTo(tip.x + drop, tip.y + drop);
      c.path(shade, shadow);
      needle.moveTo(pivot.x, pivot.y).lineTo(tip.x, tip.y);
      c.path(needle, np);
    }
    c.restore();
    // Reflejo del cristal.
    for (int i = 0; i < n; i++) {
      Vec2 cell = cellAt(i);
      Paint shine = Paint::linear({cell.x, cell.y}, {cell.x, cell.y + cellH * 0.4f}, {Color{1, 1, 1, 0.14f}, Color{1, 1, 1, 0.0f}});
      c.rect({cell.x, cell.y, cellW, cellH * 0.4f}, shine);
    }
    // Piloto rojo: primero todos los halos, después todos los puntos.
    if (m.pilotos) {
      for (int i = 0; i < n; i++) {
        Vec2 cell = cellAt(i);
        Vec2 led{cell.x + cellW * 0.9f, cell.y + cellH * 0.15f};
        float on = peak[size_t(i)] * amp;
        Paint ledGlow = Paint::radial(led, 14.0f * px, {red.opacity(std::clamp(on * f.glow, 0.0f, 1.0f)), red.opacity(0.0f)});
        ledGlow.blend = Blend::plus;
        c.circle(led, 14.0f * px, ledGlow);
      }
      for (int i = 0; i < n; i++) {
        Vec2 cell = cellAt(i);
        Vec2 led{cell.x + cellW * 0.9f, cell.y + cellH * 0.15f};
        float on = peak[size_t(i)] * amp;
        Paint ledDot;
        ledDot.color = rgba(0.25f + 0.75f * red.r * on, 0.04f + red.g * on, 0.03f + red.b * on, 1.0f);
        c.circle(led, 3.5f * px, ledDot);
      }
    }
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = amber.opacity(std::clamp(flash * 0.05f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
