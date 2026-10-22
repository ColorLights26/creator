// Reactiva Mejorada · Luciérnagas Sincronizadas — copia de «Luciérnagas Sincronizadas Transparente» (luciernagas_transparente.dart, que no se toca).
// Sin música no dibuja nada. Con música, el visual original se ve tanto
// como suena la música y cada golpe lo enciende más: sigue el ritmo.
//
// Luciérnagas Sincronizadas Transparente — cientos de luces que se ponen de acuerdo.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Cada luciérnaga tiene su propio reloj interno y destella cuando le toca.
// Al principio parpadean al azar, pero cada una adelanta o atrasa un poco su
// reloj según ve destellar a las demás (el modelo de Kuramoto), así que poco
// a poco aparecen grupos que destellan juntos hasta que todo el bosque se
// enciende a la vez, como en las montañas Great Smoky. Sin música el ciclo se
// repite: se desordenan y vuelven a sincronizarse. Con música, cada golpe
// empuja sus relojes hacia el destello y acaban latiendo con el ritmo.
// Cuando muchas destellan juntas, todo el aire brilla.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('cantidad', 'Luciérnagas', min: 80, max: 400, value: 240),
  CreatorModifier.slider('sincronia', 'Fuerza de sincronía', min: .2, max: 2, value: 1),
  CreatorModifier.choice('color', 'Luz', options: ['Lima', 'Ámbar', 'Fuego', 'Mezcla']),
  CreatorModifier.slider('deriva', 'Movimiento', min: 0, max: 2, value: 1),
  // MÚSICA (versión mejorada): qué la enciende. «Ritmo y volumen»: se ve
  // tanto como suena la música y cada golpe la enciende más.
  CreatorModifier.choice('aparece', 'Aparece con', options: ['Ritmo y volumen', 'Cada golpe', 'Cada tiempo', 'Caja']),
  // Cuánto dura cada golpe de luz.
  CreatorModifier.slider('permanencia', 'Cuánto se queda', min: .5, max: 2, value: 1),
];

const nativeSource = r'''
class Base_ final : public Scene {
  static constexpr int kMax = 400;
  static constexpr double kStep = 1.0 / 60.0;
  struct Fly { float x, y, depth, ax, ay, fx, fy, px, py, omega; double phase; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double sim = 0, cycle = 0;
  int64_t steps = 0;
  float pendingKick = 0, order = 0;
  Random rng{1};
  std::array<Fly, kMax> flies{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void scatter() {
    for (auto& fl : flies) fl.phase = double(rng.unit());
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    sim = 0;
    cycle = 0;
    steps = 0;
    pendingKick = 0;
    order = 0;
    for (auto& fl : flies) {
      fl.x = rng.unit();
      fl.y = rng.unit();
      fl.depth = 0.35f + 0.65f * rng.unit();
      fl.ax = 0.01f + 0.03f * rng.unit();
      fl.ay = 0.01f + 0.03f * rng.unit();
      fl.fx = 0.1f + 0.3f * rng.unit();
      fl.fy = 0.1f + 0.3f * rng.unit();
      fl.px = rng.unit() * 6.28f;
      fl.py = rng.unit() * 6.28f;
      fl.omega = 0.85f + 0.3f * rng.unit();
      fl.phase = double(rng.unit());
    }
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
    if (hit > kick + 0.2f) pendingKick = std::max(pendingKick, hit);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));

    int n = std::clamp(m.cantidad, 10, kMax);
    sim += f.delta * f.speed;
    int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > 30) steps = target - 30;
    while (steps < target) {
      steps++;
      cycle += kStep;
      // Sin música: 24 s de sincronía creciente y luego se desordenan.
      if (!mu.active && cycle > 24.0) {
        cycle -= 24.0;
        scatter();
      }
      float ramp = float(std::min(cycle / 16.0, 1.0));
      float K = m.sincronia * (mu.active ? 0.6f + 0.6f * drive : 1.6f * ramp * ramp);
      double cs = 0, sn = 0;
      for (int i = 0; i < n; i++) {
        double a = flies[size_t(i)].phase * 6.283185307179586;
        cs += std::cos(a);
        sn += std::sin(a);
      }
      cs /= n;
      sn /= n;
      double R = std::sqrt(cs * cs + sn * sn);
      double psi = std::atan2(sn, cs);
      order = float(R);
      for (int i = 0; i < n; i++) {
        Fly& fy = flies[size_t(i)];
        double a = fy.phase * 6.283185307179586;
        double d = double(fy.omega) + double(K) * R * std::sin(psi - a) / 6.283185307179586 * 6.0;
        fy.phase += d * kStep;
        // Un golpe adelanta los relojes hacia el destello.
        if (pendingKick > 0.0f) fy.phase += 0.12 * double(pendingKick) * std::sin(-a) / 6.283185307179586 * 6.0;
        fy.phase -= std::floor(fy.phase);
      }
      pendingKick = 0;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    int n = std::clamp(m.cantidad, 10, kMax);
    std::array<Color, 4> cols = {f.colors[1], f.colors[2], f.colors[3], f.colors[1]};
    int cm = std::clamp(m.color, 0, 3);
    const Color& main = cm == 3 ? f.colors[1] : cols[size_t(cm)];
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    double t = sim * m.deriva;
    // Grupos: 5 niveles de brillo × 2 profundidades × 2 colores.
    std::array<std::vector<Vec2>, 20> groups;
    std::vector<Vec2> dim;
    dim.reserve(size_t(n));
    for (auto& g : groups) g.reserve(size_t(n / 4));
    for (int i = 0; i < n; i++) {
      const Fly& fy = flies[size_t(i)];
      float x = (fy.x + fy.ax * float(std::sin(t * double(fy.fx) + double(fy.px)))) * f.width;
      float y = (fy.y + fy.ay * float(std::sin(t * double(fy.fy) + double(fy.py)))) * f.height;
      float b = std::exp(-float(fy.phase) * 7.0f);
      if (b < 0.06f) {
        dim.push_back({x, y});
        continue;
      }
      int level = std::min(4, int(b * 5.0f));
      int depth = fy.depth > 0.65f ? 1 : 0;
      int colorIdx = cm == 3 ? (i % 2) : 0;
      groups[size_t(level * 4 + depth * 2 + colorIdx)].push_back({x, y});
    }
    // Entre destellos se ven tenues, como brasas.
    Paint dimHalo;
    dimHalo.blend = Blend::plus;
    dimHalo.color = main.opacity(0.14f);
    c.points(dim, 5.0f * px, dimHalo);
    Paint dimP;
    dimP.blend = Blend::plus;
    // Sin fondo oscuro, las apagadas brillan más para seguir viéndose.
    dimP.color = main.opacity(0.75f);
    c.points(dim, 2.0f * px, dimP);
    for (int level = 0; level < 5; level++) {
      float b = (0.2f + 0.2f * float(level)) * amp;
      for (int depth = 0; depth < 2; depth++) {
        for (int ci = 0; ci < 2; ci++) {
          const auto& pts = groups[size_t(level * 4 + depth * 2 + ci)];
          if (pts.empty()) continue;
          const Color& col = ci == 0 ? main : f.colors[2];
          float size = (depth == 1 ? 1.0f : 0.6f) * px;
          Paint halo;
          halo.blend = Blend::plus;
          halo.color = col.opacity(std::clamp(b * 0.22f * f.glow, 0.0f, 1.0f));
          c.points(pts, size * (10.0f + 4.0f * bass), halo);
          Paint core;
          core.blend = Blend::plus;
          core.color = Color{std::min(1.0f, col.r * 0.6f + 0.4f), std::min(1.0f, col.g * 0.6f + 0.4f), std::min(1.0f, col.b * 0.6f + 0.4f), std::clamp(b, 0.0f, 1.0f)};
          c.points(pts, size * 2.6f, core);
        }
      }
    }
  }
};

// Versión reactiva mejorada: el visual original sigue vivo por debajo y se
// deja ver con el ritmo de la música. Cada golpe lo enciende y el volumen
// decide cuánto se ve. Sin música no dibuja nada.
class Visual final : public Scene {
  static constexpr double kGap_ = 0.3;  // como mucho unos 3 golpes de luz por segundo
  static constexpr double kStep_ = 1.0 / 60.0;
  static constexpr float kMin_ = 0.004f;
  static constexpr int kShows_ = 8;
  struct Show_ { double start = -100.0; float power = 0.0f; float span = 0.0f; };
  Base_ base_;
  std::array<Show_, kShows_> shows_{};
  int cursor_ = 0;
  double now_ = 0.0, acc_ = 0.0, last_ = -100.0;
  float eFast_ = 0.0f, peak_ = 0.0f, loud_ = 0.0f, kickMean_ = 0.0f;

  // Golpes de luz: entran en 40 ms y se apagan suave.
  float pulses_() const {
    float v = 0.0f;
    for (const Show_& s : shows_) {
      const double age = now_ - s.start;
      if (age < 0.0 || age >= double(s.span)) continue;
      float e = 1.0f;
      if (age < 0.04) {
        e = float(age / 0.04);
      } else {
        const float x = std::clamp(float((age - 0.04) / std::max(double(s.span) - 0.04, 0.05)), 0.0f, 1.0f);
        const float k = 1.0f - x;
        e = k * std::sqrt(k);
      }
      v = std::max(v, e * s.power);
    }
    return v;
  }

 public:
  void reset(uint32_t seed) override {
    Scene& base = base_;
    base.reset(seed);
    shows_ = {};
    cursor_ = 0;
    now_ = acc_ = 0.0;
    last_ = -100.0;
    eFast_ = peak_ = loud_ = kickMean_ = 0.0f;
  }
  void update(const Frame& f) override {
    Scene& base = base_;
    base.update(f);
    const Music& mu = f.music;
    now_ += f.delta;
    acc_ += f.delta;
    while (acc_ >= kStep_) {
      acc_ -= kStep_;
      eFast_ += (mu.energy - eFast_) * 0.19f;
      // Volumen: nivel absoluto y relativo al pico reciente; en silencio, cero.
      peak_ = std::max(peak_ * 0.9985f, eFast_);
      const float target = std::clamp(0.5f * eFast_ / std::max(peak_, 0.05f) + 1.2f * eFast_, 0.0f, 1.3f);
      loud_ += (target - loud_) * (target > loud_ ? 0.3f : 0.05f);
    }
    const auto m = modifiers(f);
    float kick = 0.0f, snare = 0.0f;
    bool beat = false;
    for (const Event& e : mu.events[0]) {
      const float s = std::max(e.strength, 0.05f);
      kick = std::max(kick, s);
      kickMean_ = kickMean_ <= 0.0f ? s : kickMean_ + (s - kickMean_) * 0.2f;
    }
    for (const Event& e : mu.events[1])
      if (e.band != 3) snare = std::max(snare, std::max(e.strength, 0.05f));
    if (!mu.events[2].empty()) beat = true;
    const int which = std::clamp(m.aparece, 0, 3);
    float s = 0.0f;
    if (which <= 1) s = kick > 0.0f ? kick / std::max(kickMean_, 0.05f) * 0.65f : 0.0f;  // golpe más fuerte, más luz
    else if (which == 2) s = beat ? 0.7f : 0.0f;
    else s = snare > 0.0f ? 0.8f : 0.0f;
    if (s <= 0.0f || now_ - last_ < kGap_) return;
    last_ = now_;
    shows_[size_t(cursor_)] = Show_{now_, std::clamp(s, 0.3f, 1.3f) * (0.35f + 0.8f * loud_), 0.45f * m.permanencia};
    cursor_ = (cursor_ + 1) % kShows_;
  }
  void render(const Frame& f, Canvas& c) const override {
    float v = pulses_();
    // «Ritmo y volumen»: mientras suena se ve en proporción al volumen.
    if (modifiers(f).aparece == 0) v = std::max(v, 0.6f * std::min(loud_, 1.0f));
    v = std::min(v, 1.0f);
    if (v < kMin_) return;
    const Scene& base = base_;
    if (v > 0.995f) {
      base.render(f, c);
      return;
    }
    c.saveLayer(v);
    base.render(f, c);
    c.restore();
  }
};
''';
