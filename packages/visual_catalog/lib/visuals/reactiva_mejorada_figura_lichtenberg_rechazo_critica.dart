// Reactiva Mejorada · Figura de Lichtenberg — transparencia momentánea. Con el golpe una descarga
// dibuja desde un punto un árbol fractal de luz que se ramifica como las
// figuras que la electricidad quema en la madera: el tronco y las ramas crecen
// en un instante, blancos en el núcleo con un resplandor lima eléctrico y
// verde, parpadean y se recogen desde las puntas. Cada golpe dibuja un árbol
// distinto. Sólo suma luz. Referente: figuras de Lichtenberg en madera.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo', 'Bombo y caja', 'Cada pulso']),
  // FORMA: cuántas ramas.
  CreatorModifier.slider('ramas', 'Ramas', min: .5, max: 1, value: .8),
  // MOVIMIENTO: cuánto dura la descarga.
  CreatorModifier.slider('caida', 'Duración', min: .4, max: 1.4, value: .8),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Rayo Seco', {'ramas': .55, 'caida': .45}),
  CreatorVariation('Helecho', {'ramas': 1, 'caida': 1.3}),
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
  float eFast = 0.0f, eMid = 0.0f, eSlow = 0.0f, bassSlow = 0.0f, build = 0.0f, impactMean = 0.0f, hatMean = 0.0f, loud = 0.0f, peak = 0.0f;
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
      // Volumen: cuánto suena ahora, mezcla del nivel absoluto y del relativo
      // al pico reciente. En silencio vuelve a cero.
      peak = std::max(peak * 0.9985f, eFast);
      const float loudTarget = std::clamp(0.5f * eFast / std::max(peak, 0.05f) + 1.2f * eFast, 0.0f, 1.3f);
      loud += (loudTarget - loud) * (loudTarget > loud ? 0.35f : 0.06f);
      bassSlow += (mu.bass - bassSlow) * (mu.bass > bassSlow ? 0.15f : 0.047f);
      // Subida: la energía de medio plazo crece por encima de la lenta.
      if (eMid > eSlow * 1.12f + 0.015f) build = std::min(1.0f, build + float(kStep) * 0.7f);
      else build = std::max(0.0f, build - float(kStep) * 0.9f);
    }
    for (const Event& e : mu.events[0]) {  // bombo
      const float s = std::max(e.strength, 0.05f);
      h.kick = std::max(h.kick, s);
      // Golpe grande: el primero tras una pausa o uno claramente más fuerte que los últimos.
      // Golpe acentuado: igual o más fuerte que la media reciente. En un ritmo
      // regular son casi todos; si unos suenan más, sólo esos.
      if (now - lastImpact > 1.5 || s >= impactMean * 0.98f) h.big = std::max(h.big, std::clamp(s / std::max(impactMean, 0.05f) * 0.6f, 0.3f, 1.2f));
      // Vuelta tras una pausa: el primer golpe después de un silencio.
      // Cada golpe, con más fuerza si llega tras un silencio.
      h.back = std::max(h.back, quiet > 1.2 ? std::max(s, 0.8f) : s);
      impactMean = impactMean <= 0.0f ? s : impactMean + (s - impactMean) * 0.25f;
      lastImpact = now;
    }
    for (const Event& e : mu.events[1]) {  // caja o palmada; platillos en la banda alta
      const float s = std::max(e.strength, 0.05f);
      if (e.band == 3) {
        h.hat = std::max(h.hat, s);
        if (s >= hatMean * 0.98f && now - lastHatBig > 0.2) {
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
      if (now - lastBig < 0.3) {
        h.big = 0.0f;
      } else {
        lastBig = now;
        if (build > 0.5f) {  // golpe grande al final de una subida: el drop
          h.drop = true;
          build = 0.0f;
        }
      }
    }
    // Golpes en la subida: cada golpe mientras la energía crece.
    if (h.kick > 0.0f && eFast > eSlow * 1.05f) h.jump = h.kick;
    if (!bassHigh && mu.bass > 0.45f) {
      bassHigh = true;
      h.bassUp = mu.bass;
    } else if (bassHigh && mu.bass < 0.3f) {
      bassHigh = false;
    }
    if (mu.active && (mu.energy > 0.06f || !mu.events[0].empty() || !mu.events[1].empty())) lastSound = now;
    return h;
  }

  // Guarda un momento. Con gated respeta la pausa mínima entre destellos.
  bool fire(float power, int kind = 0, double delay = 0.0, bool gated = true) {
    if (power <= 0.0f) return false;
    power *= 0.3f + 0.9f * loud;  // el volumen decide cuánto se ve
    if (gated) {
      if (now - lastFire < kGap) return false;
      lastFire = now + delay;
    }
    slots[cursor] = Pulse{now + delay, power, kind, fired++};
    cursor = (cursor + 1) % kSlots;
    return true;
  }
  // Con el ritmo: n = 4 (antes cada compás) es cada tiempo y n = 16 (antes
  // cada frase) es cada dos tiempos.
  static float every(const Hits& h, int n) {
    const int m = n >= 16 ? 2 : 1;
    for (int i = 0; i < h.beats; i++)
      if (h.tick[i] % m == 0) return std::max(h.beat, 0.5f);
    return 0.0f;
  }

  static uint32_t mixh(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16;
    return x;
  }
  static float rnd(uint32_t x) { return float(mixh(x) & 0xffffffu) / 16777216.0f; }
  // Cuanto más fuerte suena el golpe, más se nota.
  static float amount(float power) { return std::clamp(0.25f + 0.85f * power, 0.15f, 1.45f); }
  static float pace(const Frame& f) { return 1.6f * std::clamp(f.speed, 0.5f, 2.0f); }
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
    eFast = eMid = eSlow = bassSlow = build = impactMean = hatMean = loud = peak = 0.0f;
    bassHigh = false;
    for (auto& b : bins_) b.reserve(2048);
    resetOwn(seed);
  }
  void resetOwn(uint32_t) {}
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const int d = modifiers(f).disparo;
    fire(d == 0 ? h.kick : d == 1 ? std::max(h.kick, h.snare) : h.beat, 0);
  }
  struct Seg { Vec2 a, b; float t0, t1; int gen; };
  // Árbol fractal determinista para cada golpe: segmentos con el momento en
  // que la descarga llega a cada extremo.
  void grow(std::vector<Seg>& out, Vec2 p, float ang, float len, float t, int gen, uint32_t seed, float bushy) const {
    if (gen > 5 || len < 4.0f || out.size() > 260) return;
    const int steps = 4 + int(rnd(seed * 3u + 1u) * 3.0f);
    for (int i = 0; i < steps; i++) {
      const float jit = (rnd(seed * 7u + uint32_t(i) * 13u + 2u) - 0.5f) * 0.9f;
      const float a = ang + jit;
      const float l = len * (0.7f + 0.6f * rnd(seed * 5u + uint32_t(i) * 11u + 3u));
      const Vec2 q = {p.x + std::cos(a) * l, p.y + std::sin(a) * l};
      out.push_back({p, q, t, t + l, gen});
      if (rnd(seed * 17u + uint32_t(i) * 19u + 4u) < 0.55f * bushy)
        grow(out, q, a + (rnd(seed * 23u + uint32_t(i) * 29u + 5u) < 0.5f ? -1.0f : 1.0f) * (0.5f + 0.5f * rnd(seed * 31u + uint32_t(i))),
             len * 0.72f, t + l, gen + 1, seed * 37u + uint32_t(i) * 41u + 7u, bushy);
      p = q;
      t += l;
    }
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height;
    const float px1 = W / 360.0f;
    const float T = g.caida * 0.45f / pace(f);
    const Color green = f.colors[1], lime = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float k = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      // Nace en un borde (o cerca del centro en la Mejorada) y crece hacia dentro.
      const uint32_t s = p.id * 2654435761u + 17u;
      const int side = int(p.id % 4u);
      Vec2 root = side == 0 ? Vec2{W * (0.2f + 0.6f * rnd(s + 1u)), 0.0f} : side == 1 ? Vec2{W, H * (0.2f + 0.6f * rnd(s + 2u))}
                : side == 2 ? Vec2{W * (0.2f + 0.6f * rnd(s + 3u)), H} : Vec2{0.0f, H * (0.2f + 0.6f * rnd(s + 4u))};
      if (0.45f < 0.5f) root = {W * (0.25f + 0.5f * rnd(s + 5u)), H * (0.25f + 0.5f * rnd(s + 6u))};
      const float toC = std::atan2(0.5f * H - root.y, 0.5f * W - root.x);
      std::vector<Seg> segs;
      segs.reserve(270);
      const float base = (0.45f < 0.5f ? 40.0f : 66.0f) * px1 * sz;
      grow(segs, root, toC, base, 0.0f, 0, s, g.ramas);
      if (0.45f < 0.5f) grow(segs, root, toC + 3.1416f, base, 0.0f, 0, s + 99u, g.ramas);
      // La descarga recorre el árbol en un instante y luego se recoge desde
      // las puntas; parpadea un par de veces.
      float maxT = 1.0f;
      for (const Seg& sg : segs) maxT = std::max(maxT, sg.t1);
      const float front = maxT * (0.4f + 0.6f * easeOut(clamp01(a * pace(f) / 0.12f)));
      const float back = maxT * (1.0f - easeInOut((q - 0.35f) / 0.65f));
      const float lim = std::min(front, back);
      const float flick = q < 0.3f ? 0.8f + 0.2f * std::sin(a * 90.0f) : 1.0f;
      std::array<Path, 6> paths;
      std::array<bool, 6> used{};
      for (const Seg& sg : segs) {
        if (sg.t0 >= lim) continue;
        const float u = std::min(1.0f, (lim - sg.t0) / std::max(sg.t1 - sg.t0, 0.001f));
        const Vec2 e = {sg.a.x + (sg.b.x - sg.a.x) * u, sg.a.y + (sg.b.y - sg.a.y) * u};
        paths[size_t(sg.gen)].moveTo(sg.a.x, sg.a.y).lineTo(e.x, e.y);
        used[size_t(sg.gen)] = true;
      }
      // Tres capas por generación: resplandor ancho verde, halo lima y
      // núcleo blanco; las ramas finas, más tenues.
      for (int gi = 0; gi < 6; gi++) {
        if (!used[size_t(gi)]) continue;
        const float w = std::pow(0.68f, float(gi));
        const float lv = k * flick * (0.55f + 0.45f * w);
        Paint glowP; glowP.blend = Blend::plus; glowP.strokeCap = 1; glowP.strokeJoin = 1;
        glowP.strokeWidth = 11.0f * px1 * w + 2.0f * px1;
        glowP.color = tint(green, 0.16f * lv);
        c.path(paths[size_t(gi)], glowP);
        glowP.strokeWidth = 4.0f * px1 * w + 1.0f * px1;
        glowP.color = tint(lime, 0.5f * lv);
        c.path(paths[size_t(gi)], glowP);
        glowP.strokeWidth = 1.6f * px1 * w + 0.6f * px1;
        glowP.color = tint(white, std::min(1.0f, 1.1f * lv));
        c.path(paths[size_t(gi)], glowP);
      }
    }
  }
};
''';

const shaderSources = <String, String>{

};
