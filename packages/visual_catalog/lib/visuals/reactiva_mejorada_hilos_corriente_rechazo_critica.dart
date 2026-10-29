// Reactiva Mejorada · Hilos de Corriente — transparencia momentánea. Con el golpe entra en la escena
// un peine de hilos de humo luminoso, como en un túnel de viento: una docena
// de hilos azul eléctrico e índigo, separados sin ritmo, que se apartan y se
// aprietan al pasar junto a obstáculos invisibles y, detrás de ellos, se
// ponen a ondear y se deshilachan en turbulencia. El humo avanza con la
// corriente; al cortarse, la cola de los hilos se va río abajo. Cada golpe
// sopla en otro sentido y con otros obstáculos. Sólo suma luz. Referente:
// la visualización con hilos de humo en los túneles de viento.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo', 'Bombo y caja', 'Cada pulso']),
  // FORMA: cuántos hilos.
  CreatorModifier.slider('hilos', 'Hilos', min: .5, max: 1, value: .8),
  // MOVIMIENTO: cuánto dura.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.6, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Peine Denso', {'hilos': 1, 'caida': 1.4}),
  CreatorVariation('Pocos Hilos', {'hilos': .5, 'caida': .55}),
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
    const float T = g.caida * 1.3f * 0.45f / pace(f);
    const Color indigo = f.colors[1], blue = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2246822519u + 101u;
      const Vec2 o = {W * 0.5f, H * (0.3f + 0.4f * rnd(s + 1u))};
      // Sopla hacia un lado u otro, algo inclinado.
      const float tilt = (rnd(s + 2u) - 0.5f) * 0.5f + (rnd(s + 3u) < 0.5f ? 0.0f : float(pi));
      const Vec2 dir = {std::cos(tilt), std::sin(tilt)};
      const float size = 0.45f < 0.5f ? 0.55f + 0.45f * sz : 1.0f;
      // El humo ya va por el 60 % en el golpe; al cortarse, la cola se aleja.
      const float age = a * pace(f);
      const float front = -240.0f + 480.0f * (0.6f + 0.4f * easeOut(clamp01(age / (0.4f * 0.45f))));
      const float tail = -260.0f + 520.0f * easeInOut((q - 0.45f) / 0.55f);
      const float half = (150.0f * size + 40.0f) * px1;
      const float ext = std::hypot(W, H) * 0.6f;
      const Vec2 e0 = {o.x - dir.x * ext, o.y - dir.y * ext}, e1 = {o.x + dir.x * ext, o.y + dir.y * ext};
      const float x0 = std::max(0.0f, std::min(e0.x, e1.x) - half), x1 = std::min(W, std::max(e0.x, e1.x) + half);
      const float y0 = std::max(0.0f, std::min(e0.y, e1.y) - half), y1 = std::min(H, std::max(e0.y, e1.y) + half);
      if (x1 - x0 < 1.0f || y1 - y0 < 1.0f) continue;
      c.material("streak", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, o.x, o.y, dir.x, dir.y, px1, age, front, tail, size, g.hilos, rnd(s + 4u), lv,
                  indigo.r, indigo.g, indigo.b, blue.r, blue.g, blue.b, white.r, white.g, white.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'streak': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform vec2 uOrigin;
uniform vec2 uDir;
uniform float uPx;
uniform float uAge;
uniform float uFront;
uniform float uTail;
uniform float uScale;
uniform float uCount;
uniform float uSeed;
uniform float uAmp;
uniform vec3 uIndigo;
uniform vec3 uBlue;
uniform vec3 uWhite;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
float vnoise2(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    s += a * vnoise2(p);
    // Cada octava girada: los contornos no siguen la rejilla del ruido.
    p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.03 + vec2(1.7, 9.2);
    a *= 0.5;
  }
  return s;
}
vec2 rot(vec2 v, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Función de corriente: flujo uniforme apartado por dos obstáculos suaves
// (sin hueco) y, detrás de cada uno, una estela que ondea y se deshilacha.
float psi(vec2 q) {
  float s = q.y;
  for (int i = 0; i < 2; i++) {
    float fi = float(i);
    vec2 c = vec2((-60.0 + 120.0 * fi + 40.0 * (hash(fi + uSeed * 7.0) - 0.5)) * uScale, (hash(fi * 3.0 + uSeed * 5.0) - 0.5) * 120.0 * uScale);
    float rs = (26.0 + 16.0 * hash(fi * 5.0 + uSeed)) * uScale;
    vec2 dc = q - c;
    s -= 1.6 * rs * (dc.y / rs) * exp(-dot(dc, dc) / (2.2 * rs * rs));
    float down = max(dc.x, 0.0);
    float wake = smoothstep(0.0, 60.0 * uScale, down) * exp(-dc.y * dc.y / (2.0 * (1.2 * rs + 0.25 * down) * (1.2 * rs + 0.25 * down)));
    s += wake * (11.0 + 0.1 * down) * uScale * sin(down / (22.0 * uScale) - uAge * 7.0 + fi * 2.0 + uSeed * 6.0);
    s += wake * 28.0 * uScale * (fbm(vec2(down / 30.0 - uAge * 2.5, dc.y / 18.0) + uSeed * 4.0) - 0.5) * smoothstep(40.0, 160.0, down);
  }
  return s;
}

void main() {
  vec2 lp = FlutterFragCoord().xy;
  float inside = step(lp.x, uSize.x + 1.0) * step(lp.y, uSize.y + 1.0);
  vec2 d = (lp + uOffset - uOrigin) / uPx;
  vec2 q = vec2(dot(d, uDir), dot(d, vec2(-uDir.y, uDir.x)));
  if (abs(q.y) > 190.0 * uScale + 30.0 || q.x > uFront + 30.0 || q.x < uTail - 30.0) {
    fragColor = vec4(0.0);
    return;
  }
  float P = psi(q);
  float g = max(0.25 * length(vec2(psi(q + vec2(2.0, 0.0)) - psi(q - vec2(2.0, 0.0)), psi(q + vec2(0.0, 2.0)) - psi(q - vec2(0.0, 2.0)))), 0.3);
  // Hilos del peine con separación sin ritmo (18-42 px) y brillo distinto.
  float L = 0.0;
  float tint = 0.0;
  float ystart = -150.0 * uScale;
  float y = ystart;
  for (int i = 0; i < 14; i++) {
    float fi = float(i);
    y += (18.0 + 24.0 * hash(fi * 2.7 + uSeed * 13.0)) * uScale / max(uCount, 0.5);
    if (y > 150.0 * uScale) break;
    float dist = (P - y) / g;
    float ww = 3.2 + 1.6 * hash(fi * 4.3 + uSeed);
    float fold = smoothstep(2.5, 5.0, g);
    float li = mix(0.62 * exp(-dist * dist / (ww * ww)) + 0.2 * exp(-dist * dist / (8.0 * ww * ww)), 0.0, fold);
    float br = 0.75 + 0.25 * hash(fi * 6.1 + uSeed * 3.0);
    L += li * br;
    tint += li * br * (y - ystart) / (300.0 * uScale);
  }
  tint /= max(L, 1e-4);
  // El humo entra por delante y la cola se aleja al final; junto a la
  // cabeza del humo, un poco más brillante.
  float ends = smoothstep(uFront + 25.0, uFront - 25.0, q.x + 20.0 * (fbm(vec2(q.y / 30.0, uSeed)) - 0.5)) * smoothstep(uTail - 25.0, uTail + 25.0, q.x);
  float grain = 0.88 + 0.24 * fbm(q / 11.0 + vec2(-uAge * 2.0, uSeed * 6.0));
  L *= ends * grain * uAmp * inside;
  L = L < 0.85 ? L : 0.85 + 0.15 * (1.0 - exp(-(L - 0.85) / 0.15));
  vec3 cI = mix(vec3(0.32, 0.12, 1.0), uIndigo / max(uIndigo.b, 0.01), 0.15);
  vec3 cB = mix(vec3(0.08, 0.42, 1.0), uBlue / max(uBlue.b, 0.01), 0.15);
  vec3 col = mix(cI, cB, clamp(tint, 0.0, 1.0));
  col = mix(col, mix(uWhite, vec3(1.0), 0.5), smoothstep(0.92, 0.99, L));
  vec3 tone = min(col * L, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
