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
// largos. Grano cambia la textura: de hilos de seda finísimos a un polvo de
// granos gruesos y tenues, como pastel. El Brillo básico da la luz de los
// puntos. Los graves empujan la forma y cada golpe la hace destellar.
// Pulso elige qué más hace la música: en Golpes cada golpe hace saltar la
// nube, la enciende con un resplandor y lanza desde el centro una onda de
// choque que empuja los velos hacia fuera y los ilumina a su paso; en Graves
// la nube respira, crece, sus hilos engordan y su resplandor late con los
// graves; en Agudos los velos tiemblan y se llenan de destellos que
// centellean con los agudos.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.steps('miles', 'Miles de puntos', min: 6, max: 30, value: 18),
  CreatorModifier.slider('cambio', 'Velocidad de cambio', min: .2, max: 2.5, value: 1),
  // ATMÓSFERA: textura de los velos, de seda fina a polvo grueso.
  CreatorModifier.slider('grano', 'Grano', min: 0, max: 1, value: 0),
  CreatorModifier.toggle('giro', 'Giro lento', value: true),
  // MÚSICA: qué parte de la nube reacciona.
  CreatorModifier.choice('pulso', 'Pulso', options: ['Golpes', 'Graves', 'Agudos']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Polvo Estelar', {
    'grano': .8,
    'miles': 26,
    'pulso': 'Agudos',
    'giro': true,
  }),
  CreatorVariation('Seda que Respira', {
    'miles': 12,
    'cambio': .5,
    'pulso': 'Graves',
    'speed': .7,
  }),
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
  // Onda de choque del último golpe y reloj de los destellos de los agudos.
  double ringAge = 100, shimmer = 0;
  float ringPower = 0;
  mutable std::vector<float> raw;
  mutable std::array<std::vector<Vec2>, 3> groups;
  mutable std::vector<Vec2> lit, glints;

  static float follow(float v, float target, float up, float down, float dt) {
    return v + (target - v) * (1.0f - std::exp(-(target > v ? up : down) * dt));
  }
  static float hashU(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return float(x & 0xffffffu) / 16777216.0f;
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
    ringAge = 100;
    ringPower = 0;
    shimmer = 0;
    lit.reserve(30000);
    glints.reserve(30000);
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
    // Cada golpe lanza una onda de choque desde el centro de la nube.
    ringAge += f.delta;
    shimmer += f.delta;
    if (hit > kick + 0.2f) {
      ringAge = 0.0;
      ringPower = hit;
    }
    kick = std::max(kick * std::exp(-dt * 5.0f), hit);
    flash = std::max(flash * std::exp(-dt * 8.0f), std::min(fl, 1.0f));
    morph += f.delta * f.speed * m.cambio * (0.25 + 0.6 * drive);
    if (m.giro) spin += f.delta * f.speed * (0.05 + 0.08 * drive);
  }

  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    auto gl = glide(f);
    float amp = f.intensity;
    // Pulso: cada opción mueve algo distinto; sin música todo vale cero.
    const float kickP = std::min(kick * amp, 1.0f) * gl.pulso.weight(0);
    const float bassP = std::min(bass * amp, 1.0f) * gl.pulso.weight(1);
    const float sparkP = std::min(spark * amp, 1.0f) * gl.pulso.weight(2);
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
    // Golpes: la nube da un salto; Graves: crece despacio con los graves.
    scale *= 1.0f + 0.15f * kickP + 0.14f * bassP;
    float px = std::min(f.width, f.height) / 400.0f;
    // Onda de choque de cada golpe: un anillo que sale del centro, empuja los
    // velos hacia fuera y enciende los puntos por donde pasa.
    const float maxR = std::min(f.width, f.height) * 0.5f;
    const float ringR = float(std::min(ringAge, 10.0)) * 1.7f;
    const float ring = ringAge < 1.6 ? std::min(ringPower * amp, 1.0f) * std::exp(-float(ringAge) * 2.2f) * gl.pulso.weight(0) : 0.0f;
    // Agudos: temblor fino y destellos sueltos que cambian 14 veces por segundo.
    const uint32_t tick = uint32_t(std::fmod(shimmer, 100000.0) * 14.0);
    const bool react = ring > 0.002f || sparkP > 0.002f;
    for (auto& g : groups) g.clear();
    lit.clear();
    glints.clear();
    for (int i = 0; i < n; i++) {
      float x = raw[size_t(i) * 3] - cx, y = raw[size_t(i) * 3 + 1] - cy, jump = raw[size_t(i) * 3 + 2];
      float X = f.width * 0.5f + (x * cr - y * sr) * scale;
      float Y = f.height * 0.5f + (x * sr + y * cr) * scale;
      if (react) {
        if (ring > 0.002f) {
          const float dx = X - f.width * 0.5f, dy = Y - f.height * 0.5f;
          const float r = std::sqrt(dx * dx + dy * dy) + 1e-3f;
          const float d = (r / maxR - ringR) / 0.09f;
          const float band = std::exp(-d * d) * ring;
          X += dx / r * band * 0.12f * maxR;
          Y += dy / r * band * 0.12f * maxR;
          if (band > 0.12f) lit.push_back({X, Y});
        }
        if (sparkP > 0.002f) {
          const uint32_t h = uint32_t(i) * 2654435761u + tick * 40503u;
          X += (hashU(h) - 0.5f) * 3.5f * px * sparkP;
          Y += (hashU(h ^ 0x9e3779b9u) - 0.5f) * 3.5f * px * sparkP;
          if (hashU(h + 7u) < 0.15f * sparkP) glints.push_back({X, Y});
        }
      }
      int g = jump < 1.1f ? 0 : (jump < 2.3f ? 1 : 2);
      groups[size_t(g)].push_back({X, Y});
    }
    float density = std::clamp(18000.0f / float(std::max(n, 1)), 0.5f, 3.0f);
    // Brillo básico (glow 0..2): la luz de cada punto, nunca a cero.
    float light = 0.4f + 0.6f * std::clamp(f.glow, 0.0f, 2.0f);
    // Grano: puntos más gruesos y cada uno más tenue, así la luz total se
    // reparte en un polvo suave en vez de saturar.
    float grain = 1.0f + 2.6f * std::clamp(gl.grano, 0.0f, 1.0f);
    float soften = 1.0f / (grain * std::sqrt(grain));
    float base = 0.11f * light * soften * density * (1.0f + 0.6f * kick + 0.3f * bass) * amp;
    // Golpes destella la nube entera; Graves la aviva y engorda sus hilos;
    // Agudos la hace chispear.
    base *= 1.0f + 1.0f * kickP + 0.8f * bassP + 0.35f * sparkP;
    // Resplandor local de la nube: Golpes lo enciende y Graves lo hace latir.
    const float aura = std::clamp((0.32f * kickP + 0.2f * bassP) * f.glow, 0.0f, 0.6f);
    if (aura > 0.002f) {
      const Vec2 mid{f.width * 0.5f, f.height * 0.5f};
      const float auraR = maxR * (1.05f + 0.1f * kickP);
      Paint ap = Paint::radial(mid, auraR, {f.colors[2].opacity(aura), f.colors[1].opacity(aura * 0.4f), f.colors[1].opacity(0.0f)},
                               {0.0f, 0.55f, 1.0f});
      ap.blend = Blend::plus;
      c.circle(mid, auraR, ap);
    }
    for (int g = 0; g < 3; g++) {
      const Color& col = f.colors[size_t(1 + g)];
      Paint p;
      p.blend = Blend::plus;
      p.color = col.opacity(std::clamp(base * (g == 2 ? 1.3f : 1.0f), 0.0f, 1.0f));
      c.points(groups[size_t(g)], (0.9f + 0.3f * spark) * px * grain * (1.0f + 0.6f * bassP + 0.3f * kickP), p);
    }
    // El frente de la onda de choque, en el tono más claro de la paleta.
    if (!lit.empty()) {
      Paint lp;
      lp.blend = Blend::plus;
      lp.color = f.colors[3].opacity(std::clamp(0.55f * ring * light, 0.0f, 0.8f));
      c.points(lit, 1.5f * px * grain, lp);
    }
    // Destellos de los agudos.
    if (!glints.empty()) {
      Paint gp;
      gp.blend = Blend::plus;
      gp.color = f.colors[3].opacity(std::clamp(0.9f * sparkP, 0.0f, 0.95f));
      c.points(glints, 2.2f * px * std::sqrt(grain), gp);
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
