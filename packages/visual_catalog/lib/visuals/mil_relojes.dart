// Mil Relojes — una pared de relojes que bailan juntos.
// Inspirado en «A Million Times» de Humans since 1982: una rejilla de relojes
// analógicos cuyas dos agujas se mueven a la vez y, entre todas, dibujan
// figuras gigantes: olas, espirales, remolinos, rombos o rayos. Cada pocos
// segundos la figura cambia y cada aguja da una vuelta completa para llegar
// a la nueva, en un barrido que recorre la pared. Las agujas son de luz. Con
// música, cada golpe manda una onda que sacude las agujas a su paso, los
// graves abren las agujas como tijeras y los brillos encienden sus puntas.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // FORMA: la figura que dibujan todas las agujas.
  CreatorModifier.choice(
    'figura',
    'Figura',
    options: ['Todas', 'Olas', 'Espiral', 'Remolino', 'Rombos', 'Abanico'],
  ),
  // MOVIMIENTO: cómo recorre la pared el cambio de figura.
  CreatorModifier.choice(
    'barrido',
    'Barrido',
    options: ['Diagonal', 'Desde el centro', 'A la vez'],
  ),
  // MÚSICA
  CreatorModifier.choice(
    'pulso',
    'Pulso',
    options: ['Golpes', 'Graves', 'Brillos'],
  ),
  // ATMÓSFERA: las agujas dejan un rastro de luz.
  CreatorModifier.slider('estela', 'Estela de luz', min: 0, max: 1, value: .3),
  // MODO: relojes con esfera o sólo agujas flotando.
  CreatorModifier.toggle('esferas', 'Esferas', value: true),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Galería', {
    'figura': 'Rombos',
    'barrido': 'A la vez',
    'esferas': true,
    'estela': 0,
  }),
  CreatorVariation('Luz Pintada', {
    'figura': 'Espiral',
    'estela': 1,
    'esferas': false,
    'pulso': 'Graves',
  }),
];

const nativeSource = r'''
class Visual final : public Scene {
  static constexpr int kRipples = 4;
  static constexpr double kPeriod = 7.0;  // segundos que dura cada figura
  static constexpr float kTurn = 1.8f;    // lo que tarda cada reloj en cambiar
  static constexpr float kTau = 6.2831853f;
  float bass = 0, spark = 0, slowBass = 0, kick = 0;
  // Reloj en doble precisión: la pared sin música es idéntica a 30 y 60 FPS.
  double clock = 0;
  std::array<double, kRipples> rippleAge{};
  std::array<float, kRipples> ripplePower{};
  int nextRipple = 0;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float wrapPi(float a) {
    a = std::fmod(a + 3.14159265f, kTau);
    if (a < 0) a += kTau;
    return a - 3.14159265f;
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
  }
  static int cycleFigure(int64_t n) {
    static const int order[5] = {0, 2, 4, 1, 3};
    return order[int(((n % 5) + 5) % 5)];
  }
  // Las dos agujas de un reloj en (u, v) para una figura y un instante.
  static void figureAngles(int k, float u, float v, int parity, float t, float& a1, float& a2) {
    const float r = std::sqrt(u * u + v * v);
    switch (k) {
      case 0: {  // Olas: líneas que ondulan por la pared.
        float d = 0.9f * std::sin(u * 2.4f - t * 0.9f) + 0.5f * std::sin(v * 1.6f + t * 0.6f);
        a1 = d; a2 = d + 3.14159265f; break;
      }
      case 1: {  // Espiral que gira despacio.
        float d = std::atan2(v, u) + 1.5707963f + 1.4f * r - t * 0.5f;
        a1 = d; a2 = d + 3.14159265f; break;
      }
      case 2: {  // Remolino: esquinas que giran alrededor del centro.
        float d = std::atan2(v, u) + t * 0.7f;
        a1 = d; a2 = d + 1.5707963f; break;
      }
      case 3: {  // Rombos: diagonales alternas que forman una red.
        float d = parity == 0 ? 0.7853982f : 2.3561945f;
        float s = 0.35f * std::sin(t * 0.8f + (u + v) * 1.5f);
        a1 = d + s; a2 = d + 3.14159265f - s; break;
      }
      default: {  // Abanico: rayos que salen del centro.
        float d = std::atan2(v, u) + 0.4f * std::sin(t * 0.6f);
        a1 = d; a2 = d + 3.14159265f + 0.5f * std::sin(t * 0.9f + r * 2.0f); break;
      }
    }
  }
  // Agujas para una opción de Figura: la figura anterior gira hasta la nueva
  // con una vuelta completa, empezando cuando le llega el barrido.
  static void handsFor(int option, float u, float v, int parity, float delay, double time, float& a1, float& a2) {
    const int64_t n = int64_t(std::floor(time / kPeriod));
    const float local = float(time - double(n) * kPeriod);
    const float t = float(time);
    const int kNew = option == 0 ? cycleFigure(n) : option - 1;
    const int kOld = option == 0 ? cycleFigure(n - 1) : option - 1;
    // Con una figura fija, cada periodo la gira un cuarto de vuelta.
    const float rotNew = option == 0 ? 0.0f : float(((n % 2) + 2) % 2) * 1.5707963f;
    const float rotOld = option == 0 ? 0.0f : float((((n - 1) % 2) + 2) % 2) * 1.5707963f;
    float o1, o2, n1, n2;
    figureAngles(kOld, u, v, parity, t, o1, o2);
    figureAngles(kNew, u, v, parity, t, n1, n2);
    o1 += rotOld; o2 += rotOld; n1 += rotNew; n2 += rotNew;
    const float k = std::clamp((local - delay) / kTurn, 0.0f, 1.0f);
    const float e = k * k * (3.0f - 2.0f * k);
    const float spin = (((n % 2) + 2) % 2) == 0 ? 1.0f : -1.0f;
    a1 = o1 + e * (wrapPi(n1 - o1) + kTau * spin);
    a2 = o2 + e * (wrapPi(n2 - o2) - kTau * spin);
  }

 public:
  void reset(uint32_t seed) override {
    Random rng(seed);
    bass = spark = slowBass = kick = 0;
    clock = double(rng.unit()) * kPeriod * 5.0;
    rippleAge.fill(100.0);
    ripplePower.fill(0.0f);
    nextRipple = 0;
  }

  void update(const Frame& f) override {
    const float dt = float(f.delta);
    const Music& mu = f.music;
    bass = follow(bass, mu.bass, 22.0f, 4.5f, dt);
    spark = follow(spark, mu.spark, 30.0f, 7.0f, dt);
    float hit = 0;
    for (const auto& e : mu.events[0]) hit = std::max(hit, e.strength);
    for (const auto& e : mu.events[2]) hit = std::max(hit, e.strength * 0.85f);
    const float onset = std::clamp((mu.bass - slowBass - 0.15f) * 2.5f, 0.0f, 1.0f);
    slowBass = follow(slowBass, mu.bass, 3.0f, 3.0f, dt);
    hit = std::min(std::max(hit, onset), 1.0f);
    for (auto& age : rippleAge) age += f.delta;
    if (hit > kick + 0.2f) {
      rippleAge[size_t(nextRipple)] = 0.0;
      ripplePower[size_t(nextRipple)] = hit;
      nextRipple = (nextRipple + 1) % kRipples;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    clock += f.delta * f.speed;
  }

  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto& pal = f.colors;
    const float amp = f.intensity;
    const float W = f.width, H = f.height;
    const float side = std::min(W, H);
    const Color& bg = pal[0];
    c.rect({0, 0, W, H}, Paint::radial({W * 0.5f, H * 0.45f}, std::max(W, H) * 0.8f,
                                       {Color{std::min(1.0f, bg.r + 0.05f), std::min(1.0f, bg.g + 0.03f), std::min(1.0f, bg.b + 0.02f), 1.0f},
                                        Color{bg.r, bg.g, bg.b, 1.0f}}));
    // Detalle: cuántos relojes caben a lo ancho.
    const int cols = std::clamp(int(std::lround(4.5f + 2.6f * f.detail)), 5, 10);
    const float cell = W / float(cols);
    const int rows = int(std::ceil(H / cell)) + 1;
    const float y0 = (H - float(rows) * cell) * 0.5f;
    const float R = cell * 0.46f;
    const float maxDist = std::sqrt(W * W + H * H) / side;
    const float wGolpes = g.pulso.weight(0), wGraves = g.pulso.weight(1), wBrillos = g.pulso.weight(2);
    const float open = std::min(bass * amp, 1.2f) * 0.6f * wGraves;
    // Agujas casi hasta el borde: entre relojes vecinos se ven líneas seguidas.
    const float lenK = 0.97f * (1.0f + 0.08f * std::min(bass * amp, 1.0f) * wGraves);
    const float wDiag = g.barrido.weight(0), wCenter = g.barrido.weight(1);
    const int from = g.figura.from, to = g.figura.to;
    const float tf = std::clamp(g.figura.t, 0.0f, 1.0f);
    const float ef = tf * tf * (3.0f - 2.0f * tf);
    const float trail = std::clamp(g.estela, 0.0f, 1.0f);
    const float faces = std::clamp(g.esferas, 0.0f, 1.0f);
    const int sparkleSlot = int(std::floor(clock * 10.0));

    Path hands, facePath;
    std::array<Path, 3> trails;
    std::vector<Vec2> hubs, tips;
    hubs.reserve(size_t(rows * cols));
    tips.reserve(size_t(rows * cols) * 2);
    auto angles = [&](float u, float v, int parity, float delay, double time, float& a1, float& a2) {
      handsFor(from, u, v, parity, delay, time, a1, a2);
      if (from != to && ef < 1.0f) {
        float b1, b2;
        handsFor(to, u, v, parity, delay, time, b1, b2);
        a1 += ef * wrapPi(b1 - a1);
        a2 += ef * wrapPi(b2 - a2);
      }
    };
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        const float cx = (float(col) + 0.5f) * cell;
        const float cy = y0 + (float(row) + 0.5f) * cell;
        const float u = (cx - W * 0.5f) / (side * 0.5f);
        const float v = (cy - H * 0.5f) / (side * 0.5f);
        const float dist = std::sqrt(u * u + v * v);
        const float diag = std::clamp((cx / W + cy / H) * 0.5f, 0.0f, 1.0f);
        const float delay = 1.6f * (wDiag * diag + wCenter * std::min(dist / maxDist * 2.0f, 1.0f));
        const int parity = (row + col) % 2;
        float a1, a2;
        angles(u, v, parity, delay, clock, a1, a2);
        // Golpes: una onda que sale del centro y sacude las agujas a su paso.
        float rip = 0;
        for (int i = 0; i < kRipples; i++) {
          const float age = float(rippleAge[size_t(i)]);
          if (age > 4.0f) continue;
          const float front = (dist - age * 1.9f) / 0.25f;
          rip += ripplePower[size_t(i)] * std::exp(-age * 1.4f) * std::exp(-front * front);
        }
        rip *= 1.4f * wGolpes * amp;
        a1 += rip + open;
        a2 += rip - open;
        const float L = R * lenK;
        const Vec2 t1{cx + L * std::cos(a1), cy + L * std::sin(a1)};
        const Vec2 t2{cx + L * std::cos(a2), cy + L * std::sin(a2)};
        hands.moveTo(cx, cy).lineTo(t1.x, t1.y);
        hands.moveTo(cx, cy).lineTo(t2.x, t2.y);
        if (faces > 0.01f) facePath.circle({cx, cy}, R);
        hubs.push_back({cx, cy});
        // Brillos: las puntas de algunas agujas se encienden con los agudos.
        if (wBrillos > 0.01f) {
          const uint32_t key = uint32_t(row * 131 + col * 7919) ^ uint32_t(sparkleSlot * 104729);
          if (hashU(key) < spark * amp * wBrillos * 0.7f) {
            tips.push_back(t1);
            tips.push_back(t2);
          }
        }
        // Estela: las agujas de hace un instante, cada vez más tenues.
        if (trail > 0.01f) {
          for (int k = 0; k < 3; k++) {
            float b1, b2;
            angles(u, v, parity, delay, clock - 0.06 * double(k + 1), b1, b2);
            trails[size_t(k)].moveTo(cx, cy).lineTo(cx + L * std::cos(b1), cy + L * std::sin(b1));
            trails[size_t(k)].moveTo(cx, cy).lineTo(cx + L * std::cos(b2), cy + L * std::sin(b2));
          }
        }
      }
    }
    if (faces > 0.01f) {
      Paint face;
      face.color = pal[1].opacity(std::clamp(0.08f * faces, 0.0f, 1.0f));
      c.path(facePath, face);
      Paint rim;
      rim.strokeWidth = std::max(1.0f, R * 0.04f);
      rim.color = pal[1].opacity(std::clamp(0.55f * faces, 0.0f, 1.0f));
      c.path(facePath, rim);
    }
    if (trail > 0.01f) {
      const float fade[3] = {0.4f, 0.24f, 0.12f};
      for (int k = 0; k < 3; k++) {
        Paint tp;
        tp.blend = Blend::plus;
        tp.strokeWidth = R * 0.1f;
        tp.strokeCap = 1;
        tp.color = pal[2].opacity(std::clamp(fade[k] * trail, 0.0f, 1.0f));
        c.path(trails[size_t(k)], tp);
      }
    }
    Paint halo;
    halo.blend = Blend::plus;
    halo.strokeWidth = R * 0.42f;
    halo.strokeCap = 1;
    halo.color = pal[2].opacity(std::clamp((0.26f + 0.14f * kick * amp * wGolpes) * f.glow, 0.0f, 1.0f));
    c.path(hands, halo);
    Paint core;
    core.strokeWidth = R * 0.13f;
    core.strokeCap = 1;
    core.color = pal[3];
    c.path(hands, core);
    Paint hub;
    hub.color = pal[3];
    c.points(hubs, R * 0.08f, hub);
    if (!tips.empty()) {
      Paint tp;
      tp.blend = Blend::plus;
      tp.color = pal[3].opacity(0.9f);
      c.points(tips, R * 0.14f, tp);
    }
  }
};
''';
