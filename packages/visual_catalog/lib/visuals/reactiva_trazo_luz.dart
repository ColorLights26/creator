// Reactiva · Trazo de Luz — transparencia momentánea. Con el golpe una luz pinta en el aire
// un trazo caligráfico con un bucle, como en el light painting de larga
// exposición: la cabeza quemada avanza y todo el trazo sigue encendido detrás,
// más fino o más grueso según la dirección (como una plumilla), blanco cerca
// de la cabeza y oro, naranja y rojo vivo hacia la cola; luego la cola se
// recoge. Cada golpe pinta un trazo distinto. Sólo suma luz. Referente: light
// painting de larga exposición.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: tamaño del trazo.
  CreatorModifier.slider('tamano', 'Tamaño del trazo', min: .6, max: 1.3, value: 1),
  // MOVIMIENTO: rapidez del trazo.
  CreatorModifier.slider('rapidez', 'Rapidez', min: .6, max: 1.8, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Firma', {'tamano': 1.25, 'rapidez': .8}),
  CreatorVariation('Látigo', {'tamano': .75, 'rapidez': 1.7}),
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
  static Vec2 bez(Vec2 a, Vec2 b, Vec2 c, Vec2 d, float t) {
    const float u = 1.0f - t;
    const float w0 = u * u * u, w1 = 3.0f * u * u * t, w2 = 3.0f * u * t * t, w3 = t * t * t;
    return {w0 * a.x + w1 * b.x + w2 * c.x + w3 * d.x, w0 * a.y + w1 * b.y + w2 * c.y + w3 * d.y};
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height;
    const float px1 = W / 360.0f;
    const Color red = f.colors[1], orange = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      // Un trazo con bucle: los puntos de control se cruzan.
      const bool flip = (p.id % 2u) == 1u;
      // Grande: ocupa de lado a lado y más de un tercio del alto, con un
      // bucle de 80-90 px.
      const float span = (1.0f < 0.5f ? 290.0f * sz : 320.0f) * px1 * g.tamano;
      const float cx = W * (0.42f + 0.16f * rnd(p.id * 3u + 1u)), cy = H * (0.4f + 0.2f * rnd(p.id * 5u + 2u));
      const float ang = (rnd(p.id * 7u + 3u) - 0.5f) * 1.2f + (flip ? float(pi) : 0.0f);
      const Vec2 dir = {std::cos(ang), std::sin(ang)}, nrm = {-dir.y, dir.x};
      const float side = rnd(p.id * 11u + 4u) < 0.5f ? -1.0f : 1.0f;
      const Vec2 P0 = {cx - dir.x * span * 0.5f, cy - dir.y * span * 0.5f};
      const Vec2 P3 = {cx + dir.x * span * 0.5f, cy + dir.y * span * 0.5f};
      const Vec2 P1 = {P0.x + dir.x * span * 1.3f + nrm.x * span * 1.1f * side, P0.y + dir.y * span * 1.3f + nrm.y * span * 1.1f * side};
      const Vec2 P2 = {P3.x - dir.x * span * 1.3f + nrm.x * span * 1.1f * side, P3.y - dir.y * span * 1.3f + nrm.y * span * 1.1f * side};
      // Largo del trazo para medir el tiempo de dibujo y de recogida.
      float len = 0.0f;
      Vec2 prev = P0;
      for (int i = 1; i <= 48; i++) {
        const Vec2 cur = bez(P0, P1, P2, P3, float(i) / 48.0f);
        len += std::hypot(cur.x - prev.x, cur.y - prev.y);
        prev = cur;
      }
      const float draw = (1.0f < 0.5f ? 0.2f : 0.45f) / (pace(f) * g.rapidez);
      const float speed = 750.0f * px1 * pace(f);
      const float T = draw + len / speed + 0.05f;
      if (a < 0.0f || a > T) continue;
      // La cabeza ya se ve en el cuadro del golpe; la cola se recoge al acabar.
      const float headU = std::min(1.0f, 0.08f + 0.92f * easeOut(clamp01(a / draw)));
      const float tailU = std::min(headU, std::max(0.0f, (a - draw) * speed / std::max(len, 1.0f)));
      if (headU - tailU < 0.003f) continue;
      std::array<Vec2, 24> pts;
      float x0 = W, y0 = H, x1 = 0.0f, y1 = 0.0f;
      for (int i = 0; i < 24; i++) {
        pts[size_t(i)] = bez(P0, P1, P2, P3, tailU + (headU - tailU) * float(i) / 23.0f);
        x0 = std::min(x0, pts[size_t(i)].x);
        y0 = std::min(y0, pts[size_t(i)].y);
        x1 = std::max(x1, pts[size_t(i)].x);
        y1 = std::max(y1, pts[size_t(i)].y);
      }
      // Margen amplio para que ningún resplandor se corte en el borde.
      const float mg = 80.0f * px1;
      x0 = std::max(0.0f, x0 - mg);
      y0 = std::max(0.0f, y0 - mg);
      x1 = std::min(W, x1 + mg);
      y1 = std::min(H, y1 + mg);
      if (x1 <= x0 || y1 <= y0) continue;
      const float head = a < draw ? 1.0f : 1.0f - clamp01((a - draw) / 0.1f);
      std::vector<float> u;
      u.reserve(64);
      u.push_back(x0);
      u.push_back(y0);
      u.push_back(px1);
      u.push_back(pts[0].x);
      u.push_back(pts[0].y);
      u.push_back(pts[1].x);
      u.push_back(pts[1].y);
      u.push_back(pts[2].x);
      u.push_back(pts[2].y);
      u.push_back(pts[3].x);
      u.push_back(pts[3].y);
      u.push_back(pts[4].x);
      u.push_back(pts[4].y);
      u.push_back(pts[5].x);
      u.push_back(pts[5].y);
      u.push_back(pts[6].x);
      u.push_back(pts[6].y);
      u.push_back(pts[7].x);
      u.push_back(pts[7].y);
      u.push_back(pts[8].x);
      u.push_back(pts[8].y);
      u.push_back(pts[9].x);
      u.push_back(pts[9].y);
      u.push_back(pts[10].x);
      u.push_back(pts[10].y);
      u.push_back(pts[11].x);
      u.push_back(pts[11].y);
      u.push_back(pts[12].x);
      u.push_back(pts[12].y);
      u.push_back(pts[13].x);
      u.push_back(pts[13].y);
      u.push_back(pts[14].x);
      u.push_back(pts[14].y);
      u.push_back(pts[15].x);
      u.push_back(pts[15].y);
      u.push_back(pts[16].x);
      u.push_back(pts[16].y);
      u.push_back(pts[17].x);
      u.push_back(pts[17].y);
      u.push_back(pts[18].x);
      u.push_back(pts[18].y);
      u.push_back(pts[19].x);
      u.push_back(pts[19].y);
      u.push_back(pts[20].x);
      u.push_back(pts[20].y);
      u.push_back(pts[21].x);
      u.push_back(pts[21].y);
      u.push_back(pts[22].x);
      u.push_back(pts[22].y);
      u.push_back(pts[23].x);
      u.push_back(pts[23].y);
      u.push_back((headU - tailU) * len / px1);
      u.push_back(0.6f + 2.0f * rnd(p.id * 13u + 5u));
      u.push_back(head);
      u.push_back(lv);
      for (const Color& col : {red, orange, white}) {
        u.push_back(col.r);
        u.push_back(col.g);
        u.push_back(col.b);
      }
      c.material("trail", {x0, y0, x1 - x0, y1 - y0}, u);
    }
  }
};
''';

const shaderSources = <String, String>{
  'trail': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform float uPx;
uniform vec2 uP0;
uniform vec2 uP1;
uniform vec2 uP2;
uniform vec2 uP3;
uniform vec2 uP4;
uniform vec2 uP5;
uniform vec2 uP6;
uniform vec2 uP7;
uniform vec2 uP8;
uniform vec2 uP9;
uniform vec2 uP10;
uniform vec2 uP11;
uniform vec2 uP12;
uniform vec2 uP13;
uniform vec2 uP14;
uniform vec2 uP15;
uniform vec2 uP16;
uniform vec2 uP17;
uniform vec2 uP18;
uniform vec2 uP19;
uniform vec2 uP20;
uniform vec2 uP21;
uniform vec2 uP22;
uniform vec2 uP23;
uniform float uLen;
uniform float uNib;
uniform float uHead;
uniform float uAmp;
uniform vec3 uRed;
uniform vec3 uOrange;
uniform vec3 uWhite;
out vec4 fragColor;

// Distancia (px de 360) al tramo i de la estela, su posición a lo largo (0 en
// la cola, 1 en la cabeza) y su ancho caligráfico según la dirección.
// Luz de un tramo; la estela usa el máximo de todos los tramos (continuo, sin
// cuñas en los cruces del bucle). Blanca sólo a 12-15 px de la cabeza y la
// cola se afina y se apaga.
void seg(vec2 q, vec2 a, vec2 b, float i, inout float d, inout float s, inout float w) {
  vec2 ab = b - a;
  float t = clamp(dot(q - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
  float dd = length(q - a - ab * t);
  float ss = (i + t) / 23.0;
  float ww = (2.8 + 7.8 * abs(sin(atan(ab.y, ab.x) - uNib))) * mix(0.5, 1.0, smoothstep(0.0, 0.25, ss));
  float distHead = (1.0 - ss) * uLen;
  float B = (0.43 + 0.42 * exp(-distHead / 7.0)) * smoothstep(0.0, 0.1, ss);
  float sg = ww / 2.355;
  float lv = (exp(-dd * dd / (2.0 * sg * sg)) + 0.8 * exp(-dd / 12.0)) * B;
  if (lv > d) {
    d = lv;
    s = ss;
    w = ww;
  }
}

void main() {
  vec2 q = (FlutterFragCoord().xy + uOffset) / uPx;
  float d = 0.0;
  float s = 0.0;
  float w = 4.0;
  seg(q, uP0 / uPx, uP1 / uPx, 0.0, d, s, w);
  seg(q, uP1 / uPx, uP2 / uPx, 1.0, d, s, w);
  seg(q, uP2 / uPx, uP3 / uPx, 2.0, d, s, w);
  seg(q, uP3 / uPx, uP4 / uPx, 3.0, d, s, w);
  seg(q, uP4 / uPx, uP5 / uPx, 4.0, d, s, w);
  seg(q, uP5 / uPx, uP6 / uPx, 5.0, d, s, w);
  seg(q, uP6 / uPx, uP7 / uPx, 6.0, d, s, w);
  seg(q, uP7 / uPx, uP8 / uPx, 7.0, d, s, w);
  seg(q, uP8 / uPx, uP9 / uPx, 8.0, d, s, w);
  seg(q, uP9 / uPx, uP10 / uPx, 9.0, d, s, w);
  seg(q, uP10 / uPx, uP11 / uPx, 10.0, d, s, w);
  seg(q, uP11 / uPx, uP12 / uPx, 11.0, d, s, w);
  seg(q, uP12 / uPx, uP13 / uPx, 12.0, d, s, w);
  seg(q, uP13 / uPx, uP14 / uPx, 13.0, d, s, w);
  seg(q, uP14 / uPx, uP15 / uPx, 14.0, d, s, w);
  seg(q, uP15 / uPx, uP16 / uPx, 15.0, d, s, w);
  seg(q, uP16 / uPx, uP17 / uPx, 16.0, d, s, w);
  seg(q, uP17 / uPx, uP18 / uPx, 17.0, d, s, w);
  seg(q, uP18 / uPx, uP19 / uPx, 18.0, d, s, w);
  seg(q, uP19 / uPx, uP20 / uPx, 19.0, d, s, w);
  seg(q, uP20 / uPx, uP21 / uPx, 20.0, d, s, w);
  seg(q, uP21 / uPx, uP22 / uPx, 21.0, d, s, w);
  seg(q, uP22 / uPx, uP23 / uPx, 22.0, d, s, w);
  float L = d * uAmp;
  // La cabeza: quemada sólo en 3 px y cayendo a cero hacia los 40 px.
  vec2 hd = q - uP23 / uPx;
  float rh = length(hd);
  L += (0.5 * exp(-rh * rh / 4.0) + 0.2 * exp(-rh / 10.0)) * uHead * uAmp;
  // Rodilla suave: sólo el pico de verdad llega a quemarse.
  L = L < 0.8 ? L : 0.8 + 0.2 * (1.0 - exp(-(L - 0.8) / 0.2));
  // Color por el brillo final: blanco, oro, naranja y rojo vivo.
  vec3 red = mix(vec3(1.0, 0.14, 0.05), uRed / max(uRed.r, 0.01), 0.15);
  vec3 orRed = vec3(1.0, 0.29, 0.05);
  vec3 gold = mix(vec3(1.0, 0.7, 0.22), uOrange / max(uOrange.r, 0.01), 0.15);
  vec3 col = mix(red, orRed, smoothstep(0.3, 0.52, L));
  col = mix(col, gold, smoothstep(0.62, 0.8, L));
  col = mix(col, mix(uWhite, vec3(1.0), 0.6), smoothstep(0.9, 0.99, L));
  vec3 tone = min(col * L, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
