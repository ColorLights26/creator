// Ola de Péndulos Transparente — la famosa máquina de péndulos vista desde arriba.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Cada fila es un péndulo que oscila de izquierda a derecha; el de arriba da
// veinte vueltas por ciclo y cada uno de los siguientes una más. Al empezar
// todos van juntos, enseguida forman una serpiente, luego dos, tres, patrones
// cruzados que parecen caos y, al final del ciclo, vuelven a alinearse. Una
// línea une las bolas y cada bola deja una estela. La energía acelera el
// tiempo, los graves abren el vaivén y cada golpe recorre la fila como un
// relámpago de luz de arriba abajo.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('pendulos', 'Péndulos', min: 10, max: 32, value: 20),
  CreatorModifier.slider('ciclo', 'Duración del ciclo', min: 10, max: 60, value: 24),
  CreatorModifier.slider('amplitud', 'Amplitud', min: .4, max: 1, value: .85),
  CreatorModifier.toggle('estelas', 'Estelas', value: true),
  CreatorModifier.toggle('curva', 'Línea que los une', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 32;
  static constexpr int kTrail = 8;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double tau = 0, sinceHit = 100;
  float hitPower = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static Color mix3(const Color& a, const Color& b, const Color& c, float t) {
    t = std::clamp(t, 0.0f, 1.0f);
    if (t < 0.5f) {
      float u = t * 2.0f;
      return {a.r + (b.r - a.r) * u, a.g + (b.g - a.g) * u, a.b + (b.b - a.b) * u, 1.0f};
    }
    float u = (t - 0.5f) * 2.0f;
    return {b.r + (c.r - b.r) * u, b.g + (c.g - b.g) * u, b.b + (c.b - b.b) * u, 1.0f};
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    tau = rng.unit() * 3.0;
    sinceHit = 100;
    hitPower = 0;
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
    sinceHit += f.delta;
    if (hit > kick + 0.2f) {
      sinceHit = 0;
      hitPower = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    tau += f.delta * f.speed * (1.0 + 1.2 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& c1 = f.colors[1];
    const Color& c2 = f.colors[2];
    const Color& c3 = f.colors[3];
    int n = std::clamp(m.pendulos, 10, kMax);
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    float top = f.height * 0.08f, bottom = f.height * 0.92f;
    float cx = f.width * 0.5f;
    float swing = f.width * 0.42f * m.amplitud * (0.85f + 0.2f * bass * amp);
    double period = std::max(5.0, double(m.ciclo));
    // Destello del golpe que baja por la fila.
    float sweep = float(sinceHit) * 2.2f;
    auto bobX = [&](int k, double t) {
      double phase = 6.283185307179586 * double(20 + k) * t / period;
      return cx + swing * float(std::cos(phase));
    };
    auto rowY = [&](int k) { return top + (bottom - top) * (float(k) + 0.5f) / float(n); };

    // Guías de cada fila y eje central.
    Path guides;
    for (int k = 0; k < n; k++) {
      float y = rowY(k);
      guides.moveTo(cx - swing, y).lineTo(cx + swing, y);
    }
    Paint guide;
    guide.strokeWidth = 1.0f * px;
    guide.color = c1.opacity(0.12f);
    c.path(guides, guide);
    Path axis;
    axis.moveTo(cx, top - 8.0f * px).lineTo(cx, bottom + 8.0f * px);
    Paint ax;
    ax.strokeWidth = 1.2f * px;
    ax.color = c2.opacity(0.18f + 0.2f * kick * amp);
    c.path(axis, ax);

    // Hilos desde el eje hasta cada bola.
    Path threads;
    for (int k = 0; k < n; k++) {
      float y = rowY(k);
      threads.moveTo(cx, y).lineTo(bobX(k, tau), y);
    }
    Paint thread;
    thread.strokeWidth = 1.4f * px;
    thread.blend = Blend::plus;
    thread.color = c2.opacity(std::clamp(0.22f * amp, 0.0f, 1.0f));
    c.path(threads, thread);

    // Línea que une las bolas: la serpiente.
    if (m.curva) {
      Path curve;
      for (int k = 0; k < n; k++) {
        float x = bobX(k, tau), y = rowY(k);
        if (k == 0) curve.moveTo(x, y); else curve.lineTo(x, y);
      }
      Paint glowLine;
      glowLine.blend = Blend::plus;
      glowLine.strokeWidth = 7.0f * px;
      glowLine.strokeJoin = 1;
      glowLine.strokeCap = 1;
      glowLine.color = c1.opacity(std::clamp((0.16f + 0.2f * bass) * f.glow * amp, 0.0f, 1.0f));
      c.path(curve, glowLine);
      Paint line;
      line.blend = Blend::plus;
      line.strokeWidth = 2.0f * px;
      line.strokeJoin = 1;
      line.strokeCap = 1;
      line.color = c3.opacity(std::clamp((0.55f + 0.3f * energy) * amp, 0.0f, 1.0f));
      c.path(curve, line);
    }

    // Estelas: posiciones de las bolas un poco antes en el tiempo.
    float radius = std::min(9.0f * px, (bottom - top) / float(n) * 0.36f) * (1.0f + 0.25f * bass * amp);
    if (m.estelas) {
      for (int j = kTrail; j >= 1; j--) {
        std::vector<Vec2> pts;
        pts.reserve(size_t(n));
        double t = tau - double(j) * 0.018 * (1.0 + drive);
        for (int k = 0; k < n; k++) pts.push_back({bobX(k, t), rowY(k)});
        float fade = 1.0f - float(j) / float(kTrail + 1);
        Paint tp;
        tp.blend = Blend::plus;
        tp.color = c1.opacity(std::clamp(0.22f * fade * amp, 0.0f, 1.0f));
        c.points(pts, radius * (0.45f + 0.5f * fade), tp);
      }
    }

    // Bolas: color por fila del rojo al amarillo, halo y núcleo.
    for (int k = 0; k < n; k++) {
      float t = float(k) / float(n - 1);
      Color col = mix3(c1, c2, c3, t);
      float x = bobX(k, tau), y = rowY(k);
      float d = (sweep - float(k) / float(n) * 1.2f);
      float lit = sinceHit < 2.0 ? hitPower * std::exp(-d * d * 30.0f) : 0.0f;
      float r = radius * (1.0f + 0.6f * lit);
      Paint halo = Paint::radial({x, y}, r * 3.2f, {col.opacity(std::clamp((0.35f + 0.5f * lit) * f.glow * amp, 0.0f, 1.0f)), col.opacity(0.0f)});
      halo.blend = Blend::plus;
      c.circle({x, y}, r * 3.2f, halo);
      Paint core = Paint::radial({x - r * 0.3f, y - r * 0.3f}, r * 1.3f,
                                 {Color{1.0f, 0.97f, 0.9f, 1.0f}, col, Color{col.r * 0.5f, col.g * 0.5f, col.b * 0.5f, 1.0f}}, {0.0f, 0.45f, 1.0f});
      c.circle({x, y}, r, core);
    }
  }
};
''';
