// Cuerdas Vibrantes — cuerdas de guitarra vistas con el efecto de obturador.
// Cuando se graba una guitarra desde dentro con el móvil, el obturador lee la
// imagen línea a línea y la vibración de cada cuerda aparece como una
// serpiente de ondas que se desliza. Aquí las cuerdas cruzan la pantalla de
// arriba abajo: las graves son gruesas, entorchadas y doradas, con ondas
// largas; las agudas son finas, plateadas y con ondas cortas. Cada cuerda
// vibra con su banda de la música y está fija en sus extremos. Cada golpe
// rasguea todas las cuerdas una tras otra (y sin música se rasguea solo cada
// pocos segundos); una luz roja las ilumina desde abajo.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('cuerdas', 'Cuerdas', min: 4, max: 12, value: 6),
  CreatorModifier.slider('amplitud', 'Amplitud', min: .4, max: 2, value: 1),
  CreatorModifier.slider('ondas', 'Ondas por cuerda', min: .5, max: 2, value: 1),
  CreatorModifier.toggle('trastes', 'Trastes', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 12;
  static constexpr int kPoints = 150;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  std::array<float, kMax> bands{};
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, strumAge = 100, sinceIdle = 0;
  float strumPower = 0;
  bool strumUp = false;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    bands.fill(0);
    clock = rng.unit() * 20.0;
    strumAge = 0.3;
    strumPower = 0.8f;
    sinceIdle = 0;
    strumUp = false;
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
    int n = std::clamp(m.cuerdas, 2, kMax);
    for (int i = 0; i < n; i++) {
      int b0 = i * 26 / n, b1 = std::max(b0 + 1, (i + 1) * 26 / n);
      float v = 0;
      for (int b = b0; b < b1; b++) v = std::max(v, mu.smoothSpectrum[size_t(b)]);
      bands[size_t(i)] = follow(bands[size_t(i)], v, 25.0f, 5.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    strumAge += f.delta;
    sinceIdle += f.delta;
    if (hit > kick + 0.2f) {
      strumAge = 0;
      strumPower = hit;
      strumUp = !strumUp;
      sinceIdle = 0;
    }
    if (!mu.active && sinceIdle > 2.4) {
      sinceIdle -= 2.4;
      strumAge = sinceIdle;
      strumPower = 0.85f;
      strumUp = !strumUp;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta * f.speed * (1.0 + 0.6 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    const Color& red = f.colors[1];
    const Color& gold = f.colors[2];
    const Color& silver = f.colors[3];
    c.rect({0, 0, f.width, f.height}, Paint::linear({0, 0}, {0, f.height}, {Color{bg.r, bg.g, bg.b, 1.0f}, Color{std::min(1.0f, bg.r + red.r * 0.12f), std::min(1.0f, bg.g + red.g * 0.04f), bg.b, 1.0f}}));
    // Luz roja desde abajo, más fuerte con los graves.
    Paint glowBg = Paint::radial({f.width * 0.5f, f.height * 1.05f}, f.height * 0.75f,
                                 {red.opacity(std::clamp((0.35f + 0.35f * bass) * amp, 0.0f, 1.0f)), red.opacity(0.0f)});
    glowBg.blend = Blend::plus;
    c.rect({0, 0, f.width, f.height}, glowBg);
    float px = std::min(f.width, f.height) / 400.0f;
    float top = -f.height * 0.02f, bottom = f.height * 1.02f;
    float L = bottom - top;
    // Trastes: barras metálicas cada vez más juntas, como en el mástil.
    if (m.trastes) {
      Path frets;
      for (int k = 1; k <= 14; k++) {
        float y = top + L * (1.0f - std::pow(2.0f, -float(k) / 12.0f)) * 1.9f;
        if (y > bottom) break;
        frets.moveTo(f.width * 0.08f, y).lineTo(f.width * 0.92f, y);
      }
      Paint fp;
      fp.strokeWidth = 2.0f * px;
      fp.color = Color{0.7f, 0.68f, 0.66f, std::clamp(0.16f * amp, 0.0f, 1.0f)};
      c.path(frets, fp);
    }
    int n = std::clamp(m.cuerdas, 2, kMax);
    float t = float(std::fmod(clock, 1000.0));
    for (int i = 0; i < n; i++) {
      float u = n > 1 ? float(i) / float(n - 1) : 0.0f;
      float x0 = f.width * (0.14f + 0.72f * u);
      // Rasgueo: cada cuerda se pulsa un poco después que la anterior.
      int order = strumUp ? n - 1 - i : i;
      float delay = 0.028f * float(order);
      float sa = float(strumAge) - delay;
      float pluck = sa >= 0.0f ? strumPower * std::exp(-sa * 2.4f) : 0.0f;
      float level = std::clamp(0.22f + 1.1f * bands[size_t(i)] * amp + 1.1f * pluck, 0.0f, 1.6f);
      float A = f.width * 0.05f * m.amplitud * level * (1.15f - 0.5f * u);
      float waves = (2.0f + 3.5f * u) * m.ondas;
      float k1 = 6.2831853f * waves / L;
      float w1 = 6.2831853f * (0.5f + 0.35f * float(i));
      float k2 = k1 * 2.3f;
      float w2 = w1 * 1.7f;
      Path s;
      for (int p = 0; p <= kPoints; p++) {
        float y = top + L * float(p) / float(kPoints);
        float env = std::sin(3.14159265f * float(p) / float(kPoints));
        float d = A * env * (0.78f * std::sin(k1 * y - w1 * t + float(i) * 1.7f) + 0.22f * std::sin(k2 * y + w2 * t));
        if (p == 0) s.moveTo(x0 + d, y); else s.lineTo(x0 + d, y);
      }
      bool wound = u < 0.5f;
      const Color& base = wound ? gold : silver;
      float thick = (wound ? 4.2f - 2.6f * u : 2.2f - 1.2f * (u - 0.5f)) * px;
      Paint halo;
      halo.blend = Blend::plus;
      halo.strokeWidth = thick * 5.0f;
      halo.strokeJoin = 1;
      halo.color = (wound ? gold : red).opacity(std::clamp((0.05f + 0.22f * level) * f.glow * amp, 0.0f, 1.0f));
      c.path(s, halo);
      // Sombreado de cilindro con su reflejo.
      Paint core;
      core.strokeWidth = thick;
      core.strokeJoin = 1;
      float lit = (0.75f + 0.45f * level) * amp;
      core.color = Color{std::min(1.0f, base.r * lit), std::min(1.0f, base.g * lit), std::min(1.0f, base.b * lit), 1.0f};
      c.path(s, core);
      Paint shine;
      shine.blend = Blend::plus;
      shine.strokeWidth = std::max(0.8f, thick * 0.3f);
      shine.strokeJoin = 1;
      shine.color = Color{1.0f, 0.95f, 0.9f, std::clamp((0.25f + 0.4f * level) * amp, 0.0f, 1.0f)};
      c.path(s, shine);
    }
    if (flash > 0.01f) {
      Paint fl;
      fl.blend = Blend::plus;
      fl.color = red.opacity(std::clamp(flash * 0.06f * amp, 0.0f, 1.0f));
      c.rect({0, 0, f.width, f.height}, fl);
    }
  }
};
''';
