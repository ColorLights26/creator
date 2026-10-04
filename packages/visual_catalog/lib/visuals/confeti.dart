// Confeti — capa transparente de fiesta para poner encima de otro visual.
// Dos cañones en las esquinas de abajo disparan ráfagas de papelitos que
// suben, se frenan con el aire y caen girando. Cada papelito es un
// rectángulo, una tira o una lentejuela que da vueltas en 3D: se estrecha al
// ponerse de canto y muestra su cara trasera más oscura. Con cada golpe
// dispara un cañón (alternando), en los golpes fuertes disparan los dos y
// estalla otro puñado en el centro, y la energía hace llover confeti desde
// arriba. Sin música hay una ráfaga cada pocos segundos. El fondo es
// transparente: sólo se ve el confeti.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('cantidad', 'Cantidad', min: .3, max: 2, value: 1),
  CreatorModifier.slider('tamano', 'Tamaño', min: .5, max: 2, value: 1),
  CreatorModifier.choice('colores', 'Colores', options: ['Arcoíris', 'Paleta', 'Dorado']),
  CreatorModifier.toggle('lluvia', 'Lluvia desde arriba', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 900;
  static constexpr double kStep = 1.0 / 60.0;
  struct Piece { float x, y, px, py, vx, vy, angle, spin, flip, flipSpeed, w, h; uint8_t color, shape; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double sim = 0, nextIdle = 0.3, rainAcc = 0;
  int64_t steps = 0;
  int idleCount = 0, side = 0;
  int pendingLeft = 0, pendingRight = 0, pendingCenter = 0;
  float width = 1, height = 1;
  Random rng{1};
  std::vector<Piece> pieces;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  void spawn(float x, float y, float vx, float vy, float sizeMul) {
    if (int(pieces.size()) >= kMax) return;
    float s = std::min(width, height);
    Piece p;
    p.x = p.px = x;
    p.y = p.py = y;
    p.vx = vx;
    p.vy = vy;
    p.angle = rng.unit() * 6.2831853f;
    p.spin = (rng.unit() - 0.5f) * 9.0f;
    p.flip = rng.unit() * 6.2831853f;
    p.flipSpeed = 4.0f + 9.0f * rng.unit();
    p.shape = uint8_t(std::min(int(rng.unit() * 3.0f), 2));
    float base = s * 0.012f * sizeMul * (0.7f + 0.6f * rng.unit());
    p.w = p.shape == 1 ? base * 0.45f : base;
    p.h = p.shape == 1 ? base * 2.6f : (p.shape == 2 ? base : base * 1.5f);
    p.color = uint8_t(std::min(int(rng.unit() * 6.0f), 5));
    pieces.push_back(p);
  }

  void cannon(bool left, int count, float sizeMul) {
    float s = std::min(width, height);
    for (int i = 0; i < count; i++) {
      float a = (left ? -1.05f : -2.09f) + (rng.unit() - 0.5f) * 0.55f;
      float speed = s * (1.9f + 1.4f * rng.unit());
      spawn(left ? 0.0f : width, height * 1.01f, std::cos(a) * speed, std::sin(a) * speed, sizeMul);
    }
  }

  void pop(int count, float sizeMul) {
    float s = std::min(width, height);
    float cx = width * (0.3f + 0.4f * rng.unit()), cy = height * (0.3f + 0.25f * rng.unit());
    for (int i = 0; i < count; i++) {
      float a = rng.unit() * 6.2831853f;
      float speed = s * (0.4f + 1.3f * rng.unit());
      spawn(cx, cy, std::cos(a) * speed, std::sin(a) * speed - s * 0.5f, sizeMul);
    }
  }

  void step(float rainRate, float amount, float sizeMul, bool rain) {
    float s = std::min(width, height);
    float dt = float(kStep);
    double t = double(steps) * kStep;
    // Sin música: ráfagas a su hora exacta, alternando cañones y estallidos.
    if (t >= nextIdle) {
      int kind = idleCount % 4;
      int n = int(55.0f * amount);
      if (kind == 0) cannon(true, n, sizeMul);
      if (kind == 1) cannon(false, n, sizeMul);
      if (kind == 2) { cannon(true, n / 2, sizeMul); cannon(false, n / 2, sizeMul); }
      if (kind == 3) pop(n, sizeMul);
      idleCount++;
      nextIdle += 3.2;
    }
    if (pendingLeft > 0) { cannon(true, pendingLeft, sizeMul); pendingLeft = 0; }
    if (pendingRight > 0) { cannon(false, pendingRight, sizeMul); pendingRight = 0; }
    if (pendingCenter > 0) { pop(pendingCenter, sizeMul); pendingCenter = 0; }
    if (rain) {
      rainAcc += double(rainRate) * kStep;
      while (rainAcc >= 1.0) {
        rainAcc -= 1.0;
        spawn(rng.unit() * width, -s * 0.03f, (rng.unit() - 0.5f) * s * 0.2f, s * 0.15f, sizeMul);
      }
    }
    const float g = s * 1.35f;
    const float drag = 2.4f;
    float k = std::exp(-drag * dt);
    for (auto& p : pieces) {
      p.px = p.x;
      p.py = p.y;
      // Los papelitos planean: más freno cuanto más de cara caen.
      float face = std::fabs(std::cos(p.flip));
      p.vy += g * dt;
      float kk = k * (1.0f - 0.02f * face);
      p.vx *= kk;
      p.vy *= kk;
      p.vx += std::sin(p.flip * 0.5f + p.angle) * s * 0.35f * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.angle += p.spin * dt;
      p.flip += p.flipSpeed * dt;
    }
    pieces.erase(std::remove_if(pieces.begin(), pieces.end(), [&](const Piece& p) {
      return p.y > height + s * 0.08f || p.x < -s * 0.3f || p.x > width + s * 0.3f;
    }), pieces.end());
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    sim = 0;
    steps = 0;
    nextIdle = 0.3;
    rainAcc = 0;
    idleCount = 0;
    side = 0;
    pendingLeft = pendingRight = pendingCenter = 0;
    pieces.clear();
    pieces.reserve(kMax + 64);
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
    width = f.width;
    height = f.height;
    if (beat) {
      int n = int((14.0f + 30.0f * hit) * m.cantidad);
      if (hit > 0.75f) {
        pendingLeft += n;
        pendingRight += n;
        pendingCenter += n;
      } else if ((side++ & 1) == 0) {
        pendingLeft += n;
      } else {
        pendingRight += n;
      }
    }
    if (fl > 0.5f) pendingCenter += int(30.0f * m.cantidad);
    // Con música las ráfagas las marcan los golpes, no el reloj.
    if (mu.active) nextIdle = double(steps) * kStep + 3.2;
    sim += f.delta * f.speed;
    int64_t target = int64_t(std::floor(sim / kStep + 1e-6));
    if (target - steps > 30) steps = target - 30;
    float rainRate = (6.0f + 40.0f * energy) * m.cantidad;
    while (steps < target) {
      step(rainRate, m.cantidad, m.tamano, m.lluvia);
      steps++;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    // Entre el paso anterior y el último: movimiento suave a cualquier FPS.
    float a = float(std::clamp(sim / kStep - double(steps), 0.0, 1.0));
    std::array<Color, 6> cols;
    if (m.colores == 0) {
      cols = {Color{1.0f, 0.15f, 0.2f, 1.0f}, Color{1.0f, 0.55f, 0.0f, 1.0f}, Color{1.0f, 0.88f, 0.1f, 1.0f},
              Color{0.2f, 0.85f, 0.3f, 1.0f}, Color{0.2f, 0.45f, 1.0f, 1.0f}, Color{1.0f, 0.3f, 0.75f, 1.0f}};
    } else if (m.colores == 1) {
      cols = {f.colors[1], f.colors[2], f.colors[3], Color{1, 1, 1, 1}, f.colors[1], f.colors[2]};
    } else {
      cols = {Color{1.0f, 0.82f, 0.3f, 1.0f}, Color{0.95f, 0.7f, 0.2f, 1.0f}, Color{1.0f, 0.93f, 0.6f, 1.0f},
              Color{0.85f, 0.6f, 0.15f, 1.0f}, Color{1.0f, 1.0f, 0.95f, 1.0f}, Color{1.0f, 0.75f, 0.35f, 1.0f}};
    }
    // Cara delantera y trasera de cada color.
    std::array<Path, 12> paths;
    for (const auto& p : pieces) {
      float x = p.px + (p.x - p.px) * a, y = p.py + (p.y - p.py) * a;
      float cf = std::cos(p.flip);
      float hw = 0.5f * p.w * std::max(0.08f, std::fabs(cf));
      float hh = 0.5f * p.h;
      float ca = std::cos(p.angle), sa = std::sin(p.angle);
      Path& path = paths[size_t(p.color * 2 + (cf < 0.0f ? 1 : 0))];
      path.moveTo(x + (-hw) * ca - (-hh) * sa, y + (-hw) * sa + (-hh) * ca)
          .lineTo(x + hw * ca - (-hh) * sa, y + hw * sa + (-hh) * ca)
          .lineTo(x + hw * ca - hh * sa, y + hw * sa + hh * ca)
          .lineTo(x + (-hw) * ca - hh * sa, y + (-hw) * sa + hh * ca)
          .close();
    }
    float lit = (0.9f + 0.2f * kick) * amp;
    for (int k = 0; k < 12; k++) {
      const Color& col = cols[size_t(k / 2)];
      float shade = (k % 2 == 0 ? 1.0f : 0.62f) * lit;
      Paint p;
      p.color = Color{std::min(1.0f, col.r * shade), std::min(1.0f, col.g * shade), std::min(1.0f, col.b * shade), 1.0f};
      c.path(paths[size_t(k)], p);
    }
    (void)flash;
  }
};
''';
