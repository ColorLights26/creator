// Caos de Péndulos Dobles Transparente — el efecto mariposa a la vista.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Cientos de péndulos dobles que empiezan en la misma posición salvo por una
// diferencia de millonésimas de radián. Al principio se mueven como uno solo
// (todos los colores juntos se ven blancos); al cabo de unos segundos el caos
// amplifica esa diferencia y el grupo se abre en un abanico de arcoíris que
// llena la pantalla. Cuando el caos es total, un golpe fuerte (o el tiempo,
// sin música) los vuelve a juntar en una posición nueva. Cuanto más corto el
// ciclo, antes se abre el abanico. La física es real (ecuaciones de Lagrange
// integradas con Runge-Kutta a 120 pasos por segundo), con el brazo de abajo
// más corto o más largo. Los graves engordan los brazos y cada golpe
// enciende las puntas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('pendulos', 'Péndulos', min: 50, max: 400, value: 220),
  // MOVIMIENTO y figura: brazo de abajo corto, latigazos cerrados que giran;
  // largo, barridos amplios que cruzan la pantalla.
  CreatorModifier.slider('brazo', 'Brazo inferior', min: .45, max: 2.2, value: 1),
  // Duración de cada ronda. También fija cuánto difieren los péndulos al
  // salir: con ciclos cortos el abanico se abre enseguida; con largos van
  // juntos, como uno solo, mucho más tiempo.
  CreatorModifier.slider('ciclo', 'Segundos de caos', min: 10, max: 40, value: 20),
  CreatorModifier.toggle('estelas', 'Estelas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 400;
  static constexpr int kTrail = 10;
  static constexpr double kStep = 1.0 / 120.0;
  struct State { double a1, a2, w1, w2; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double sim = 0, sinceReset = 0;
  int64_t steps = 0;
  int count = 0;
  bool resetPending = false;
  Random rng{1};
  std::vector<State> st;
  std::vector<float> trailX, trailY;
  int trailHead = 0, trailCount = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Ecuaciones del péndulo doble con masas iguales y brazos l1 y l2
  // (l1 + l2 = 2: el alcance total no cambia).
  static void deriv(const State& s, double l1, double l2, double& d1, double& d2) {
    const double g = 9.81;
    double delta = s.a1 - s.a2;
    double den = 3.0 - std::cos(2.0 * delta);
    d1 = (-3.0 * g * std::sin(s.a1) - g * std::sin(s.a1 - 2.0 * s.a2) -
          2.0 * std::sin(delta) * (s.w2 * s.w2 * l2 + s.w1 * s.w1 * l1 * std::cos(delta))) / (l1 * den);
    d2 = (2.0 * std::sin(delta) * (2.0 * s.w1 * s.w1 * l1 + 2.0 * g * std::cos(s.a1) + s.w2 * s.w2 * l2 * std::cos(delta))) / (l2 * den);
  }

  static State rk4(const State& s, double h, double l1, double l2) {
    double k1a, k1b, k2a, k2b, k3a, k3b, k4a, k4b;
    deriv(s, l1, l2, k1a, k1b);
    State s2{s.a1 + 0.5 * h * s.w1, s.a2 + 0.5 * h * s.w2, s.w1 + 0.5 * h * k1a, s.w2 + 0.5 * h * k1b};
    deriv(s2, l1, l2, k2a, k2b);
    State s3{s.a1 + 0.5 * h * s2.w1, s.a2 + 0.5 * h * s2.w2, s.w1 + 0.5 * h * k2a, s.w2 + 0.5 * h * k2b};
    deriv(s3, l1, l2, k3a, k3b);
    State s4{s.a1 + h * s3.w1, s.a2 + h * s3.w2, s.w1 + h * k3a, s.w2 + h * k3b};
    deriv(s4, l1, l2, k4a, k4b);
    return {s.a1 + h / 6.0 * (s.w1 + 2.0 * s2.w1 + 2.0 * s3.w1 + s4.w1),
            s.a2 + h / 6.0 * (s.w2 + 2.0 * s2.w2 + 2.0 * s3.w2 + s4.w2),
            s.w1 + h / 6.0 * (k1a + 2.0 * k2a + 2.0 * k3a + k4a),
            s.w2 + h / 6.0 * (k1b + 2.0 * k2b + 2.0 * k3b + k4b)};
  }

  // Brazos de un péndulo con el brazo de abajo [ratio] veces el de arriba.
  static void armLengths(float ratio, double& l1, double& l2) {
    const double r = std::clamp(double(ratio), 0.45, 2.2);
    l1 = 2.0 / (1.0 + r);
    l2 = 2.0 - l1;
  }

  void restart(double cycle) {
    double a = 3.14159265358979 * (0.62 + 0.3 * double(rng.unit()));
    double b = a + (double(rng.unit()) - 0.5) * 1.2;
    if (rng.unit() < 0.5f) {
      a = -a;
      b = -b;
    }
    // El caos multiplica por 10 la diferencia inicial cada ~1,4 s: un ciclo
    // corto parte de diferencias mayores y se abre antes. El abanico se abre
    // hacia el 30% del ciclo (20 s: 1,5e-6 rad, como siempre).
    const double spread = 1.5e-6 * std::exp(0.6 * (20.0 - std::clamp(cycle, 10.0, 40.0)));
    for (int i = 0; i < count; i++) {
      double e = spread * double(i);
      st[size_t(i)] = {a + e, b, 0.0, 0.0};
    }
    sinceReset = 0;
    resetPending = false;
    std::fill(trailX.begin(), trailX.end(), 0.0f);
    std::fill(trailY.begin(), trailY.end(), 0.0f);
    trailHead = -1;
    trailCount = 0;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    sim = 0;
    steps = 0;
    count = 0;
    st.assign(kMax, State{0, 0, 0, 0});
    trailX.assign(size_t(kMax * kTrail), 0.0f);
    trailY.assign(size_t(kMax * kTrail), 0.0f);
    trailHead = -1;
    trailCount = 0;
    sinceReset = 0;
    resetPending = false;
  }

  void update(const Frame& f) override {
    auto m = modifiers(f);
    auto gl = glide(f);
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

    int want = std::clamp(m.pendulos, 10, kMax);
    if (want != count) {
      count = want;
      restart(double(m.ciclo));
    }
    // Con música, un golpe fuerte reúne a los péndulos cuando ya hay caos.
    if (beat && hit > 0.6f && sinceReset > double(m.ciclo) * 0.6) resetPending = true;
    double l1, l2;
    armLengths(gl.brazo, l1, l2);
    sim += f.delta * f.speed;
    int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > 60) steps = target - 60;
    while (steps < target) {
      for (int i = 0; i < count; i++) st[size_t(i)] = rk4(st[size_t(i)], kStep, l1, l2);
      steps++;
      sinceReset += kStep;
      // Estela de la punta: una muestra cada 4 pasos.
      if (steps % 4 == 0) {
        trailHead = (trailHead + 1) % kTrail;
        trailCount = std::min(trailCount + 1, kTrail);
        for (int i = 0; i < count; i++) {
          const State& s = st[size_t(i)];
          trailX[size_t(i * kTrail + trailHead)] = float(l1 * std::sin(s.a1) + l2 * std::sin(s.a2));
          trailY[size_t(i * kTrail + trailHead)] = float(l1 * std::cos(s.a1) + l2 * std::cos(s.a2));
        }
      }
      if (resetPending || sinceReset > double(m.ciclo)) restart(double(m.ciclo));
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    if (count <= 0) return;
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    float L = side * 0.3f;
    double l1, l2;
    armLengths(glide(f).brazo, l1, l2);
    const float L1 = L * float(l1), L2 = L * float(l2);
    Vec2 pivot{f.width * 0.5f, f.height * 0.42f};
    const int groups = 12;
    // Colores del grupo: arcoíris entre los tres colores de la paleta.
    auto groupColor = [&](int g) {
      float t = float(g) / float(groups - 1);
      const Color& a = f.colors[1];
      const Color& b = f.colors[2];
      const Color& d = f.colors[3];
      if (t < 0.5f) {
        float u = t * 2.0f;
        return Color{a.r + (b.r - a.r) * u, a.g + (b.g - a.g) * u, a.b + (b.b - a.b) * u, 1.0f};
      }
      float u = (t - 0.5f) * 2.0f;
      return Color{b.r + (d.r - b.r) * u, b.g + (d.g - b.g) * u, b.b + (d.b - b.b) * u, 1.0f};
    };
    std::array<Path, groups> arms, trails;
    std::array<std::vector<Vec2>, groups> tips;
    for (auto& t : tips) t.reserve(size_t(count / groups + 2));
    for (int i = 0; i < count; i++) {
      int g = std::min(groups - 1, i * groups / count);
      const State& s = st[size_t(i)];
      float x1 = pivot.x + L1 * float(std::sin(s.a1)), y1 = pivot.y + L1 * float(std::cos(s.a1));
      float x2 = x1 + L2 * float(std::sin(s.a2)), y2 = y1 + L2 * float(std::cos(s.a2));
      arms[size_t(g)].moveTo(pivot.x, pivot.y).lineTo(x1, y1).lineTo(x2, y2);
      tips[size_t(g)].push_back({x2, y2});
      if (m.estelas && trailHead >= 0) {
        for (int k = 0; k < trailCount; k++) {
          int idx = ((trailHead - k) % kTrail + kTrail) % kTrail;
          float tx = pivot.x + L * trailX[size_t(i * kTrail + idx)];
          float ty = pivot.y + L * trailY[size_t(i * kTrail + idx)];
          if (k == 0) trails[size_t(g)].moveTo(x2, y2);
          trails[size_t(g)].lineTo(tx, ty);
        }
      }
    }
    float alpha = std::clamp(4.2f / std::sqrt(float(count)) * amp, 0.05f, 1.0f);
    for (int g = 0; g < groups; g++) {
      Color col = groupColor(g);
      if (m.estelas) {
        Paint tp;
        tp.blend = Blend::plus;
        tp.strokeWidth = 1.6f * px;
        tp.strokeJoin = 1;
        tp.color = col.opacity(std::clamp(alpha * 0.7f * f.glow, 0.0f, 1.0f));
        c.path(trails[size_t(g)], tp);
      }
      Paint arm;
      arm.blend = Blend::plus;
      arm.strokeWidth = (1.7f + 1.4f * bass) * px;
      arm.strokeJoin = 1;
      arm.strokeCap = 1;
      arm.color = col.opacity(std::clamp(alpha * (0.8f + 0.4f * energy), 0.0f, 1.0f));
      c.path(arms[size_t(g)], arm);
      Paint tip;
      tip.blend = Blend::plus;
      tip.color = col.opacity(std::clamp((0.35f + 0.5f * kick) * amp, 0.0f, 1.0f));
      c.points(tips[size_t(g)], (2.6f + 2.5f * kick) * px, tip);
    }
    Paint hub;
    hub.color = Color{1.0f, 0.97f, 0.9f, 1.0f};
    c.circle(pivot, 3.5f * px, hub);
  }
};
''';
