// Lluvia de Chispas — chispas de metal como las de una radial en cámara lenta.
// Uno, dos o tres puntos de corte (que se mueven despacio) lanzan chorros de
// chispas en abanico: cada chispa sale disparada, cae con la gravedad, se
// frena con el aire y se enfría del blanco al amarillo, naranja y rojo hasta
// apagarse. Se dibujan como estelas cuyo largo depende de su velocidad, y al
// llegar al suelo rebotan, a veces partiéndose en dos. El suelo brilla donde
// caen. La energía aumenta el chorro, cada golpe dispara una ráfaga y los
// graves hacen brillar el punto de corte.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('cantidad', 'Cantidad', min: .3, max: 2.5, value: 1),
  CreatorModifier.steps('fuentes', 'Puntos de corte', min: 1, max: 3, value: 2),
  CreatorModifier.choice('direccion', 'Dirección', options: ['Abanico', 'Abajo', 'Arriba']),
  CreatorModifier.toggle('rebote', 'Rebote en el suelo', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 1800;
  static constexpr double kStep = 1.0 / 120.0;
  struct Spark { float x, y, vx, vy, temp, cool; int bounces; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double sim = 0, emitAcc = 0;
  int64_t steps = 0;
  int burst = 0;
  float aspect = 2.0f;
  Random rng{1};
  std::vector<Spark> sparks, pieces;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Posición de cada punto de corte (en unidades del lado corto).
  Vec2 source(int k, int count, double t) const {
    float baseX = count == 1 ? 0.0f : (float(k) / float(count - 1) - 0.5f) * 0.6f;
    return {baseX + 0.08f * float(std::sin(t * 0.4 + double(k) * 2.1)), -aspect * 0.18f + 0.06f * float(std::sin(t * 0.33 + double(k)))};
  }

  void emit(int count, int dir, double t) {
    if (int(sparks.size()) >= kMax) return;
    int k = std::min(int(rng.unit() * float(count)), count - 1);
    Vec2 s = source(k, count, t);
    float a;
    if (dir == 1) a = 1.5708f + (rng.unit() - 0.5f) * 1.3f;
    else if (dir == 0) a = (k % 2 == 0 ? -0.35f : 3.14159f + 0.35f) + (rng.unit() - 0.5f) * 0.8f;
    else a = -1.5708f + (rng.unit() - 0.5f) * 1.0f;
    float speed = 0.9f + 1.6f * rng.unit();
    sparks.push_back({s.x, s.y, std::cos(a) * speed, std::sin(a) * speed, 1.0f, 0.45f + 0.7f * rng.unit(), 0});
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    sim = 0;
    emitAcc = 0;
    steps = 0;
    burst = 0;
    sparks.clear();
    sparks.reserve(kMax + 64);
    pieces.clear();
    pieces.reserve(kMax);
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
    if (hit > kick + 0.2f) burst += int((120.0f + 220.0f * hit) * m.cantidad);
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    aspect = f.height / std::max(std::min(f.width, f.height), 1.0f) * 0.5f * 2.0f;

    int count = std::clamp(m.fuentes, 1, 3);
    float floorY = aspect * 0.5f * 0.92f;
    sim += f.delta * f.speed;
    int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > 30) steps = target - 30;
    float h = float(kStep);
    while (steps < target) {
      steps++;
      double t = double(steps) * kStep;
      double rate = (260.0 + 900.0 * double(drive)) * double(m.cantidad);
      emitAcc += rate * kStep;
      while (emitAcc >= 1.0) {
        emitAcc -= 1.0;
        emit(count, m.direccion, t);
      }
      int b = std::min(burst, 60);
      for (int k = 0; k < b; k++) emit(count, m.direccion, t);
      burst -= b;
      pieces.clear();
      for (auto& s : sparks) {
        s.vy += 2.4f * h;
        float drag = 1.0f - 0.9f * h;
        s.vx *= drag;
        s.vy *= drag;
        s.x += s.vx * h;
        s.y += s.vy * h;
        s.temp -= s.cool * h;
        if (m.rebote && s.y > floorY && s.vy > 0.0f) {
          s.y = floorY;
          s.vy = -s.vy * 0.32f;
          s.vx = s.vx * 0.65f + (rng.unit() - 0.5f) * 0.4f;
          s.bounces++;
          s.temp -= 0.08f;
          if (s.bounces == 1 && rng.unit() < 0.35f && int(sparks.size() + pieces.size()) < kMax) {
            // Se parte en dos: el trozo nuevo se añade después del recorrido.
            Spark piece = s;
            piece.vx = -s.vx * 0.8f;
            piece.cool *= 1.4f;
            pieces.push_back(piece);
          }
        }
      }
      sparks.insert(sparks.end(), pieces.begin(), pieces.end());
      sparks.erase(std::remove_if(sparks.begin(), sparks.end(), [&](const Spark& s) {
        return s.temp <= 0.0f || s.bounces > 3 || std::fabs(s.x) > 1.5f || s.y > aspect;
      }), sparks.end());
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    Paint back;
    back.color = Color{bg.r, bg.g, bg.b, 1.0f};
    c.rect({0, 0, f.width, f.height}, back);
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    float cx = f.width * 0.5f, cy = f.height * 0.5f;
    int count = std::clamp(m.fuentes, 1, 3);
    float floorY = aspect * 0.5f * 0.92f;
    // Brillo del suelo bajo los puntos de corte.
    if (m.rebote) {
      for (int k = 0; k < count; k++) {
        Vec2 s = source(k, count, double(steps) * kStep);
        Vec2 q{cx + s.x * side, cy + floorY * side};
        Paint pool = Paint::radial(q, side * 0.35f, {f.colors[2].opacity(std::clamp((0.18f + 0.25f * drive + 0.2f * kick) * amp, 0.0f, 1.0f)), f.colors[2].opacity(0.0f)});
        pool.blend = Blend::plus;
        c.rect({q.x - side * 0.35f, q.y - side * 0.35f, side * 0.7f, side * 0.7f}, pool);
      }
      Paint line;
      line.strokeWidth = 1.2f * px;
      line.color = f.colors[1].opacity(0.25f);
      Path fl;
      fl.moveTo(0, cy + floorY * side).lineTo(f.width, cy + floorY * side);
      c.path(fl, line);
    }
    // Estelas por temperatura: blanca, amarilla, naranja, roja y brasa.
    const int buckets = 5;
    std::array<Path, buckets> paths;
    std::array<bool, buckets> used{};
    for (const auto& s : sparks) {
      int b = s.temp > 0.8f ? 0 : (s.temp > 0.6f ? 1 : (s.temp > 0.4f ? 2 : (s.temp > 0.2f ? 3 : 4)));
      float x1 = cx + s.x * side, y1 = cy + s.y * side;
      float x0 = x1 - s.vx * side * 0.045f, y0 = y1 - s.vy * side * 0.045f;
      paths[size_t(b)].moveTo(x0, y0).lineTo(x1, y1);
      used[size_t(b)] = true;
    }
    std::array<Color, buckets> cols = {Color{1.0f, 0.98f, 0.9f, 1.0f}, f.colors[3], f.colors[2], f.colors[1],
                                       Color{f.colors[1].r * 0.55f, f.colors[1].g * 0.4f, f.colors[1].b * 0.4f, 1.0f}};
    static const float widths[buckets] = {1.8f, 1.6f, 1.4f, 1.2f, 1.0f};
    for (int b = buckets - 1; b >= 0; b--) {
      if (!used[size_t(b)]) continue;
      Paint glow;
      glow.blend = Blend::plus;
      glow.strokeWidth = widths[b] * 3.5f * px;
      glow.strokeCap = 1;
      glow.color = cols[size_t(b)].opacity(std::clamp(0.1f * f.glow * amp, 0.0f, 1.0f));
      c.path(paths[size_t(b)], glow);
      Paint core;
      core.blend = Blend::plus;
      core.strokeWidth = widths[b] * px;
      core.strokeCap = 1;
      core.color = cols[size_t(b)].opacity(std::clamp(0.9f * amp, 0.0f, 1.0f));
      c.path(paths[size_t(b)], core);
    }
    // Punto de corte incandescente.
    for (int k = 0; k < count; k++) {
      Vec2 s = source(k, count, double(steps) * kStep);
      Vec2 q{cx + s.x * side, cy + s.y * side};
      float r = (18.0f + 10.0f * bass + 10.0f * kick) * px;
      Paint halo = Paint::radial(q, r, {Color{1.0f, 0.95f, 0.8f, std::clamp(0.9f * amp, 0.0f, 1.0f)}, f.colors[2].opacity(0.0f)});
      halo.blend = Blend::plus;
      c.circle(q, r, halo);
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
