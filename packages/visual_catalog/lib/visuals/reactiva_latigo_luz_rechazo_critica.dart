// Reactiva · Látigo de Luz — transparencia momentánea. Con el golpe un látigo de luz entra
// desde un borde y restalla: el mango barre un arco dejando una estela de luz
// en abanico, un bucle rueda por el látigo hacia la punta, cada vez más rápido
// y más cerrado, y al llegar la punta rompe la barrera del sonido con un
// chasquido de luz, una estrella de rayos, un anillo de choque y chispas.
// Después el látigo se apaga desde el mango hacia la punta. Rojo intenso con
// el cuerpo naranja y un filo amarillo blanco; cada golpe restalla desde otro
// sitio y con otra curva. Sólo suma luz. Referente: el chasquido de un látigo
// a cámara superlenta.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: largo del látigo.
  CreatorModifier.slider('largo', 'Largo', min: .6, max: 1.2, value: 1),
  // MOVIMIENTO: cuánto dura.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.5, value: .9),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Látigo Largo', {'largo': 1.2, 'caida': 1.3}),
  CreatorVariation('Chasquido Seco', {'largo': .7, 'caida': .55}),
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
    const float W = f.width, H = f.height;
    const float px1 = W / 360.0f;
    const float T = g.caida * 1.0f / pace(f);
    const Color red = f.colors[1], orange = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2654435761u + 17u;
      // Mango fuera de un borde (izquierda, derecha o abajo), apuntando dentro.
      const int side = int(rnd(s + 1u) * 2.999f);
      Vec2 h0;
      float thBase;
      if (side == 0) {
        h0 = {-10.0f * px1, H * (0.3f + 0.4f * rnd(s + 2u))};
        thBase = -0.4f + 0.8f * rnd(s + 3u);
      } else if (side == 1) {
        h0 = {W + 10.0f * px1, H * (0.3f + 0.4f * rnd(s + 2u))};
        thBase = float(pi) - 0.4f + 0.8f * rnd(s + 3u);
      } else {
        h0 = {W * (0.2f + 0.6f * rnd(s + 2u)), H + 10.0f * px1};
        thBase = -0.5f * float(pi) - 0.5f + rnd(s + 3u);
      }
      const float Lw = std::min(W, H) * 1.1f * g.largo * (1.0f < 0.5f ? 0.55f + 0.4f * sz : 1.0f);
      const float k = (rnd(s + 4u) - 0.5f) * 1.8f / Lw;
      const float swing = (rnd(s + 5u) < 0.5f ? -1.0f : 1.0f) * 0.8f;
      // El bucle ya va por el 70 % en el golpe y llega a la punta en unos
      // cuadros, cada vez más rápido y más cerrado.
      const float tc = 0.045f * 1.0f / pace(f);
      // Forma del látigo en el instante tt: el mango barre un arco y el bucle
      // rueda hacia la punta. Devuelve tres tramos de grosor, el bucle y la punta.
      auto build = [&](float tt, float cut, std::array<Path, 3>& seg, Vec2& loop, Vec2& tip) {
        const float P = tt >= tc ? 1.0f : std::max(0.3f, 0.7f + 0.3f * (tt < 0.0f ? tt / tc : (tt / tc) * (tt / tc)));
        const float th0 = thBase + swing * (1.0f - P);
        auto at = [&](float x, float y) -> Vec2 {
          const float th = th0 + k * x;
          const Vec2 o = std::fabs(k) < 1e-6f ? Vec2{h0.x + std::cos(th0) * x, h0.y + std::sin(th0) * x}
                                              : Vec2{h0.x + (std::sin(th) - std::sin(th0)) / k, h0.y - (std::cos(th) - std::cos(th0)) / k};
          return {o.x - std::sin(th) * y, o.y + std::cos(th) * y};
        };
        const float r = 22.0f * px1 * sz * std::pow(1.0f - P, 0.6f) + 0.5f * px1;
        const float A = P * (Lw - float(pi) * r);
        const float wave = 8.0f * px1 * sz;
        bool open[3] = {false, false, false};
        Vec2 last{};
        bool have = false;
        const int N = 90;
        for (int i = 0; i <= N; i++) {
          const float sl = Lw * float(i) / float(N);
          if (sl < cut) continue;
          Vec2 pt;
          if (sl <= A) {
            // Pierna de arriba con una onda que corre hacia la punta.
            pt = at(sl, wave * std::sin(sl / (Lw * 0.18f) * 6.2832f - tt * 40.0f) * (sl / std::max(A, 1.0f)) * (1.0f - P * 0.6f));
          } else if (sl <= A + float(pi) * r) {
            const float ph = (sl - A) / std::max(r, 0.001f);
            pt = at(A + r * std::sin(ph), -r + r * std::cos(ph));
          } else {
            pt = at(A - (sl - A - float(pi) * r), -2.0f * r);
          }
          // Cada tramo empieza donde acabó el anterior.
          const int j = std::min(2, int(3.0f * sl / Lw));
          if (!open[j]) {
            const Vec2 st = have ? last : pt;
            seg[size_t(j)].moveTo(st.x, st.y);
            open[j] = true;
          }
          seg[size_t(j)].lineTo(pt.x, pt.y);
          last = pt;
          have = true;
        }
        loop = at(A, -r);
        tip = at(Lw, 0.0f);
      };
      Paint pt;
      pt.blend = Blend::plus;
      pt.strokeCap = 1;
      pt.strokeJoin = 1;
      const float wm[3] = {1.4f, 1.0f, 0.7f};
      // Estela en abanico del barrido: copias de instantes anteriores.
      if (a < tc + 0.04f) {
        const float tw = 1.0f - clamp01((a - tc) / 0.04f);
        for (int j = 4; j >= 1; j--) {
          std::array<Path, 3> gs;
          Vec2 gl, gt;
          build(a - float(j) * 0.014f, 0.0f, gs, gl, gt);
          const float w = (0.45f - 0.1f * float(j)) * tw;
          for (int i = 0; i < 3; i++) {
            pt.strokeWidth = 16.0f * px1 * wm[i];
            pt.color = tint(red, 0.1f * w * lv);
            c.path(gs[size_t(i)], pt);
            pt.strokeWidth = 4.0f * px1 * wm[i];
            pt.color = tint(orange, 0.45f * w * lv);
            c.path(gs[size_t(i)], pt);
          }
        }
      }
      // Tras el chasquido se apaga desde el mango hacia la punta.
      const float cut = a < tc ? 0.0f : Lw * easeInOut((a - tc) / std::max(T - tc, 0.001f));
      std::array<Path, 3> seg;
      Vec2 loop, tip;
      build(a, cut, seg, loop, tip);
      // Más grueso en el mango y fino en la punta: halo rojo, cuerpo naranja y
      // filo blanco amarillento.
      for (int j = 0; j < 3; j++) {
        pt.strokeWidth = 18.0f * px1 * wm[j];
        pt.color = tint(red, 0.14f * lv);
        c.path(seg[size_t(j)], pt);
        pt.strokeWidth = 5.5f * px1 * wm[j];
        pt.color = tint(orange, 0.5f * lv);
        c.path(seg[size_t(j)], pt);
        pt.strokeWidth = 2.0f * px1 * wm[j];
        pt.color = tint(white, std::min(1.0f, lv));
        c.path(seg[size_t(j)], pt);
      }
      // El bucle es lo más caliente mientras corre.
      if (a < tc) glow(c, loop, 30.0f * px1 * sz, tint(white, 1.0f), orange, 0.95f * lv);
      // Chasquido en la punta: destello, estrella de rayos, anillo y chispas.
      const float ac = a - tc;
      if (ac >= 0.0f) {
        const float tt = ac * pace(f);
        const float boom = std::exp(-tt / (0.09f * 1.0f));
        softGlow(c, tip, 170.0f * px1 * sz, tint(white, 1.0f), orange, 0.55f * boom * lv);
        glow(c, tip, 110.0f * px1 * sz, tint(white, 1.0f), orange, boom * lv);
        Path rays;
        for (int i = 0; i < 10; i++) {
          const float ang = 6.2832f * (float(i) + 0.5f * rnd(s + 80u + uint32_t(i))) / 10.0f;
          const float rl = (30.0f + 70.0f * rnd(s + 90u + uint32_t(i))) * px1 * sz * (0.4f + 0.6f * boom);
          rays.moveTo(tip.x, tip.y).lineTo(tip.x + std::cos(ang) * rl, tip.y + std::sin(ang) * rl);
        }
        pt.strokeWidth = 5.0f * px1;
        pt.color = tint(orange, 0.35f * boom * lv);
        c.path(rays, pt);
        pt.strokeWidth = 1.3f * px1;
        pt.color = tint(white, std::min(1.0f, boom * lv));
        c.path(rays, pt);
        Path ring;
        ring.circle(tip, (10.0f + 560.0f * tt / std::sqrt(1.0f)) * px1 * sz);
        const float rf = std::exp(-tt / (0.16f * 1.0f));
        pt.strokeWidth = 10.0f * px1;
        pt.color = tint(red, 0.14f * rf * lv);
        c.path(ring, pt);
        pt.strokeWidth = 2.4f * px1;
        pt.color = tint(orange, 0.7f * rf * lv);
        c.path(ring, pt);
        for (int i = 0; i < 16; i++) {
          const float ang = 6.2832f * (float(i) + rnd(s + 40u + uint32_t(i))) / 16.0f;
          const float v = (260.0f + 340.0f * rnd(s + 60u + uint32_t(i))) * px1 * sz;
          const float dd = v * (1.0f - std::exp(-tt * 5.0f)) / 5.0f;
          const Vec2 sp = {tip.x + std::cos(ang) * dd, tip.y + std::sin(ang) * dd + 120.0f * px1 * tt * tt};
          glow(c, sp, 10.0f * px1 * sz, tint(white, 1.0f), orange, 0.9f * lv * std::exp(-tt / (0.25f * 1.0f)));
        }
      }
    }
  }
};
''';

const shaderSources = <String, String>{

};
