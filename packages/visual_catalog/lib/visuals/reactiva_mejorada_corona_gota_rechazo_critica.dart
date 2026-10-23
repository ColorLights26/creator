// Reactiva Mejorada · Corona de Gota — transparencia momentánea. Con el golpe cae una gota de luz
// líquida y salpica en corona, como la gota de leche filmada a alta velocidad:
// un anillo que se abre en perspectiva, una pared fina y translúcida de luz que
// sube con el borde ondulado y rematado en puntas afiladas, cada punta suelta
// una gotita que vuela y cae, y en el centro rebota un chorro. La mitad de
// delante brilla más que la de detrás. Luz esmeralda en la pared, blanca en el
// borde y en las gotas. Cada golpe salpica en otro sitio. Sólo suma luz.
// Referente: la corona de una gota de leche a alta velocidad.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo', 'Bombo y caja', 'Cada pulso']),
  // FORMA: tamaño de la corona.
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.4, value: 1),
  // MOVIMIENTO: cuánto dura.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.5, value: .9),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Gran Salpicadura', {'tamano': 1.35, 'caida': 1.3}),
  CreatorVariation('Gotita', {'tamano': .7, 'caida': .55}),
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
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height;
    const float px1 = W / 360.0f;
    const float T = g.caida * 0.45f / pace(f);
    const Color deep = f.colors[1], green = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2654435761u + 11u;
      const float cx = W * (0.3f + 0.4f * rnd(s + 1u)), cy = H * (0.45f + 0.35f * rnd(s + 2u));
      // El anillo ya se abre en el golpe; la pared sube, se rompe en puntas y
      // cae; el chorro central rebota después.
      const float R = (60.0f + 70.0f * easeOut(clamp01(0.25f + a * pace(f) / 0.35f))) * px1 * g.tamano * sz;
      const float wall = std::sin(float(pi) * clamp01(0.12f + q / 0.75f)) * 85.0f * px1 * g.tamano * sz;
      const float fade = 1.0f - easeInOut((q - 0.55f) / 0.45f);
      const int lobes = 12 + int(rnd(s + 4u) * 5.0f);
      const float ph = 6.2832f * rnd(s + 3u);
      const int N = 192;
      // Delante (abajo en pantalla) y detrás, para que la de detrás brille menos.
      Path baseF, baseB, sheetF, sheetB, rimF, rimB;
      std::vector<Vec2> tips;
      Vec2 prevB{}, prevT{};
      for (int i = 0; i <= N; i++) {
        const float th = 6.2832f * float(i % N) / float(N);
        const float ex = std::cos(th) * R, ey = std::sin(th) * R * 0.32f;
        // Pared ondulada con puntas afiladas en cada lóbulo.
        const float lob = 0.5f + 0.5f * std::cos(th * float(lobes) + ph);
        const float hgt = wall * (0.62f + 0.38f * lob * lob * lob * lob);
        const Vec2 b0 = {cx + ex, cy + ey}, t0 = {cx + ex * 1.1f, cy + ey - hgt};
        const bool front = std::sin(th) > 0.0f;
        if (i > 0) {
          (front ? baseF : baseB).moveTo(prevB.x, prevB.y).lineTo(b0.x, b0.y);
          (front ? rimF : rimB).moveTo(prevT.x, prevT.y).lineTo(t0.x, t0.y);
        }
        if (i < N && i % 2 == 0) (front ? sheetF : sheetB).moveTo(b0.x, b0.y).lineTo(t0.x, t0.y);
        prevB = b0;
        prevT = t0;
      }
      // Una punta por lóbulo, en lo alto de cada uno.
      for (int j = 0; j < lobes; j++) {
        const float th = (6.2832f * float(j) - ph) / float(lobes);
        tips.push_back({cx + std::cos(th) * R * 1.1f, cy + std::sin(th) * R * 0.32f * 1.1f - wall});
      }
      Paint pt;
      pt.blend = Blend::plus;
      pt.strokeCap = 1;
      pt.strokeJoin = 1;
      const float lf = lv * fade;
      for (int side = 0; side < 2; side++) {
        const float k = side == 0 ? 1.0f : 0.5f;
        Path& base = side == 0 ? baseF : baseB;
        Path& sheet = side == 0 ? sheetF : sheetB;
        Path& rim = side == 0 ? rimF : rimB;
        // Anillo de la base con su resplandor.
        pt.strokeWidth = 10.0f * px1;
        pt.color = tint(deep, 0.2f * lf * k);
        c.path(base, pt);
        pt.strokeWidth = 2.4f * px1;
        pt.color = tint(green, 0.65f * lf * k);
        c.path(base, pt);
        // Pared translúcida: hilos verticales muy juntos que se ven como lámina.
        pt.strokeWidth = 3.0f * px1;
        pt.color = tint(green, 0.07f * lf * k);
        c.path(sheet, pt);
        // Borde de la corona: blanco con halo verde.
        pt.strokeWidth = 8.0f * px1;
        pt.color = tint(green, 0.22f * lf * k);
        c.path(rim, pt);
        pt.strokeWidth = 1.8f * px1;
        pt.color = tint(white, std::min(1.0f, 0.95f * lv) * fade * k);
        c.path(rim, pt);
      }
      // Las puntas sueltan gotitas que vuelan hacia fuera y caen.
      const float fly = clamp01((q - 0.15f) / 0.85f);
      for (size_t i = 0; i < tips.size(); i++) {
        const float dx = tips[i].x - cx;
        const float vx = dx / std::max(R, 1.0f) * (40.0f + 30.0f * rnd(s + 10u + uint32_t(i))) * px1;
        const float vy = -(70.0f + 40.0f * rnd(s + 30u + uint32_t(i))) * px1;
        const Vec2 d0 = {tips[i].x + vx * fly, tips[i].y + vy * fly + 170.0f * px1 * fly * fly};
        glow(c, d0, 9.0f * px1 * sz, tint(white, 1.0f), green, 0.9f * lf * (q > 0.15f ? 1.0f : 0.0f));
      }
      // Chorro central que rebota.
      const float jet = std::sin(float(pi) * clamp01((q - 0.3f) / 0.6f));
      if (jet > 0.01f) {
        Path col;
        col.moveTo(cx, cy).lineTo(cx, cy - jet * 120.0f * px1 * g.tamano * sz);
        pt.strokeWidth = 10.0f * px1;
        pt.color = tint(deep, 0.25f * lv);
        c.path(col, pt);
        pt.strokeWidth = 3.0f * px1;
        pt.color = tint(green, 0.7f * lv);
        c.path(col, pt);
        glow(c, {cx, cy - jet * 128.0f * px1 * g.tamano * sz}, 12.0f * px1 * sz, tint(white, 1.0f), green, 0.9f * lv * jet);
      }
    }
  }
};
''';

const shaderSources = <String, String>{

};
