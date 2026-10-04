// Atractor de Clifford — velos de seda hechos de caos.
// Un punto salta una y otra vez según la fórmula de Clifford:
//   x' = sen(a·y) + c·cos(a·x),   y' = sen(b·x) + d·cos(b·y)
// y decenas de miles de saltos dibujan una figura que nunca se repite pero
// siempre tiene la misma forma: pliegues y velos como de seda. Cada punto se
// suma a la luz, así las zonas por donde pasa más veces brillan más. Hay
// siete formas probadas cuyos números a, b, c y d oscilan un poco, así los
// velos se pliegan sin parar, y cada ocho golpes (o cada diez segundos sin
// música) una forma se funde en otra; el encuadre se ajusta a cada figura. El
// color va del rojo de las zonas tranquilas al amarillo-blanco de los saltos
// largos. Los graves empujan la forma y cada golpe la hace destellar.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('miles', 'Miles de puntos', min: 6, max: 30, value: 18),
  CreatorModifier.slider('cambio', 'Velocidad de cambio', min: .2, max: 2.5, value: 1),
  CreatorModifier.slider('brillo', 'Brillo', min: .4, max: 2, value: 1),
  CreatorModifier.toggle('giro', 'Giro lento', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kPresets = 7;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double morph = 0, spin = 0, sinceShape = 0;
  float fade = 1;
  int beats = 0, from = 0, to = 0;
  mutable std::vector<float> raw;
  mutable std::array<std::vector<Vec2>, 3> groups;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Formas probadas y cuánto pueden variar sin caer en una órbita pobre
  // (comprobado recorriendo todas las variaciones posibles).
  static float preset(int k, float& a, float& b, float& c, float& d) {
    static const float P[kPresets][5] = {{-1.4f, 1.6f, 1.0f, 0.7f, 0.4f},    {1.5f, -1.8f, 1.6f, 0.9f, 0.4f},
                                         {-1.8f, -2.0f, -0.5f, -0.9f, 0.6f}, {-1.3f, -1.3f, -1.8f, -1.9f, 0.6f},
                                         {1.5f, -1.8f, 1.6f, 2.0f, 0.6f},    {-1.9f, -1.9f, -1.9f, -1.0f, 1.0f},
                                         {-1.6f, 1.6f, 0.7f, -1.0f, 0.6f}};
    a = P[k][0];
    b = P[k][1];
    c = P[k][2];
    d = P[k][3];
    return P[k][4];
  }

  // Itera una forma y deja sus puntos (en el espacio del atractor) en raw.
  void iterate(int k, int n, float wobble, float push, size_t offset) const {
    float a, b, c, d;
    float safe = preset(k, a, b, c, d);
    a += 0.05f * safe * std::sin(wobble);
    b += 0.05f * safe * std::sin(wobble * 0.8f + 1.0f);
    c += (0.04f * std::sin(wobble * 0.6f + 2.0f) + push) * safe;
    d += 0.04f * safe * std::sin(wobble * 0.7f + 3.0f);
    // Algunas variaciones caen en una órbita de pocos puntos: se prueban 400
    // saltos y, si casi no ocupan sitio, se usa la forma pura (siempre rica).
    {
      std::array<uint8_t, 1024> seen{};
      int distinct = 0;
      float x = 0.1f, y = 0.1f;
      for (int i = 0; i < 420; i++) {
        float nx = std::sin(a * y) + c * std::cos(a * x);
        float ny = std::sin(b * x) + d * std::cos(b * y);
        x = nx;
        y = ny;
        if (i < 20) continue;
        int gx = std::clamp(int((x + 3.0f) * 32.0f / 6.0f), 0, 31), gy = std::clamp(int((y + 3.0f) * 32.0f / 6.0f), 0, 31);
        if (!seen[size_t(gy * 32 + gx)]) {
          seen[size_t(gy * 32 + gx)] = 1;
          distinct++;
        }
      }
      if (distinct < 40) preset(k, a, b, c, d);
    }
    float x = 0.1f, y = 0.1f;
    for (int i = 0; i < n + 20; i++) {
      float nx = std::sin(a * y) + c * std::cos(a * x);
      float ny = std::sin(b * x) + d * std::cos(b * y);
      float jump = std::fabs(nx - x) + std::fabs(ny - y);
      x = nx;
      y = ny;
      if (i < 20) continue;
      size_t j = (offset + size_t(i - 20)) * 3;
      raw[j] = x;
      raw[j + 1] = y;
      raw[j + 2] = jump;
    }
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    morph = rng.unit() * 60.0;
    spin = rng.unit() * 6.28;
    sinceShape = 0;
    fade = 1;
    beats = 0;
    from = to = int(seed % uint32_t(kPresets));
    raw.assign(30000 * 3, 0.0f);
    for (auto& g : groups) g.reserve(30000);
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
    sinceShape += f.delta;
    // El fundido avanza antes de mirar cambios: si el cambio es por tiempo,
    // empieza en su instante exacto (igual a 30 y 60 FPS).
    fade = std::min(1.0f, fade + dt / 2.0f);
    bool next = false;
    double carry = -1.0;
    if (hit > kick + 0.2f && ++beats % 8 == 0) next = true;
    if (!mu.active && sinceShape > 10.0) {
      next = true;
      sinceShape -= 10.0;
      carry = sinceShape;
    }
    if (next) {
      from = to;
      to = (to + 1) % kPresets;
      fade = carry >= 0.0 ? std::min(1.0f, float(carry / 2.0)) : 0.0f;
      if (mu.active) sinceShape = 0;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    morph += f.delta * f.speed * m.cambio * (0.25 + 0.6 * drive);
    if (m.giro) spin += f.delta * f.speed * (0.05 + 0.08 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.7f,
                                                   {Color{std::min(1.0f, bg.r + f.colors[1].r * 0.05f), std::min(1.0f, bg.g + 0.01f), bg.b, 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    int total = std::clamp(m.miles, 1, 30) * 1000;
    float e = fade * fade * (3.0f - 2.0f * fade);
    int nTo = fade >= 1.0f ? total : int(float(total) * e);
    int nFrom = total - nTo;
    float wobble = float(std::fmod(morph, 1000.0));
    float push = 0.06f * bass * amp;
    if (nFrom > 0) iterate(from, nFrom, wobble, push, 0);
    if (nTo > 0) iterate(to, nTo, wobble, push, size_t(nFrom));
    int n = nFrom + nTo;
    // Encuadre según la figura real: ocupa la pantalla sea cual sea la forma.
    float minX = 1e9f, maxX = -1e9f, minY = 1e9f, maxY = -1e9f;
    for (int i = 0; i < n; i++) {
      minX = std::min(minX, raw[size_t(i) * 3]);
      maxX = std::max(maxX, raw[size_t(i) * 3]);
      minY = std::min(minY, raw[size_t(i) * 3 + 1]);
      maxY = std::max(maxY, raw[size_t(i) * 3 + 1]);
    }
    float cx = (minX + maxX) * 0.5f, cy = (minY + maxY) * 0.5f;
    float hx = std::max(0.05f, (maxX - minX) * 0.5f), hy = std::max(0.05f, (maxY - minY) * 0.5f);
    float rot = float(std::fmod(spin, 6.2831853));
    float cr = std::cos(rot), sr = std::sin(rot);
    float scale = m.giro ? std::min(f.width, f.height) * 0.47f / std::sqrt(hx * hx + hy * hy)
                         : std::min(f.width * 0.47f / hx, f.height * 0.47f / hy);
    scale *= 1.0f + 0.04f * kick * amp;
    float px = std::min(f.width, f.height) / 400.0f;
    for (auto& g : groups) g.clear();
    for (int i = 0; i < n; i++) {
      float x = raw[size_t(i) * 3] - cx, y = raw[size_t(i) * 3 + 1] - cy, jump = raw[size_t(i) * 3 + 2];
      float X = f.width * 0.5f + (x * cr - y * sr) * scale;
      float Y = f.height * 0.5f + (x * sr + y * cr) * scale;
      int g = jump < 1.1f ? 0 : (jump < 2.3f ? 1 : 2);
      groups[size_t(g)].push_back({X, Y});
    }
    float density = std::clamp(18000.0f / float(std::max(n, 1)), 0.5f, 3.0f);
    float base = 0.11f * m.brillo * density * (1.0f + 0.6f * kick + 0.3f * bass) * amp;
    for (int g = 0; g < 3; g++) {
      const Color& col = f.colors[size_t(1 + g)];
      Paint p;
      p.blend = Blend::plus;
      p.color = col.opacity(std::clamp(base * (g == 2 ? 1.3f : 1.0f), 0.0f, 1.0f));
      c.points(groups[size_t(g)], (0.9f + 0.3f * spark) * px, p);
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
