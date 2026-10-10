// Árbol Fractal Transparente — un árbol de luz que se ramifica sin fin.
// Versión overlay: mismo movimiento y reacción a la música sin fondo opaco.
// Desde el tronco, cada rama se parte en dos más cortas una y otra vez (hasta
// diez generaciones, mil ramas): el color pasa del dorado del tronco al
// fucsia de las puntas y cada generación tiene su halo. Al empezar el árbol
// crece desde el suelo. El viento lo mece más con los graves, la apertura de
// las ramas respira con la energía, cada golpe sube como un pulso de luz del
// tronco a la copa y en las puntas florecen brotes que se encienden con los
// agudos; alrededor caen pétalos de luz. En Auto la forma cambia entre
// simétrica, natural y en espiral.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('ramas', 'Generaciones', min: 5, max: 10, value: 8),
  CreatorModifier.slider('apertura', 'Apertura', min: .2, max: 1.1, value: .38),
  CreatorModifier.choice('forma', 'Forma', options: ['Auto', 'Simétrico', 'Natural', 'Espiral']),
  CreatorModifier.toggle('hojas', 'Brotes en las puntas', value: true),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kMaxNodes = 1023;
  static constexpr int kPetals = 70;
  float bass = 0, body = 0, spark = 0, energy = 0, slowBass = 0;
  float kick = 0, flash = 0, drive = 0;
  // Relojes en doble precisión: la escena sin música es idéntica a 30 y 60 FPS.
  double clock = 0, wind = 0, sincePulse = 100, sinceForm = 0;
  float pulsePower = 0, asym = 0, curl = 0;
  int beats = 0, autoForm = 0;
  // Variación fija de cada rama, elegida al reiniciar.
  std::array<float, kMaxNodes> jitterA{}, jitterL{};
  // Pétalos que caen flotando: posición, velocidad y vaivén propios.
  std::array<float, kPetals> petalX{}, petalSpeed{}, petalPhase{}, petalSway{};
  // Ramas calculadas en update y dibujadas en render.
  std::array<Vec2, kMaxNodes> start{}, end{};
  std::array<float, kMaxNodes> angle{}, length{};
  std::array<bool, kMaxNodes> alive{};
  int nodes = 0, generations = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }

  static int depthOf(int i) {
    int d = 0;
    for (int n = i + 1; n > 1; n >>= 1) d++;
    return d;
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = body = spark = energy = slowBass = kick = flash = drive = 0;
    clock = 0;
    wind = rng.unit() * 20.0;
    sincePulse = 100;
    sinceForm = 0;
    pulsePower = 0;
    asym = curl = 0;
    beats = 0;
    autoForm = 0;
    for (int i = 0; i < kMaxNodes; i++) {
      jitterA[size_t(i)] = rng.unit() * 2.0f - 1.0f;
      jitterL[size_t(i)] = rng.unit() * 2.0f - 1.0f;
    }
    for (int i = 0; i < kPetals; i++) {
      petalX[size_t(i)] = rng.unit();
      petalSpeed[size_t(i)] = 0.03f + 0.05f * rng.unit();
      petalPhase[size_t(i)] = rng.unit();
      petalSway[size_t(i)] = rng.unit() * 6.2831853f;
    }
    nodes = generations = 0;
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
    sincePulse += f.delta;
    sinceForm += f.delta;
    if (hit > kick + 0.2f) {
      beats++;
      sincePulse = 0;
      pulsePower = hit;
      if (beats % 8 == 0) {
        autoForm = (autoForm + 1) % 3;
        sinceForm = 0;
      }
    }
    if (!mu.active && sinceForm > 11.0) {
      autoForm = (autoForm + 1) % 3;
      sinceForm = 0;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    clock += f.delta;
    wind += f.delta * f.speed * (0.7 + 1.3 * drive);

    // La forma se transforma poco a poco: asimetría y rizo hacia su objetivo.
    int form = m.forma == 0 ? autoForm : m.forma - 1;
    float asymGoal = form == 1 ? 1.0f : (form == 2 ? 0.25f : 0.0f);
    float curlGoal = form == 2 ? 1.0f : 0.0f;
    float k = 1.0f - std::exp(-dt * 1.5f);
    asym += (asymGoal - asym) * k;
    curl += (curlGoal - curl) * k;

    // Ramas: recorrido por niveles; los hijos de i son 2i+1 y 2i+2.
    generations = std::clamp(m.ramas, 5, 10);
    nodes = (1 << generations) - 1;
    float growth = float(std::min(clock / 3.0, 1.0)) * float(generations);
    float spread = m.apertura * (1.0f + 0.18f * energy + 0.12f * kick);
    float trunk = f.height * 0.26f;
    float ratio = 0.76f;
    float shortSide = std::min(f.width, f.height);
    // Con pocas generaciones el árbol es más corto: se agranda para llenar.
    float total = 0;
    for (int d = 0; d < generations; d++) total += std::pow(ratio, float(d));
    trunk = std::min(trunk * 3.6f / total, shortSide * 0.45f);
    for (int i = 0; i < nodes; i++) {
      int d = depthOf(i);
      float g = std::clamp(growth - float(d), 0.0f, 1.0f);
      alive[size_t(i)] = g > 0.0f;
      float sway = (0.05f + 0.1f * bass + 0.04f * drive) *
                   float(std::sin(wind * 0.9 + double(d) * 0.55)) * (0.4f + 0.12f * float(d));
      if (i == 0) {
        start[0] = {f.width * 0.5f, f.height * 0.94f};
        angle[0] = -1.5707963f + sway * 0.4f;
        length[0] = trunk * g;
      } else {
        int parent = (i - 1) / 2;
        float dir = (i == 2 * parent + 1) ? -1.0f : 1.0f;
        // Las ramas altas se abren menos: la copa crece hacia arriba.
        float spreadHere = spread * (1.0f + asym * 0.45f * jitterA[size_t(i)]) * (1.0f - 0.035f * float(d));
        float bend = curl * spread * 0.75f;
        angle[size_t(i)] = angle[size_t(parent)] + dir * spreadHere + bend + sway;
        float full = length[size_t(parent)] > 0 ? 1.0f : 0.0f;
        float base = trunk * std::pow(ratio, float(d)) * (1.0f + asym * 0.22f * jitterL[size_t(i)]);
        length[size_t(i)] = base * g * full;
        start[size_t(i)] = end[size_t(parent)];
      }
      end[size_t(i)] = {start[size_t(i)].x + std::cos(angle[size_t(i)]) * length[size_t(i)],
                        start[size_t(i)].y + std::sin(angle[size_t(i)]) * length[size_t(i)]};
    }
    // Encaje: si la copa se sale (formas abiertas o en espiral), el árbol se
    // reduce desde la raíz y se centra en horizontal.
    float minX = f.width * 0.5f, maxX = f.width * 0.5f, minY = start[0].y;
    for (int i = 0; i < nodes; i++) {
      if (!alive[size_t(i)]) continue;
      minX = std::min(minX, end[size_t(i)].x);
      maxX = std::max(maxX, end[size_t(i)].x);
      minY = std::min(minY, end[size_t(i)].y);
    }
    float rootY = start[0].y;
    float fit = 1.0f;
    if (maxX - minX > f.width * 0.94f) fit = std::min(fit, f.width * 0.94f / (maxX - minX));
    if (rootY - minY > rootY - f.height * 0.04f) fit = std::min(fit, (rootY - f.height * 0.04f) / (rootY - minY));
    float centerX = (minX + maxX) * 0.5f;
    float shift = f.width * 0.5f - centerX;
    if (fit < 1.0f || std::fabs(shift) > 0.5f) {
      for (int i = 0; i < nodes; i++) {
        start[size_t(i)] = {f.width * 0.5f + (start[size_t(i)].x - centerX) * fit, rootY + (start[size_t(i)].y - rootY) * fit};
        end[size_t(i)] = {f.width * 0.5f + (end[size_t(i)].x - centerX) * fit, rootY + (end[size_t(i)].y - rootY) * fit};
      }
    }
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    float amp = f.intensity;
    const Color& bg = f.colors[0];
    const Color& gold = f.colors[1];
    const Color& pink = f.colors[2];
    const Color& bloom = f.colors[3];
    // Sin fondo: sólo un resplandor pequeño en la raíz.
    (void)bg;
    float rootR = f.width * 0.28f;
    Paint ground = Paint::radial({f.width * 0.5f, f.height * 0.95f}, rootR,
                                 {gold.opacity(0.22f + 0.2f * kick * amp), gold.opacity(0.0f)});
    c.circle({f.width * 0.5f, f.height * 0.95f}, rootR, ground);

    float px = std::min(f.width, f.height) / 400.0f;
    // Pétalos que caen desde arriba meciéndose con el viento.
    {
      std::array<std::vector<Vec2>, 2> petals;
      for (auto& g : petals) g.reserve(kPetals / 2 + 1);
      for (int i = 0; i < kPetals; i++) {
        double fall = std::fmod(wind * 0.35 * double(petalSpeed[size_t(i)]) * 10.0 + double(petalPhase[size_t(i)]), 1.0);
        float y = (float(fall) * 1.1f - 0.05f) * f.height;
        float x = petalX[size_t(i)] * f.width + float(std::sin(wind * 0.8 + double(petalSway[size_t(i)]))) * 18.0f * px;
        petals[size_t(i % 2)].push_back({x, y});
      }
      for (int g = 0; g < 2; g++) {
        Paint petal;
        petal.blend = Blend::plus;
        const Color& pc = g == 0 ? pink : gold;
        petal.color = pc.opacity(std::clamp((0.35f + 0.4f * kick + 0.3f * spark) * amp, 0.0f, 1.0f));
        c.points(petals[size_t(g)], (1.6f + 0.8f * float(g) + 1.5f * kick) * px, petal);
      }
    }
    float pulsePos = float(sincePulse) * 9.0f;
    for (int d = 0; d < generations; d++) {
      Path p;
      int first = (1 << d) - 1;
      int last = std::min((1 << (d + 1)) - 1, nodes);
      bool any = false;
      for (int i = first; i < last; i++) {
        if (!alive[size_t(i)] || length[size_t(i)] <= 0.0f) continue;
        p.moveTo(start[size_t(i)].x, start[size_t(i)].y);
        p.lineTo(end[size_t(i)].x, end[size_t(i)].y);
        any = true;
      }
      if (!any) continue;
      float t = float(d) / float(std::max(generations - 1, 1));
      float pulse = sincePulse < 2.0 ? pulsePower * std::exp(-(float(d) - pulsePos) * (float(d) - pulsePos) * 0.5f) : 0.0f;
      float lit = (0.8f + 0.3f * body + 1.1f * pulse) * amp;
      Color base{gold.r + (pink.r - gold.r) * t, gold.g + (pink.g - gold.g) * t, gold.b + (pink.b - gold.b) * t, 1.0f};
      float w = std::max(1.0f * px, side(f) * 0.034f * std::pow(0.7f, float(d)));
      Paint halo;
      halo.blend = Blend::plus;
      halo.strokeWidth = w * 2.6f + 4.0f * px;
      halo.strokeCap = 1;
      halo.color = {base.r, base.g, base.b, std::clamp(0.13f * lit * f.glow, 0.0f, 1.0f)};
      c.path(p, halo);
      Paint core;
      core.strokeWidth = w;
      core.strokeCap = 1;
      core.strokeJoin = 1;
      core.color = {std::min(1.0f, base.r * lit + pulse * 0.4f), std::min(1.0f, base.g * lit + pulse * 0.4f),
                    std::min(1.0f, base.b * lit + pulse * 0.4f), 1.0f};
      c.path(p, core);
    }

    if (m.hojas && generations > 0) {
      // Brotes en las puntas: tres grupos que parpadean desfasados.
      int first = (1 << (generations - 1)) - 1;
      std::array<std::vector<Vec2>, 3> groups;
      for (auto& g : groups) g.reserve(size_t(nodes - first) / 3 + 1);
      for (int i = first; i < nodes; i++) {
        if (!alive[size_t(i)] || length[size_t(i)] <= 0.0f) continue;
        groups[size_t(i % 3)].push_back(end[size_t(i)]);
      }
      float arrive = sincePulse < 2.0 ? pulsePower * std::exp(-std::pow(float(generations) - pulsePos, 2.0f) * 0.3f) : 0.0f;
      for (int g = 0; g < 3; g++) {
        if (groups[size_t(g)].empty()) continue;
        float tw = 0.5f + 0.5f * float(std::sin(clock * 2.3 + double(g) * 2.1));
        float r = (1.6f + 1.4f * tw + 3.0f * arrive + 2.5f * spark) * px;
        Paint halo;
        halo.blend = Blend::plus;
        halo.color = pink.opacity(std::clamp((0.18f + 0.3f * arrive) * f.glow * amp, 0.0f, 1.0f));
        c.points(groups[size_t(g)], r * 3.0f, halo);
        Paint dot;
        dot.blend = Blend::plus;
        dot.color = bloom.opacity(std::clamp((0.55f + 0.35f * tw + 0.5f * arrive) * amp, 0.0f, 1.0f));
        c.points(groups[size_t(g)], r, dot);
      }
    }
  }

 private:
  static float side(const Frame& f) { return std::min(f.width, f.height); }
};
''';
