// Reactiva · Fotograma de Impacto — transparencia momentánea. El «impact frame» del anime
// en el golpe grande: durante dos cuadros la pantalla se hunde en negro hacia
// los bordes y decenas de cuñas blancas apuntan a un foco, dejando libre un
// ojo alrededor; luego las cuñas se vuelven bermellón y se retiran hacia fuera.
// Dura menos de un tercio de segundo. Referentes: ActFX Impact (92 ms),
// SpeedLines FX y los impact frames de One Punch Man.
// Funciona encima de cualquier escena sin conocerla: sólo luz (y sombra
// neutra), sin objetos que se queden. Sin música no dibuja nada. Nunca más de
// tres destellos por segundo.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento lo lanza.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cambio de frase', 'Primer tiempo']),
  // FORMA: cuántas cuñas.
  CreatorModifier.steps('lineas', 'Líneas', min: 40, max: 120, value: 80),
  // ATMÓSFERA: cuánto se oscurece el borde en el impacto.
  CreatorModifier.slider('oscuro', 'Fondo oscuro', min: 0, max: 1, value: .7),
  // MOVIMIENTO: dónde apuntan.
  CreatorModifier.choice('foco', 'Foco', options: ['Al azar', 'Centro']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Shonen', {'lineas': 120, 'oscuro': 1}),
  CreatorVariation('Sólo Luz', {'oscuro': 0, 'lineas': 60, 'foco': 'Centro'}),
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
  void resetOwn(uint32_t) {}
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const int d = modifiers(f).disparo;
    fire(d == 0 ? h.big : d == 1 ? every(h, 16) : every(h, 4), d == 2 ? 1 : 0);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height, S = std::min(W, H), D = std::sqrt(W * W + H * H);
    const int n = std::clamp(int(std::lround(g.lineas)), 40, 120);
    const double life = 0.28 / double(pace(f));
    for (const Pulse& p : slots) {
      const double age = now - p.start;
      if (age < 0.0 || age > life) continue;
      const float wr = g.foco.weight(0);
      const Vec2 o = {W * (0.5f + wr * (rnd(p.id * 11u) - 0.5f) * 0.5f), H * (0.45f + wr * (rnd(p.id * 17u + 5u) - 0.5f) * 0.4f)};
      const float k = amount(p.power) * std::min(f.intensity, 1.5f) * (p.kind == 1 ? 0.6f : 1.0f);
      const float eye = S * 0.17f;
      const bool hold = age < 0.066;  // dos cuadros de impacto
      const float q = hold ? 0.0f : float((age - 0.066) / (life - 0.066));
      // Campo oscuro: sólo en el impacto y se va en 40 ms.
      const float dark = std::min(0.82f * g.oscuro * k, 0.85f) * (hold ? 1.0f : clamp01(1.0f - float((age - 0.066) / 0.04)));
      if (dark > kMin) {
        const Color ink = f.colors[0];
        const float R = D * 0.8f;
        Paint field = Paint::radial(o, R, {tint(ink, 0.0f), tint(ink, 0.0f), tint(ink, dark * 0.55f), tint(ink, dark)}, {0.0f, eye / R, 0.45f, 1.0f});
        c.rect({0.0f, 0.0f, W, H}, field);
      }
      // Cuñas que apuntan al foco y luego se retiran hacia fuera.
      Path wedges;
      for (int i = 0; i < n; i++) {
        const float th = 2.0f * float(pi) * (float(i) + 0.6f * rnd(p.id * 131u + uint32_t(i))) / float(n);
        const float half = (0.004f + 0.011f * rnd(p.id * 71u + uint32_t(i))) * (1.0f - 0.6f * q);
        const float tip = eye * (1.0f + 0.9f * rnd(p.id * 53u + uint32_t(i))) + D * 0.55f * q * q;
        wedges.moveTo(o.x + tip * std::cos(th), o.y + tip * std::sin(th));
        wedges.lineTo(o.x + D * std::cos(th - half), o.y + D * std::sin(th - half));
        wedges.lineTo(o.x + D * std::cos(th + half), o.y + D * std::sin(th + half));
        wedges.close();
      }
      const Color col = mixc(white(), f.colors[1], q);
      const float a = (hold ? 0.9f : 0.75f * std::pow(1.0f - q, 1.5f)) * std::min(k, 1.2f);
      Paint wp = Paint::radial(o, D, {tint(col, 0.0f), tint(col, 0.0f), tint(col, a), tint(col, a * 0.8f)}, {0.0f, eye / D, eye / D + 0.12f, 1.0f});
      wp.blend = hold ? Blend::sourceOver : Blend::plus;
      c.path(wedges, wp);
      // Anillo bermellón y polvo en el borde del ojo.
      Paint rp;
      rp.color = tint(f.colors[1], 0.6f * a);
      rp.blend = Blend::plus;
      rp.strokeWidth = S * 0.004f;
      Path eyeRing;
      eyeRing.circle(o, eye * (1.0f + 0.3f * q));
      c.path(eyeRing, rp);
      clearBins();
      for (int j = 0; j < 48; j++) {
        const float th = 2.0f * float(pi) * rnd(p.id * 19u + uint32_t(j));
        const float rr = eye * (0.95f + 0.25f * rnd(p.id * 23u + uint32_t(j))) * (1.0f + 0.5f * q);
        bins_[0].push_back({o.x + rr * std::cos(th), o.y + rr * std::sin(th)});
      }
      drawBin(c, 0, std::max(0.8f, S * 0.002f), white(), 0.6f * a);
    }
  }
};
''';
