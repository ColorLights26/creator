// Espiral de Primos — los números primos dibujan brazos y rayos.
// Cada número n se coloca a distancia n del centro y con un ángulo de n
// radianes. Si sólo se dibujan los primos aparece un patrón sorprendente: de
// cerca, seis brazos en espiral; al alejarse, cuarenta y cuatro; y de muy
// lejos, cientos de rayos rectos, todo por cómo se reparten los primos entre
// los restos al dividir. El zoom se acerca y se aleja sin parar, la espiral
// gira despacio y cada brazo tiene su color. Los graves hacen latir los
// puntos, cada golpe los enciende y la energía acelera el zoom.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('velocidad', 'Velocidad del zoom', min: .2, max: 2.5, value: 1),
  CreatorModifier.choice('colores', 'Colores', options: ['Brazos', 'Arcoíris', 'Fuego']),
  CreatorModifier.slider('tamano', 'Tamaño de puntos', min: .5, max: 2, value: 1),
  CreatorModifier.toggle('noprimos', 'Mostrar no primos', value: false),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kLimit = 140000;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double zoom = 0, spin = 0;
  std::vector<int> primes;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static Color hsv(float h) {
    h = h - std::floor(h);
    return {std::clamp(std::fabs(h * 6.0f - 3.0f) - 1.0f, 0.0f, 1.0f), std::clamp(2.0f - std::fabs(h * 6.0f - 2.0f), 0.0f, 1.0f),
            std::clamp(2.0f - std::fabs(h * 6.0f - 4.0f), 0.0f, 1.0f), 1.0f};
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    zoom = rng.unit() * 6.28;
    spin = 0;
    // Criba de Eratóstenes, una sola vez.
    std::vector<uint8_t> composite(kLimit + 1, 0);
    primes.clear();
    primes.reserve(13000);
    for (int i = 2; i <= kLimit; i++) {
      if (composite[size_t(i)]) continue;
      primes.push_back(i);
      for (long long j = (long long)i * i; j <= kLimit; j += i) composite[size_t(j)] = 1;
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
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    zoom += f.delta * f.speed * m.velocidad * (0.09 + 0.12 * drive);
    spin += f.delta * f.speed * (0.04 + 0.06 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    c.rect({0, 0, f.width, f.height}, Paint::radial({f.width * 0.5f, f.height * 0.5f}, std::max(f.width, f.height) * 0.7f,
                                                   {Color{std::min(1.0f, bg.r + 0.05f), std::min(1.0f, bg.g + 0.02f), std::min(1.0f, bg.b + 0.06f), 1.0f},
                                                    Color{bg.r, bg.g, bg.b, 1.0f}}));
    // Zoom en escala logarítmica: de ver 300 números a ver casi 90 000.
    float w = 0.5f - 0.5f * float(std::cos(zoom));
    float pMax = std::exp(std::log(300.0f) + (std::log(float(kLimit) * 0.62f) - std::log(300.0f)) * w);
    float R = 0.5f * std::sqrt(f.width * f.width + f.height * f.height);
    float s = R / pMax;
    float rot = float(std::fmod(spin, 6.2831853));
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    float dot = std::clamp(0.5f * s + 1.6f * px, 1.2f * px, 8.0f * px) * m.tamano * (1.0f + 0.35f * kick * amp);
    Vec2 center{f.width * 0.5f, f.height * 0.5f};
    const int buckets = 11;
    std::array<std::vector<Vec2>, buckets> groups;
    for (auto& g : groups) g.reserve(primes.size() / 8);
    // El color sigue los brazos: de cerca por resto entre 6, luego entre 44.
    int mod = pMax < 2500.0f ? 6 : 44;
    for (int p : primes) {
      if (float(p) > pMax) break;
      double a = std::fmod(double(p), 6.283185307179586) + double(rot);
      float r = float(p) * s;
      Vec2 q{center.x + r * float(std::cos(a)), center.y + r * float(std::sin(a))};
      int b = int(float(p % mod) / float(mod) * float(buckets));
      groups[size_t(std::min(b, buckets - 1))].push_back(q);
    }
    if (m.noprimos && pMax < 4000.0f) {
      std::vector<Vec2> rest;
      rest.reserve(size_t(pMax));
      size_t k = 0;
      for (int n = 1; float(n) <= pMax; n++) {
        while (k < primes.size() && primes[k] < n) k++;
        if (k < primes.size() && primes[k] == n) continue;
        double a = std::fmod(double(n), 6.283185307179586) + double(rot);
        float r = float(n) * s;
        rest.push_back({center.x + r * float(std::cos(a)), center.y + r * float(std::sin(a))});
      }
      Paint dim;
      dim.color = Color{0.45f, 0.42f, 0.5f, 0.35f};
      c.points(rest, dot * 0.55f, dim);
    }
    for (int b = 0; b < buckets; b++) {
      float t = float(b) / float(buckets - 1);
      Color col;
      if (m.colores == 1) {
        col = hsv(t * 0.9f);
      } else if (m.colores == 2) {
        const Color& a0 = f.colors[1];
        const Color& a1 = f.colors[3];
        col = Color{a0.r + (a1.r - a0.r) * t, a0.g + (a1.g - a0.g) * t, a0.b + (a1.b - a0.b) * t, 1.0f};
      } else {
        std::array<Color, 3> pal = {f.colors[1], f.colors[2], f.colors[3]};
        col = pal[size_t(b % 3)];
      }
      float lit = (0.8f + 0.35f * bass + 0.3f * kick) * amp;
      Paint halo;
      halo.blend = Blend::plus;
      halo.color = col.opacity(std::clamp(0.16f * f.glow * amp, 0.0f, 1.0f));
      if (dot > 2.0f * px) c.points(groups[size_t(b)], dot * 2.4f, halo);
      Paint core;
      core.blend = Blend::plus;
      core.color = Color{std::min(1.0f, col.r * lit), std::min(1.0f, col.g * lit), std::min(1.0f, col.b * lit), 1.0f};
      c.points(groups[size_t(b)], dot, core);
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
