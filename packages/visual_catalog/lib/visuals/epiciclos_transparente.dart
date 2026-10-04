// Epiciclos Transparente — círculos que giran dentro de círculos y dibujan con luz.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Como en las series de Fourier: una cadena de círculos, cada uno girando a
// una frecuencia entera distinta (1, −1, 2, −2, 3…) sobre el borde del
// anterior. La punta del último lleva un lápiz de luz que traza una figura
// cerrada; la estela va del naranja fuego al lima y lo recién dibujado brilla
// más. Cada círculo crece con su banda del espectro, así la figura se
// deforma con la música, y se repite girada en varias copias como un
// mandala; cada ocho golpes (o cada pocos segundos sin música)
// se pasa con suavidad a otra figura, y cada golpe da un acelerón al giro.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('circulos', 'Círculos', min: 4, max: 16, value: 10),
  CreatorModifier.slider('velocidad', 'Velocidad', min: .3, max: 2.5, value: 1),
  CreatorModifier.slider('estela', 'Largo de la estela', min: .2, max: 1, value: .75),
  CreatorModifier.steps('copias', 'Copias en simetría', min: 1, max: 6, value: 3),
  CreatorModifier.toggle('mostrar', 'Mostrar los círculos', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMax = 16;
  static constexpr int kCurve = 420;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double angle = 0, sinceShape = 0, morph = 1;
  int beats = 0;
  Random rng{1};
  std::array<float, kMax> ampFrom{}, ampTo{}, phase{};
  std::array<float, kMax> bands{};

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  // Frecuencias 1, −1, 2, −2, 3, −3…
  static float freq(int k) { return float(k / 2 + 1) * (k % 2 == 0 ? 1.0f : -1.0f); }

  void newShape() {
    for (int k = 0; k < kMax; k++) {
      ampFrom[size_t(k)] = amplitude(k);
      float falloff = 1.0f / (1.0f + 0.55f * float(k));
      ampTo[size_t(k)] = (0.25f + 0.75f * rng.unit()) * falloff * (rng.unit() < 0.2f ? 0.2f : 1.0f);
    }
    morph = 0;
  }

  float amplitude(int k) const {
    float t = float(std::min(morph, 1.0));
    t = t * t * (3.0f - 2.0f * t);
    return ampFrom[size_t(k)] + (ampTo[size_t(k)] - ampFrom[size_t(k)]) * t;
  }

 public:
  void reset(uint32_t seed) override {
    rng = Random(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    angle = rng.unit() * 6.2831853;
    sinceShape = 0;
    beats = 0;
    bands.fill(0);
    for (int k = 0; k < kMax; k++) {
      phase[size_t(k)] = rng.unit() * 6.2831853f;
      ampFrom[size_t(k)] = 0;
      ampTo[size_t(k)] = 0;
    }
    morph = 1;
    newShape();
    morph = 1;
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
    for (int k = 0; k < kMax; k++) {
      int b0 = k * 31 / kMax, b1 = std::max(b0 + 1, (k + 1) * 31 / kMax);
      float v = 0;
      for (int b = b0; b < b1 && b < 31; b++) v = std::max(v, mu.smoothSpectrum[size_t(b)]);
      bands[size_t(k)] = follow(bands[size_t(k)], v, 18.0f, 4.0f, dt);
    }

    float hit = 0, fl = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    for (const auto& e : mu.events[3]) fl = std::max(fl, e.strength);
    float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    sinceShape += f.delta;
    if (hit > kick + 0.2f) {
      beats++;
      if (beats % 8 == 0) {
        newShape();
        sinceShape = 0;
      }
    }
    if (!mu.active && sinceShape > 9.0) {
      newShape();
      sinceShape -= 9.0;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    morph = std::min(morph + f.delta / 1.6, 1.0);
    angle += f.delta * f.speed * m.velocidad * (0.35 + 0.6 * drive + 1.2 * kick);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& fire = f.colors[1];
    const Color& lime = f.colors[2];
    const Color& white = f.colors[3];
    int n = std::clamp(m.circulos, 4, kMax);
    float side = std::min(f.width, f.height);
    float px = side / 400.0f;
    // Radios: amplitud de la figura más la banda del espectro.
    std::array<float, kMax> base{}, radii{};
    for (int k = 0; k < n; k++) {
      base[size_t(k)] = amplitude(k);
      radii[size_t(k)] = base[size_t(k)] * (1.0f + 1.6f * bands[size_t(k)] * amp);
    }
    Vec2 center{f.width * 0.5f, f.height * 0.5f};
    int copies = std::clamp(m.copias, 1, 6);
    // Encaje: el tamaño sale de la figura real sin música (así la música la
    // agranda) y, con copias girando, de su distancia máxima al centro.
    float maxR = 1e-3f, maxX = 1e-3f, maxY = 1e-3f;
    for (int i = 0; i < 96; i++) {
      double a = 6.283185307179586 * double(i) / 96.0;
      float x = 0, y = 0;
      for (int k = 0; k < n; k++) {
        double th = a * double(freq(k)) + double(phase[size_t(k)]);
        x += base[size_t(k)] * float(std::cos(th));
        y += base[size_t(k)] * float(std::sin(th));
      }
      maxR = std::max(maxR, std::sqrt(x * x + y * y));
      maxX = std::max(maxX, std::fabs(x));
      maxY = std::max(maxY, std::fabs(y));
    }
    float fit = copies > 1 ? std::min(f.width, f.height) * 0.46f / maxR
                           : std::min(f.width * 0.44f / maxX, f.height * 0.36f / maxY);
    float scale = fit * (1.0f + 0.1f * bass * amp);
    auto tip = [&](double a, std::array<Vec2, kMax + 1>* chain) {
      Vec2 p = center;
      if (chain) (*chain)[0] = p;
      for (int k = 0; k < n; k++) {
        double th = a * double(freq(k)) + double(phase[size_t(k)]);
        p.x += radii[size_t(k)] * scale * float(std::cos(th));
        p.y += radii[size_t(k)] * scale * float(std::sin(th));
        if (chain) (*chain)[size_t(k + 1)] = p;
      }
      return p;
    };
    // Copias giradas alrededor del centro.
    auto turn = [&](Vec2 p, int copy) {
      if (copy == 0) return p;
      float a = 6.2831853f * float(copy) / float(copies);
      float cs = std::cos(a), sn = std::sin(a);
      float dx = p.x - center.x, dy = p.y - center.y;
      return Vec2{center.x + dx * cs - dy * sn, center.y + dx * sn + dy * cs};
    };

    // Figura completa tenue y estela reciente brillante, por tramos.
    Path full;
    std::vector<Vec2> curve(kCurve + 1);
    for (int i = 0; i <= kCurve; i++) curve[size_t(i)] = tip(angle + 6.283185307179586 * double(i) / double(kCurve), nullptr);
    for (int cp = 0; cp < copies; cp++) {
      for (int i = 0; i <= kCurve; i++) {
        Vec2 p = turn(curve[size_t(i)], cp);
        if (i == 0) full.moveTo(p.x, p.y); else full.lineTo(p.x, p.y);
      }
    }
    Paint faint;
    faint.strokeWidth = 1.6f * px;
    faint.strokeJoin = 1;
    faint.color = fire.opacity(0.3f);
    c.path(full, faint);

    const int chunks = 8;
    double span = 6.283185307179586 * double(m.estela);
    for (int ch = 0; ch < chunks; ch++) {
      float t = float(ch + 1) / float(chunks);
      Path seg;
      int steps = 40;
      std::array<Vec2, 41> pts{};
      for (int i = 0; i <= steps; i++) {
        double a = angle - span + span * (double(ch) + double(i) / double(steps)) / double(chunks);
        pts[size_t(i)] = tip(a, nullptr);
      }
      for (int cp = 0; cp < copies; cp++) {
        for (int i = 0; i <= steps; i++) {
          Vec2 p = turn(pts[size_t(i)], cp);
          if (i == 0) seg.moveTo(p.x, p.y); else seg.lineTo(p.x, p.y);
        }
      }
      Color col{fire.r + (lime.r - fire.r) * t, fire.g + (lime.g - fire.g) * t, fire.b + (lime.b - fire.b) * t, 1.0f};
      Paint glow;
      glow.blend = Blend::plus;
      glow.strokeWidth = (10.0f + 8.0f * bass) * px;
      glow.strokeCap = 1;
      glow.strokeJoin = 1;
      glow.color = col.opacity(std::clamp(0.18f * t * f.glow * amp, 0.0f, 1.0f));
      c.path(seg, glow);
      Paint line;
      line.blend = Blend::plus;
      line.strokeWidth = (2.0f + 2.6f * t + 1.5f * energy) * px;
      line.strokeCap = 1;
      line.strokeJoin = 1;
      line.color = col.opacity(std::clamp((0.3f + 0.7f * t) * amp, 0.0f, 1.0f));
      c.path(seg, line);
    }

    // Los círculos y sus brazos.
    std::array<Vec2, kMax + 1> chain{};
    Vec2 pen = tip(angle, &chain);
    if (m.mostrar) {
      Path rings, arms;
      for (int k = 0; k < n; k++) {
        rings.circle(chain[size_t(k)], std::max(radii[size_t(k)] * scale, 0.5f));
        arms.moveTo(chain[size_t(k)].x, chain[size_t(k)].y).lineTo(chain[size_t(k + 1)].x, chain[size_t(k + 1)].y);
      }
      Paint ring;
      ring.strokeWidth = 1.0f * px;
      ring.color = white.opacity(std::clamp((0.14f + 0.12f * kick) * amp, 0.0f, 1.0f));
      c.path(rings, ring);
      Paint arm;
      arm.strokeWidth = 1.4f * px;
      arm.strokeCap = 1;
      arm.color = white.opacity(std::clamp(0.45f * amp, 0.0f, 1.0f));
      c.path(arms, arm);
      std::vector<Vec2> joints(chain.begin(), chain.begin() + n);
      Paint dot;
      dot.color = white.opacity(std::clamp(0.6f * amp, 0.0f, 1.0f));
      c.points(joints, 1.8f * px, dot);
    }
    // El lápiz de luz.
    Paint halo = Paint::radial(pen, (14.0f + 10.0f * kick) * px, {lime.opacity(std::clamp(0.7f * f.glow * amp, 0.0f, 1.0f)), lime.opacity(0.0f)});
    halo.blend = Blend::plus;
    c.circle(pen, (14.0f + 10.0f * kick) * px, halo);
    Paint penDot;
    penDot.color = Color{1.0f, 1.0f, 0.95f, 1.0f};
    c.circle(pen, 2.6f * px, penDot);
  }
};
''';
