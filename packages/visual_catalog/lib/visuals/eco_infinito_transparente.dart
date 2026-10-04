// Eco Infinito Transparente — el efecto de eco de MilkDrop hecho con la música.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Quince veces por segundo se guarda la forma de la música: un anillo cuya
// silueta sale del espectro, repetido en simetría. El anillo nuevo brilla en
// el centro y los anteriores quedan como ecos que se encogen, giran y cambian
// de color por el arcoíris hasta perderse en el infinito (o, al revés, crecen
// y salen de la pantalla). Como cada eco guarda lo que sonó un instante
// antes, la música deja un rastro visible. Los graves inflan el anillo, la
// energía acelera la caída y cada golpe gira el arcoíris y destella.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('ecos', 'Ecos', min: 6, max: 24, value: 16),
  CreatorModifier.choice('sentido', 'Sentido', options: ['Hacia dentro', 'Hacia fuera']),
  CreatorModifier.steps('simetria', 'Simetría', min: 2, max: 8, value: 5),
  CreatorModifier.slider('giro', 'Giro de los ecos', min: 0, max: 2, value: 1),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kSnaps = 24;
  static constexpr int kBands = 12;
  static constexpr int kPoints = 120;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, kBands> bands{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, hue = 0;
  int64_t captured = 0;
  // Instantáneas: el espectro y el momento en que se guardaron.
  std::array<std::array<float, kBands>, kSnaps> snaps{};
  std::array<double, kSnaps> snapTime{};
  std::array<float, kSnaps> snapBass{};
  int head = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static Color hsv(float h, float s, float v, float a) {
    h = h - std::floor(h);
    float r = std::clamp(std::fabs(h * 6.0f - 3.0f) - 1.0f, 0.0f, 1.0f);
    float g = std::clamp(2.0f - std::fabs(h * 6.0f - 2.0f), 0.0f, 1.0f);
    float b = std::clamp(2.0f - std::fabs(h * 6.0f - 4.0f), 0.0f, 1.0f);
    return {v * (1.0f - s + s * r), v * (1.0f - s + s * g), v * (1.0f - s + s * b), a};
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    clock = 0;
    hue = rng.unit();
    captured = 0;
    head = 0;
    for (auto& s : snaps) s.fill(0);
    snapTime.fill(0);
    snapBass.fill(0);
  }

  void update(const Frame& f) override {
    float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    body = follow(body, mu.body, 12.0f, 3.0f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    energy = follow(energy, mu.energy, 6.0f, 1.8f, dt);
    drive = follow(drive, mu.active ? std::pow(std::clamp(mu.energy, 0.0f, 1.0f), 0.8f) : 0.0f, 3.0f, 0.7f, dt);
    for (int b = 0; b < kBands; b++) {
      int k0 = b * 31 / kBands, k1 = std::max(k0 + 1, (b + 1) * 31 / kBands);
      float v = 0;
      for (int k = k0; k < k1 && k < 31; k++) v = std::max(v, mu.smoothSpectrum[size_t(k)]);
      bands[size_t(b)] = follow(bands[size_t(b)], v, 25.0f, 6.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    if (hit > kick + 0.2f) hue += 0.08 * hit;
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    hue += f.delta * f.speed * (0.03 + 0.05 * drive);
    clock += f.delta * f.speed * (1.0 + 1.2 * drive);
    // Instantáneas a ritmo fijo del reloj: cada una es un eco.
    int64_t target = int64_t(std::floor(clock * 15.0 + 1e-6));
    if (target - captured > kSnaps) captured = target - kSnaps;
    while (captured < target) {
      captured++;
      head = (head + 1) % kSnaps;
      snaps[size_t(head)] = bands;
      snapTime[size_t(head)] = double(captured) / 15.0;
      snapBass[size_t(head)] = bass;
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    Color tint = hsv(float(hue), 0.9f, 1.0f, 1.0f);
    int echoes = std::clamp(m.ecos, 6, kSnaps);
    int sym = std::clamp(m.simetria, 2, 8);
    bool inward = m.sentido == 0;
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    float baseR = side * (inward ? 0.36f : 0.1f);
    // Fracción entre instantáneas: los ecos se mueven sin saltos.
    float frac = float(clock * 15.0 - std::floor(clock * 15.0));
    const float q = inward ? 0.86f : 1.0f / 0.86f;
    Vec2 center{f.width * 0.5f, f.height * 0.5f};
    for (int k = echoes - 1; k >= 0; k--) {
      int idx = ((head - k) % kSnaps + kSnaps) % kSnaps;
      const auto& snap = snaps[size_t(idx)];
      float age = float(k) + frac;
      float s = std::pow(q, age);
      float rot = age * 0.07f * m.giro + float(snapTime[size_t(idx)]) * 0.05f;
      float fade = 1.0f - age / float(echoes + 1);
      if (fade <= 0.0f) continue;
      Path ring;
      double t0 = snapTime[size_t(idx)];
      for (int i = 0; i <= kPoints; i++) {
        float th = 6.2831853f * float(i) / float(kPoints);
        // Banda según el ángulo, en espejo para la simetría.
        float u = std::fabs(std::sin(th * float(sym) * 0.5f));
        float bi = u * float(kBands - 1);
        int b0 = int(bi);
        int b1 = std::min(b0 + 1, kBands - 1);
        float level = snap[size_t(b0)] + (snap[size_t(b1)] - snap[size_t(b0)]) * (bi - float(b0));
        float wob = 0.06f * float(std::sin(double(th) * double(sym) + t0 * 1.7));
        float r = baseR * s * (1.0f + wob + 0.5f * level * amp + 0.25f * snapBass[size_t(idx)] * amp);
        float a = th + rot;
        float x = center.x + r * std::cos(a), y = center.y + r * std::sin(a);
        if (i == 0) ring.moveTo(x, y); else ring.lineTo(x, y);
      }
      ring.close();
      Color col = hsv(float(hue) + age * 0.055f, 0.95f, 1.0f, 1.0f);
      float lit = (k == 0 ? 1.0f + 0.6f * kick : 1.0f) * amp;
      Paint glow;
      glow.blend = Blend::plus;
      glow.strokeWidth = (7.0f + 5.0f * bass) * px * std::sqrt(s);
      glow.strokeJoin = 1;
      glow.color = col.opacity(std::clamp(0.14f * fade * f.glow * lit, 0.0f, 1.0f));
      c.path(ring, glow);
      Paint line;
      line.blend = Blend::plus;
      line.strokeWidth = std::max(0.8f, (2.4f + 1.2f * energy) * px * std::sqrt(s));
      line.strokeJoin = 1;
      line.color = col.opacity(std::clamp((0.25f + 0.75f * fade) * lit, 0.0f, 1.0f));
      c.path(ring, line);
    }
    // Núcleo que late con los graves.
    float core = side * (0.03f + 0.03f * bass);
    Paint glowCore = Paint::radial(center, core * 4.0f, {tint.opacity(std::clamp((0.4f + 0.5f * kick) * amp, 0.0f, 1.0f)), tint.opacity(0.0f)});
    glowCore.blend = Blend::plus;
    c.circle(center, core * 4.0f, glowCore);
  }
};
''';
