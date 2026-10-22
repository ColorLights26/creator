// Reactiva Mejorada · Polvo de Lente Revelado — transparencia momentánea. En el golpe grande una luz
// fuera de cuadro barre la lente y revela la suciedad del cristal sólo cerca de
// ella: motas, huellas, un par de pelos y un velo cálido. La suciedad está fija
// (semilla) y lo que se mueve es la luz, como en la postproducción cara.
// Referentes: Optical Flares de Video Copilot (lens dirt) y los tutoriales de
// suciedad procedural que reacciona a la luz.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música; los pulsos son cortos para que se
// vean con el compás. La original («Reactiva · Polvo de Lente Revelado») no se toca.
// Funciona encima de cualquier escena sin conocerla: sólo luz (y sombra
// neutra), sin objetos que se queden. Sin música no dibuja nada. Nunca más de
// tres destellos por segundo.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento enciende la luz.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpes acentuados', 'Bombo', 'Cada dos tiempos']),
  // FORMA: cuánta suciedad tiene la lente.
  CreatorModifier.slider('suciedad', 'Suciedad', min: .3, max: 1, value: .7),
  // MOVIMIENTO: desde dónde barre la luz.
  CreatorModifier.choice('barrido', 'Barrido', options: ['Desde la izquierda', 'Desde la derecha', 'Desde arriba']),
  // ATMÓSFERA: cuánto dura el barrido.
  CreatorModifier.slider('caida', 'Duración', min: .3, max: 1, value: .6),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Lente Vieja', {'suciedad': 1, 'caida': .9}),
  CreatorVariation('Reflejo Rápido', {'suciedad': .45, 'caida': .35, 'barrido': 'Desde arriba'}),
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
  static constexpr int kMotes = 320, kSmudges = 12, kHairs = 3;
  std::array<Vec2, kMotes> mote{};
  std::array<float, kMotes> moteLum{};
  std::array<Vec2, kSmudges> smudge{};
  std::array<float, kSmudges> smudgeR{}, smudgeA{}, smudgeE{};
  std::array<std::array<Vec2, 4>, kHairs> hair{};
  void resetOwn(uint32_t seed) {
    Random rng(seed);
    for (int i = 0; i < kMotes; i++) {
      mote[size_t(i)] = {rng.unit(), rng.unit()};
      moteLum[size_t(i)] = 0.35f + 0.65f * rng.unit();
    }
    for (int i = 0; i < kSmudges; i++) {
      smudge[size_t(i)] = {rng.unit(), rng.unit()};
      smudgeR[size_t(i)] = 0.04f + 0.08f * rng.unit();
      smudgeA[size_t(i)] = rng.unit() * float(pi);
      smudgeE[size_t(i)] = 1.2f + 1.8f * rng.unit();
    }
    for (int i = 0; i < kHairs; i++) {
      const Vec2 b = {rng.unit(), rng.unit()};
      for (int k = 0; k < 4; k++) hair[size_t(i)][size_t(k)] = {b.x + (rng.unit() - 0.5f) * 0.12f, b.y + (rng.unit() - 0.5f) * 0.12f};
    }
  }
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const int d = modifiers(f).disparo;
    fire(d == 0 ? h.big : d == 1 ? h.kick : every(h, 16), d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height, S = std::min(W, H), D = std::sqrt(W * W + H * H);
    const float T = g.caida / pace(f);
    const float wl = g.barrido.weight(0), wr = g.barrido.weight(1), wt = g.barrido.weight(2);
    const Color warm = f.colors[3], amber = f.colors[2];
    for (const Pulse& p : slots) {
      const double age = now - p.start;
      if (age <= 0.0 || age >= double(T)) continue;
      const float q = float(age / double(T));
      const float e = std::pow(std::max(0.0f, std::sin(float(pi) * q)), 0.7f) * amount(p.power) * f.intensity * (p.kind == 1 ? 0.75f : 1.0f);
      const float sweep = easeOut(q), y = H * (0.2f + 0.5f * rnd(p.id * 13u)), x = W * (0.25f + 0.5f * rnd(p.id * 29u));
      const Vec2 L = {wl * W * (-0.15f + 0.5f * sweep) + wr * W * (1.15f - 0.5f * sweep) + wt * x,
                      (wl + wr) * y + wt * H * (-0.15f + 0.5f * sweep)};
      glow(c, L, D * 0.75f, warm, amber, 0.26f * e);
      const float reach = 1.0f / (0.38f * D);
      const int count = std::clamp(int(float(kMotes) * g.suciedad), 0, kMotes);
      clearBins();
      for (int i = 0; i < count; i++) {
        const Vec2 pt = {mote[size_t(i)].x * W, mote[size_t(i)].y * H};
        const float dx = (pt.x - L.x) * reach, dy = (pt.y - L.y) * reach;
        const float v = e * moteLum[size_t(i)] * std::exp(-(dx * dx + dy * dy));
        if (v < 0.03f) continue;
        bins_[size_t(std::min(3, int(v * 4.0f)))].push_back(pt);
      }
      const float lv[4] = {0.18f, 0.34f, 0.55f, 0.8f};
      for (int b = 0; b < 4; b++) drawBin(c, b, std::max(0.8f, S * 0.0017f * (1.0f + 0.3f * float(b))), mixc(white(), warm, 0.3f), lv[b]);
      drawBin(c, 3, std::max(1.5f, S * 0.005f), f.colors[1], 0.08f);  // borde irisado de las motas cercanas
      for (int i = 0; i < kSmudges; i++) {
        const Vec2 pt = {smudge[size_t(i)].x * W, smudge[size_t(i)].y * H};
        const float dx = (pt.x - L.x) * reach, dy = (pt.y - L.y) * reach;
        const float v = e * std::exp(-(dx * dx + dy * dy)) * g.suciedad;
        if (v < 0.02f) continue;
        c.save();
        c.translate(pt.x, pt.y);
        c.rotate(smudgeA[size_t(i)]);
        c.scale(smudgeE[size_t(i)], 1.0f);
        glow(c, {0.0f, 0.0f}, smudgeR[size_t(i)] * S, warm, amber, 0.13f * v);
        c.restore();
      }
      for (int i = 0; i < kHairs; i++) {
        const auto& hh = hair[size_t(i)];
        const float dx = (hh[1].x * W - L.x) * reach, dy = (hh[1].y * H - L.y) * reach;
        const float v = e * std::exp(-(dx * dx + dy * dy)) * g.suciedad;
        if (v < 0.03f) continue;
        Path hp;
        hp.moveTo(hh[0].x * W, hh[0].y * H).cubicTo(hh[1].x * W, hh[1].y * H, hh[2].x * W, hh[2].y * H, hh[3].x * W, hh[3].y * H);
        Paint pp;
        pp.color = tint(warm, 0.45f * v);
        pp.blend = Blend::plus;
        pp.strokeWidth = std::max(1.0f, S * 0.0012f);
        pp.strokeCap = 1;
        c.path(hp, pp);
      }
    }
  }
};
''';
