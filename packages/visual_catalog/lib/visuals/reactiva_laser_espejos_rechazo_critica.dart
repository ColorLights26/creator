// Reactiva · Láser de Espejos — transparencia momentánea. Con el golpe entra un rayo láser
// verde y rebota entre espejos invisibles repartidos en un anillo alrededor
// de la escena: en un instante dibuja una estrella de líneas que se cruzan y
// en cada espejo salta un destello. La estrella queda un momento y el rayo se
// recoge desde el principio. Núcleo casi blanco, cuerpo verde láser y un halo
// en el humo. Cada golpe dibuja otra estrella, con otro número de puntas y
// otro giro. Sólo suma luz. Referente: los láseres reflejados en espejos de
// los espectáculos.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: cuántos espejos (puntas de la estrella).
  CreatorModifier.steps('rebotes', 'Espejos', min: 5, max: 12, value: 8),
  // MOVIMIENTO: rapidez del rayo.
  CreatorModifier.slider('rapidez', 'Rapidez', min: .6, max: 1.8, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Telaraña', {'rebotes': 12, 'rapidez': .8}),
  CreatorVariation('Pentagrama', {'rebotes': 5, 'rapidez': 1.6}),
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
    fire(d == 0 ? h.big : d == 1 ? every(h, 16) : h.jump, 0);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    const float px1 = W / 360.0f;
    const Color deep = f.colors[1], green = f.colors[2], white = f.colors[3];
    // Tiempos: dibuja en un instante, se queda y se recoge.
    const float draw = 0.12f * 1.0f / pace(f) / g.rapidez;
    const float hold = 0.3f * 1.0f / pace(f);
    const float rec = 0.22f * 1.0f / pace(f) / g.rapidez;
    const float T = draw + hold + rec;
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2246822519u + 13u;
      // Estrella {n/k} entre espejos repartidos en un anillo.
      const int n = 1.0f < 0.5f ? std::clamp(m.rebotes - 2 + 2 * int(p.id % 2u), 5, 12) : std::clamp(m.rebotes, 5, 12);
      auto gcd = [](int x, int y) {
        while (y != 0) {
          const int t = x % y;
          x = y;
          y = t;
        }
        return x;
      };
      int k = n / 2;
      while (k > 1 && gcd(n, k) != 1) k--;
      const float rx = W * 0.46f * (1.0f < 0.5f ? 0.65f + 0.3f * sz : 1.0f), ry = H * 0.4f * (1.0f < 0.5f ? 0.65f + 0.3f * sz : 1.0f);
      const float cx = W * 0.5f, cy = H * (0.45f + 0.1f * rnd(s + 2u));
      const float r0 = 6.2832f * rnd(s + 1u);
      std::vector<Vec2> pts;
      // El rayo entra desde fuera, por detrás del primer espejo.
      const Vec2 m0 = {cx + std::cos(r0) * rx, cy + std::sin(r0) * ry};
      pts.push_back({m0.x + std::cos(r0) * 400.0f * px1, m0.y + std::sin(r0) * 400.0f * px1});
      for (int i = 0; i <= n; i++) {
        const float th = r0 + 6.2832f * float((i * k) % n) / float(n);
        pts.push_back({cx + std::cos(th) * rx, cy + std::sin(th) * ry});
      }
      float total = 0.0f;
      for (size_t i = 1; i < pts.size(); i++) total += std::hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
      // Ya un tercio dibujado en el golpe; al final la cola recorre el camino.
      const float headD = total * std::min(1.0f, 0.3f + 0.7f * a / draw);
      const float tailD = total * clamp01((a - draw - hold) / rec);
      if (headD - tailD < 1.0f) continue;
      Path beam;
      float dist = 0.0f;
      std::vector<std::pair<Vec2, float>> flares;
      for (size_t i = 1; i < pts.size(); i++) {
        const Vec2 a0 = pts[i - 1], a1 = pts[i];
        const float l = std::hypot(a1.x - a0.x, a1.y - a0.y);
        const float u0 = clamp01((tailD - dist) / std::max(l, 0.001f));
        const float u1 = clamp01((headD - dist) / std::max(l, 0.001f));
        if (u1 > u0) beam.moveTo(a0.x + (a1.x - a0.x) * u0, a0.y + (a1.y - a0.y) * u0).lineTo(a0.x + (a1.x - a0.x) * u1, a0.y + (a1.y - a0.y) * u1);
        // Destello en el espejo cuando el rayo lo alcanza, que baja a un
        // brillo tranquilo mientras el rayo pasa por él.
        if (headD >= dist + l && tailD < dist + l) flares.push_back({a1, 0.35f + 0.65f * std::exp(-(headD - dist - l) / (500.0f * px1))});
        dist += l;
      }
      Paint pt;
      pt.blend = Blend::plus;
      pt.strokeCap = 1;
      pt.strokeJoin = 1;
      pt.strokeWidth = 16.0f * px1;
      pt.color = tint(deep, 0.08f * lv);
      c.path(beam, pt);
      pt.strokeWidth = 5.0f * px1;
      pt.color = tint(green, 0.32f * lv);
      c.path(beam, pt);
      pt.strokeWidth = 1.5f * px1;
      pt.color = tint(white, std::min(1.0f, lv));
      c.path(beam, pt);
      for (const auto& fl : flares) {
        softGlow(c, fl.first, 70.0f * px1 * sz, tint(white, 1.0f), green, 0.4f * fl.second * lv);
        glow(c, fl.first, 44.0f * px1 * sz, tint(white, 1.0f), green, fl.second * lv);
      }
    }
  }
};
''';

const shaderSources = <String, String>{

};
