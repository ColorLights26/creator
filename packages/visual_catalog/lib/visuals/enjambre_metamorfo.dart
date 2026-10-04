// Enjambre Metamorfo — miles de partículas que cambian de forma.
// Cada partícula tiene un lugar fijo en cinco figuras 3D (esfera, toro, cubo,
// doble hélice y una onda que se mueve) y viaja de una a otra con un pequeño
// retraso propio, así el cambio se ve como un enjambre que se reorganiza. La
// mitad es violeta y la otra mitad naranja; donde se juntan, la luz se suma.
// Gira despacio en 3D y las partículas cercanas son más grandes. Los graves
// la hacen respirar, el espectro la eriza, cada golpe fuerte la hace estallar
// hacia fuera antes de volver a formarse y cada ocho golpes cambia de figura.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('miles', 'Miles de partículas', min: 1, max: 6, value: 4),
  CreatorModifier.choice('forma', 'Forma', options: ['Auto', 'Esfera', 'Toro', 'Cubo', 'Doble hélice', 'Onda']),
  CreatorModifier.slider('giro', 'Velocidad de giro', min: 0, max: 2, value: 1),
  CreatorModifier.toggle('estallido', 'Estalla con los golpes', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 6000;
  struct Seed { float u, v, w, j; };
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, 8> bands{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double yaw = 0, pitch = 0, clock = 0, morph = 1, sinceShape = 0, blastAge = 100;
  int shapeFrom = 0, shapeTo = 0, autoShape = 0, beats = 0;
  float blastPower = 0;
  std::vector<Seed> seeds;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static std::array<float, 3> shape(int kind, const Seed& s, float t) {
    const float tau = 6.2831853f;
    switch (kind) {
      case 0: {
        float th = s.u * tau, ph = std::acos(2.0f * s.v - 1.0f);
        return {std::sin(ph) * std::cos(th), std::cos(ph), std::sin(ph) * std::sin(th)};
      }
      case 1: {
        float th = s.u * tau, ph = s.v * tau;
        float R = 0.72f, r = 0.3f;
        return {(R + r * std::cos(ph)) * std::cos(th), r * std::sin(ph), (R + r * std::cos(ph)) * std::sin(th)};
      }
      case 2: {
        int face = std::min(int(s.w * 6.0f), 5);
        float a = (s.u * 2.0f - 1.0f) * 0.7f, b = (s.v * 2.0f - 1.0f) * 0.7f, sgn = (face % 2 == 0) ? 0.7f : -0.7f;
        if (face < 2) return {sgn, a, b};
        if (face < 4) return {a, sgn, b};
        return {a, b, sgn};
      }
      case 3: {
        float th = s.u * tau * 2.5f + (s.w < 0.5f ? 0.0f : 3.14159265f) + t * 0.6f;
        float y = (s.u * 2.0f - 1.0f) * 1.05f;
        float r = 0.42f + 0.05f * (s.v - 0.5f);
        return {r * std::cos(th), y, r * std::sin(th)};
      }
      default: {
        float x = s.u * 2.0f - 1.0f, z = s.v * 2.0f - 1.0f;
        float y = 0.22f * std::sin(x * 4.0f + t * 1.6f) * std::cos(z * 3.0f - t * 1.1f);
        return {x * 0.95f, y, z * 0.95f};
      }
    }
  }

  void goTo(int next) {
    if (next == shapeTo) return;
    shapeFrom = shapeTo;
    shapeTo = next;
    morph = 0;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    yaw = rng.unit() * 6.2831853;
    pitch = 0;
    clock = 0;
    morph = 1;
    sinceShape = 0;
    blastAge = 100;
    blastPower = 0;
    shapeFrom = shapeTo = autoShape = 0;
    beats = 0;
    seeds.resize(kMax);
    for (auto& s : seeds) s = {rng.unit(), rng.unit(), rng.unit(), rng.unit()};
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
    for (int b = 0; b < 8; b++) {
      float v = 0;
      for (int k = b * 4; k < b * 4 + 4 && k < 31; k++) v = std::max(v, mu.smoothSpectrum[size_t(k)]);
      bands[size_t(b)] = follow(bands[size_t(b)], v, 18.0f, 4.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    blastAge += f.delta;
    sinceShape += f.delta;
    if (hit > kick + 0.2f) {
      beats++;
      if (hit > 0.6f && blastAge > 0.5) {
        blastAge = 0;
        blastPower = hit;
      }
      if (beats % 8 == 0) {
        autoShape = (autoShape + 1) % 5;
        sinceShape = 0;
      }
    }
    if (!mu.active && sinceShape > 6.0) {
      autoShape = (autoShape + 1) % 5;
      sinceShape -= 6.0;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    goTo(m.forma == 0 ? autoShape : m.forma - 1);
    morph = std::min(morph + f.delta / 2.0, 1.0);
    clock += f.delta * f.speed;
    yaw += f.delta * f.speed * m.giro * (0.3 + 0.6 * drive);
    pitch += f.delta * f.speed * m.giro * 0.11;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    const Color& violet = f.colors[1];
    const Color& orange = f.colors[2];
    c.rect({0, 0, f.width, f.height},
           Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.7f,
                         {Color{std::min(1.0f, bg.r + violet.r * 0.08f * (1.0f + bass)), std::min(1.0f, bg.g + violet.g * 0.05f),
                                std::min(1.0f, bg.b + violet.b * 0.1f * (1.0f + bass)), 1.0f},
                          Color{bg.r, bg.g, bg.b, 1.0f}}));
    int n = std::clamp(m.miles, 1, 6) * 1000;
    n = std::min(n, int(seeds.size()));
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    float scale = side * 0.46f * (1.0f + 0.14f * bass * amp);
    float cy = float(std::cos(yaw)), sy = float(std::sin(yaw));
    float tilt = 0.35f * float(std::sin(pitch));
    float cp = std::cos(tilt), sp = std::sin(tilt);
    float t = float(std::fmod(clock, 1000.0));
    float mo = float(morph);
    float blast = m.estallido && blastAge < 1.6 ? blastPower * float(std::exp(-blastAge * 2.4)) * float(std::min(blastAge * 12.0, 1.0)) : 0.0f;
    // Seis grupos: dos colores por tres profundidades.
    std::array<std::vector<Vec2>, 6> groups;
    for (auto& g : groups) g.reserve(size_t(n / 4));
    for (int i = 0; i < n; i++) {
      const Seed& s = seeds[size_t(i)];
      auto a = shape(shapeFrom, s, t);
      auto b = shape(shapeTo, s, t);
      float pr = std::clamp((mo - s.w * 0.4f) / 0.6f, 0.0f, 1.0f);
      pr = pr * pr * (3.0f - 2.0f * pr);
      float x = a[0] + (b[0] - a[0]) * pr, y = a[1] + (b[1] - a[1]) * pr, z = a[2] + (b[2] - a[2]) * pr;
      // Erizado con su banda y estallido hacia fuera.
      float len = std::sqrt(x * x + y * y + z * z) + 1e-4f;
      float push = 0.18f * bands[size_t(i % 8)] * amp + blast * (0.6f + 1.2f * s.j);
      x += x / len * push;
      y += y / len * push;
      z += z / len * push;
      float rx = x * cy + z * sy, rz = -x * sy + z * cy;
      float ry = y * cp - rz * sp;
      float rzz = y * sp + rz * cp;
      float persp = 2.4f / (3.0f + rzz);
      Vec2 q{f.width * 0.5f + rx * persp * scale, f.height * 0.5f - ry * persp * scale};
      int depth = rzz < -0.3f ? 0 : (rzz < 0.3f ? 1 : 2);
      groups[size_t((i & 1) * 3 + depth)].push_back(q);
    }
    for (int g = 5; g >= 0; g--) {
      int depth = g % 3;
      const Color& col = g < 3 ? violet : orange;
      float near = 1.0f - float(depth) * 0.35f;
      Paint p;
      p.blend = Blend::plus;
      p.color = col.opacity(std::clamp((0.35f + 0.45f * near + 0.3f * kick) * amp, 0.0f, 1.0f));
      c.points(groups[size_t(g)], (1.1f + 1.3f * near + 0.6f * spark) * px, p);
      if (depth == 0) {
        Paint halo;
        halo.blend = Blend::plus;
        halo.color = col.opacity(std::clamp(0.05f * f.glow * amp, 0.0f, 1.0f));
        c.points(groups[size_t(g)], 4.0f * px, halo);
      }
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
