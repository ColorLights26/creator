// Espiral de Primos — los números primos dibujan brazos y rayos.
// Cada número n se coloca a distancia n del centro y con un ángulo de n
// radianes. Si sólo se dibujan los primos aparece un patrón sorprendente: de
// cerca, seis brazos en espiral; al alejarse, cuarenta y cuatro; y de muy
// lejos, cientos de rayos rectos, todo por cómo se reparten los primos entre
// los restos al dividir. El zoom se acerca y se aleja sin parar, la espiral
// gira despacio y cada brazo tiene su color. Los graves hacen latir los
// puntos, cada golpe los enciende y la energía acelera el zoom. Con estela,
// cada primo arrastra una cola que se curva hacia dentro al girar: la espiral
// parece una galaxia en remolino, y cada golpe estira las colas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.slider('velocidad', 'Velocidad del zoom', min: .2, max: 2.5, value: 1),
  // ATMÓSFERA: de puntos nítidos a cometas con cola.
  CreatorModifier.slider('estela', 'Estela', min: 0, max: 1, value: 0),
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
    auto gl = glide(f);
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
    // Estela: cada primo deja una cola detrás de su giro, en tres tramos que
    // se apagan y adelgazan. Más puntos por cola cuando hay pocos primos; el
    // total se queda en unos 30 000. Se pintan encima sin sumar luz, así las
    // colas que se cruzan nunca queman a blanco.
    const float trail = gl.estela;
    const size_t shown = size_t(std::upper_bound(primes.begin(), primes.end(), int(pMax)) - primes.begin());
    const int tailPoints = trail > 0.005f ? std::clamp(int(30000 / std::max<size_t>(shown, 1)), 3, 28) : 0;
    // Con miles de primos las colas se acortan para que sigan viéndose los
    // rayos y quede oscuridad entre ellos.
    const float crowd = std::clamp(std::sqrt(1200.0f / float(std::max<size_t>(shown, 1))), 0.4f, 1.0f);
    const float tailLength = trail * dot * crowd * (26.0f + 6.0f * kick * amp);
    std::array<std::array<std::vector<Vec2>, 3>, buckets> tails;
    // El color sigue los brazos: de cerca por resto entre 6, luego entre 44.
    int mod = pMax < 2500.0f ? 6 : 44;
    for (int p : primes) {
      if (float(p) > pMax) break;
      double a = std::fmod(double(p), 6.283185307179586) + double(rot);
      float r = float(p) * s;
      Vec2 q{center.x + r * float(std::cos(a)), center.y + r * float(std::sin(a))};
      int b = std::min(int(float(p % mod) / float(mod) * float(buckets)), buckets - 1);
      groups[size_t(b)].push_back(q);
      if (tailPoints > 0) {
        // Paso angular de la cola: tramos de un punto, sin dar la vuelta cerca del centro.
        double step = double(std::min(tailLength / float(tailPoints) / std::max(r, dot), 1.2f / float(tailPoints)));
        for (int j = 1; j <= tailPoints; j++) {
          float u = float(j) / float(tailPoints);
          double aj = a - step * double(j);
          float rj = r * (1.0f - 0.12f * trail * u);
          tails[size_t(b)][size_t(std::min(2, (j - 1) * 3 / tailPoints))].push_back(
              {center.x + rj * float(std::cos(aj)), center.y + rj * float(std::sin(aj))});
        }
      }
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
      // Cada brazo con un acento de la paleta.
      const Color& col = f.colors[size_t(1 + b % 3)];
      float lit = (0.8f + 0.35f * bass + 0.3f * kick) * amp;
      if (tailPoints > 0) {
        const std::array<float, 3> fadeTail = {0.8f, 0.55f, 0.28f}, thinTail = {1.0f, 0.85f, 0.65f};
        for (int k = 0; k < 3; k++) {
          Paint tail;
          tail.color = Color{std::min(1.0f, col.r * lit), std::min(1.0f, col.g * lit), std::min(1.0f, col.b * lit),
                             std::clamp(fadeTail[size_t(k)] * std::min(1.0f, trail * 1.5f), 0.0f, 1.0f)};
          c.points(tails[size_t(b)][size_t(k)], dot * thinTail[size_t(k)], tail);
        }
      }
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
