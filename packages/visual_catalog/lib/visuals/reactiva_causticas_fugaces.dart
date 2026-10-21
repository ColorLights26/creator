// Reactiva · Cáusticas Fugaces — transparencia momentánea. Cuando crecen los graves aparece
// sobre la escena, por zonas, la red de luz de una piscina: líneas curvas
// brillantes que se deforman despacio, con halo y borde prismático, y se
// evaporan en cuanto los graves bajan. Reflejos sin objeto, en la línea líquida
// de Cromo Líquido. Referentes: Sapphire Caustics (Boris FX) y «2Tweet Water
// Caustic» de Shadertoy, rehechas con trazos para el móvil.
// Funciona encima de cualquier escena sin conocerla: sólo luz (y sombra
// neutra), sin objetos que se queden. Sin música no dibuja nada. Nunca más de
// tres destellos por segundo.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué la hace aparecer.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Graves que crecen', 'Bombo', 'Cambio de frase']),
  // FORMA: tamaño de las celdas de la red.
  CreatorModifier.slider('escala', 'Tamaño de la red', min: .6, max: 1.6, value: 1),
  // MOVIMIENTO: cuánto se deforma.
  CreatorModifier.slider('ondulacion', 'Ondulación', min: 0, max: 1, value: .6),
  // MODO: borde de color separado.
  CreatorModifier.toggle('prisma', 'Borde prismático', value: true),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Piscina', {'escala': 1.4, 'ondulacion': 1}),
  CreatorVariation('Red Fina', {'escala': .7, 'ondulacion': .3, 'prisma': false}),
];

const nativeSource = r'''
class Visual final : public Scene {
  // Fotosensibilidad: nunca más de 3 destellos por segundo.
  static constexpr double kGap = 0.34;
  static constexpr double kStep = 1.0 / 60.0;
  // Por debajo de esta opacidad no se pinta nada: sin su momento la capa
  // queda vacía y no cuesta nada.
  static constexpr float kMin = 0.004f;
  static constexpr int kSlots = 8;
  struct Pulse { double start = -100.0; float power = 0.0f; int kind = 0; uint32_t id = 0; };
  // Lo que la música trae en este cuadro.
  struct Hits {
    float kick = 0.0f, snare = 0.0f, hat = 0.0f, hatBig = 0.0f, beat = 0.0f, big = 0.0f, jump = 0.0f, back = 0.0f, bassUp = 0.0f;
    bool drop = false;
    int beats = 0;               // pulsos nuevos en este cuadro
    std::array<int, 4> tick{};   // número de cada pulso nuevo desde el inicio
  };
  std::array<Pulse, kSlots> slots{};
  int cursor = 0, beatCount = 0, flip = 0;
  uint32_t fired = 0;
  double now = 0.0, acc = 0.0, lastFire = -100.0, lastImpact = -100.0, lastBig = -100.0, lastJump = -100.0;
  double lastSound = -100.0, lastHatBig = -100.0;
  float eFast = 0.0f, eMid = 0.0f, eSlow = 0.0f, bassSlow = 0.0f, build = 0.0f, impactMean = 0.0f, hatMean = 0.0f;
  bool bassHigh = false;
  // Lotes de puntos reutilizados cada cuadro (reservados en reset).
  mutable std::array<std::vector<Vec2>, 12> bins_;

  Hits listen(const Frame& f) {
    Hits h;
    const Music& mu = f.music;
    const double quiet = now - lastSound;
    now += f.delta;
    acc += f.delta;
    while (acc >= kStep) {
      acc -= kStep;
      eFast += (mu.energy - eFast) * 0.19f;
      eMid += (mu.energy - eMid) * 0.033f;
      eSlow += (mu.energy - eSlow) * 0.0042f;
      bassSlow += (mu.bass - bassSlow) * (mu.bass > bassSlow ? 0.15f : 0.047f);
      // Subida: la energía de medio plazo crece por encima de la lenta.
      if (eMid > eSlow * 1.12f + 0.015f) build = std::min(1.0f, build + float(kStep) * 0.7f);
      else build = std::max(0.0f, build - float(kStep) * 0.9f);
    }
    for (const Event& e : mu.events[0]) {  // bombo
      const float s = std::max(e.strength, 0.05f);
      h.kick = std::max(h.kick, s);
      // Golpe grande: el primero tras una pausa o uno claramente más fuerte que los últimos.
      if (now - lastImpact > 1.5 || s > std::max(0.3f, impactMean * 1.3f)) h.big = std::max(h.big, std::max(s, 0.5f));
      // Vuelta tras una pausa: el primer golpe después de un silencio.
      if (quiet > 1.2) h.back = std::max(h.back, std::max(s, 0.5f));
      impactMean = impactMean <= 0.0f ? s : impactMean + (s - impactMean) * 0.25f;
      lastImpact = now;
    }
    for (const Event& e : mu.events[1]) {  // caja o palmada; platillos en la banda alta
      const float s = std::max(e.strength, 0.05f);
      if (e.band == 3) {
        h.hat = std::max(h.hat, s);
        if (s > std::max(0.12f, hatMean * 1.35f) && now - lastHatBig > 1.0) {
          h.hatBig = std::max(h.hatBig, s);
          lastHatBig = now;
        }
        hatMean = hatMean <= 0.0f ? s : hatMean + (s - hatMean) * 0.2f;
      } else {
        h.snare = std::max(h.snare, s);
      }
    }
    for (const Event& e : mu.events[2]) {  // pulso
      h.beat = std::max(h.beat, std::max(e.strength, 0.05f));
      if (h.beats < 4) h.tick[h.beats++] = beatCount;
      beatCount++;
    }
    for (const Event& e : mu.events[3]) h.big = std::max(h.big, std::max(e.strength, 0.6f));  // gran momento
    if (h.big > 0.0f) {
      if (now - lastBig < 2.5) {
        h.big = 0.0f;
      } else {
        lastBig = now;
        if (build > 0.5f) {  // golpe grande al final de una subida: el drop
          h.drop = true;
          build = 0.0f;
        }
      }
    }
    if (eFast > 0.12f && eFast > eSlow * 1.6f + 0.05f && now - lastJump > 6.0) {
      h.jump = std::clamp(eFast * 2.0f, 0.5f, 1.0f);
      lastJump = now;
    }
    if (!bassHigh && mu.bass > 0.72f) {
      bassHigh = true;
      h.bassUp = mu.bass;
    } else if (bassHigh && mu.bass < 0.5f) {
      bassHigh = false;
    }
    if (mu.active && (mu.energy > 0.06f || !mu.events[0].empty() || !mu.events[1].empty())) lastSound = now;
    return h;
  }

  // Guarda un momento. Con gated respeta la pausa mínima entre destellos.
  bool fire(float power, int kind = 0, double delay = 0.0, bool gated = true) {
    if (power <= 0.0f) return false;
    if (gated) {
      if (now - lastFire < kGap) return false;
      lastFire = now + delay;
    }
    slots[cursor] = Pulse{now + delay, power, kind, fired++};
    cursor = (cursor + 1) % kSlots;
    return true;
  }
  // Primer pulso de cada grupo de n (n = 4: compás; n = 16: frase).
  static float every(const Hits& h, int n) {
    for (int i = 0; i < h.beats; i++)
      if (h.tick[i] % n == 0) return std::max(h.beat, 0.5f);
    return 0.0f;
  }

  static uint32_t mixh(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16;
    return x;
  }
  static float rnd(uint32_t x) { return float(mixh(x) & 0xffffffu) / 16777216.0f; }
  // Un golpe más fuerte se nota un poco más, nunca el doble.
  static float amount(float power) { return std::clamp(0.65f + 0.7f * power, 0.65f, 1.25f); }
  static float pace(const Frame& f) { return std::clamp(f.speed, 0.5f, 2.0f); }
  static float clamp01(float x) { return std::clamp(x, 0.0f, 1.0f); }
  static float easeOut(float t) {
    t = clamp01(t);
    const float k = 1.0f - t;
    return 1.0f - k * k * k;
  }
  static float easeInOut(float t) {
    t = clamp01(t);
    return t * t * (3.0f - 2.0f * t);
  }
  // Entra en attack segundos y se apaga en dur (caída cuadrática).
  static float env(double age, float attack, float dur) {
    if (age < 0.0) return 0.0f;
    if (age < double(attack)) return float(age / double(attack));
    const float x = float((age - double(attack)) / double(std::max(dur, 0.02f)));
    if (x >= 1.0f) return 0.0f;
    const float k = 1.0f - x;
    return k * k;
  }
  // Sube y baja suave en dur segundos.
  static float arc(double age, float dur) {
    if (age <= 0.0 || age >= double(dur)) return 0.0f;
    return std::sin(float(pi) * float(age / double(dur)));
  }
  static Color mixc(Color a, Color b, float t) {
    return {a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t};
  }
  static Color tint(Color c, float a) { return c.opacity(std::clamp(a, 0.0f, 1.0f)); }
  static Color white() { return Color{1.0f, 1.0f, 1.0f, 1.0f}; }
  static Color spectral(float t) {
    const float k = 2.0f * float(pi);
    return {0.5f + 0.5f * std::cos(k * t), 0.5f + 0.5f * std::cos(k * (t - 0.333f)), 0.5f + 0.5f * std::cos(k * (t - 0.667f)), 1.0f};
  }
  // Luz con caída real: núcleo, halo y velo muy tenue.
  static void glow(Canvas& c, Vec2 p, float r, Color core, Color halo, float a) {
    if (a < kMin || r < 0.5f) return;
    Paint q = Paint::radial(p, r, {tint(core, a), tint(halo, a * 0.55f), tint(halo, a * 0.22f), tint(halo, a * 0.06f), tint(halo, 0.0f)},
                            {0.0f, 0.08f, 0.2f, 0.45f, 1.0f});
    q.blend = Blend::plus;
    c.circle(p, r, q);
  }
  // Luz ancha y suave (fugas, quemaduras, humo): cae más despacio que glow.
  static void softGlow(Canvas& c, Vec2 p, float r, Color core, Color halo, float a) {
    if (a < kMin || r < 0.5f) return;
    Paint q = Paint::radial(p, r, {tint(core, a), tint(halo, a * 0.75f), tint(halo, a * 0.32f), tint(halo, 0.0f)}, {0.0f, 0.25f, 0.6f, 1.0f});
    q.blend = Blend::plus;
    c.circle(p, r, q);
  }
  // Anillo de luz fino de radio r y ancho w.
  static void ring(Canvas& c, const Frame& f, Vec2 o, float r, float w, Color col, float a) {
    if (a < kMin || r <= w * 1.05f) return;
    const float R = r + 2.0f * w;
    Paint q = Paint::radial(o, R, {tint(col, 0.0f), tint(col, 0.0f), tint(col, a), tint(col, 0.0f), tint(col, 0.0f)},
                            {0.0f, (r - w) / R, r / R, (r + w) / R, 1.0f});
    q.blend = Blend::plus;
    const float x0 = std::max(0.0f, o.x - R), y0 = std::max(0.0f, o.y - R);
    const float x1 = std::min(f.width, o.x + R), y1 = std::min(f.height, o.y + R);
    if (x1 > x0 && y1 > y0) c.rect({x0, y0, x1 - x0, y1 - y0}, q);
  }
  void clearBins() const {
    for (auto& b : bins_) b.clear();
  }
  void drawBin(Canvas& c, int i, float radius, Color col, float a) const {
    if (bins_[size_t(i)].empty() || a < kMin) return;
    Paint p;
    p.color = tint(col, a);
    p.blend = Blend::plus;
    c.points(bins_[size_t(i)], radius, p);
  }

 public:
  void reset(uint32_t seed) override {
    slots = {};
    cursor = beatCount = flip = 0;
    fired = 0;
    now = acc = 0.0;
    lastFire = lastImpact = lastBig = lastJump = lastSound = lastHatBig = -100.0;
    eFast = eMid = eSlow = bassSlow = build = impactMean = hatMean = 0.0f;
    bassHigh = false;
    for (auto& b : bins_) b.reserve(2048);
    resetOwn(seed);
  }
  float glowLevel = 0.0f;
  void resetOwn(uint32_t) { glowLevel = 0.0f; }
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const int d = modifiers(f).disparo;
    const float x = d == 0 ? clamp01((bassSlow - 0.12f) / 0.33f) : 0.0f;
    glowLevel = x * x * (3.0f - 2.0f * x);
    if (d == 1) fire(h.kick, 1);
    if (d == 2) fire(every(h, 16), 2);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height, S = std::min(W, H);
    float V = glowLevel;
    for (const Pulse& p : slots) V = std::max(V, arc(now - p.start, (p.kind == 1 ? 0.6f : 1.2f) / pace(f)) * amount(p.power));
    V *= f.intensity;
    if (V < kMin) return;
    const float cell = S * 0.17f * g.escala;
    const int nx = std::min(14, int(W / cell) + 3), ny = std::min(24, int(H / cell) + 3);
    const float t = float(now), wob = 0.42f * g.ondulacion;
    auto vertex = [&](int i, int j) -> Vec2 {
      const float fi = float(i), fj = float(j);
      return {(fi - 1.0f) * cell + cell * (wob * std::sin(t * 0.9f + fi * 1.3f + fj * 0.7f) + 0.7f * (rnd(uint32_t(i * 31 + j * 17)) - 0.5f)),
              (fj - 1.0f) * cell + cell * (wob * std::cos(t * 0.8f + fi * 0.6f - fj * 1.1f) + 0.7f * (rnd(uint32_t(i * 53 + j * 29 + 7)) - 0.5f))};
    };
    std::array<Path, 3> nets;
    clearBins();
    for (int j = 0; j < ny; j++)
      for (int i = 0; i < nx; i++) {
        const Vec2 a0 = vertex(i, j);
        // Destello donde se cruzan las líneas en las zonas más brillantes.
        const float va = 0.5f + 0.5f * std::sin(a0.x / W * 3.1f + t * 0.4f) * std::sin(a0.y / H * 2.3f - t * 0.3f + 1.0f);
        if (va > 0.72f) bins_[0].push_back(a0);
        for (int dir = 0; dir < 3; dir++) {
          if ((dir == 0 && i + 1 >= nx) || (dir == 1 && j + 1 >= ny)) continue;
          // Algunas diagonales: celdas irregulares, mezcla de cuadros y triángulos.
          if (dir == 2 && (i + 1 >= nx || j + 1 >= ny || rnd(uint32_t(i * 71 + j * 13 + 5)) < 0.5f)) continue;
          const Vec2 b0 = dir == 0 ? vertex(i + 1, j) : dir == 1 ? vertex(i, j + 1) : vertex(i + 1, j + 1);
          const Vec2 mid = {0.5f * (a0.x + b0.x), 0.5f * (a0.y + b0.y)};
          // Manchas grandes: la red sólo aparece por zonas.
          const float mask = 0.5f + 0.5f * std::sin(mid.x / W * 3.1f + t * 0.4f) * std::sin(mid.y / H * 2.3f - t * 0.3f + 1.0f);
          if (mask < 0.3f) continue;
          const int bin = mask < 0.55f ? 0 : mask < 0.8f ? 1 : 2;
          const float bend = cell * 0.25f * std::sin(t * 1.3f + float(i) + float(j) * 1.7f + float(dir));
          const float dx = b0.x - a0.x, dy = b0.y - a0.y, l = std::sqrt(dx * dx + dy * dy) + 1e-3f;
          nets[size_t(bin)].moveTo(a0.x, a0.y).quadraticTo(mid.x - dy / l * bend, mid.y + dx / l * bend, b0.x, b0.y);
        }
      }
    drawBin(c, 0, std::max(2.0f, S * 0.008f), f.colors[2], 0.2f * V);
    drawBin(c, 0, std::max(1.0f, S * 0.0028f), f.colors[3], std::min(0.7f * V, 0.9f));
    const float lv[3] = {0.35f, 0.65f, 1.0f};
    for (int b = 0; b < 3; b++) {
      Paint halo;
      halo.color = tint(f.colors[2], 0.07f * V * lv[b]);
      halo.blend = Blend::plus;
      halo.strokeWidth = S * 0.012f;
      halo.strokeCap = 1;
      halo.strokeJoin = 1;
      c.path(nets[size_t(b)], halo);
      Paint line = halo;
      line.color = tint(f.colors[3], std::min(0.55f * V * lv[b], 0.8f));
      line.strokeWidth = std::max(1.0f, S * 0.0022f);
      c.path(nets[size_t(b)], line);
      if (g.prisma > 0.01f) {
        Paint pr = line;
        pr.color = tint(f.colors[1], 0.2f * V * lv[b] * g.prisma);
        c.save();
        c.translate(std::max(1.0f, S * 0.002f), 0.0f);
        c.path(nets[size_t(b)], pr);
        c.restore();
      }
    }
  }
};
''';
