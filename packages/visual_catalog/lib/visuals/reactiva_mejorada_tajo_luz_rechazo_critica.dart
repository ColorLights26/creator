// Reactiva Mejorada · Tajo de Luz — transparencia momentánea. Con el golpe un tajo de luz corta la
// escena en una media luna: un arco grande que se traza en un parpadeo, con
// el filo exterior blanco y nítido y el cuerpo carmesí que se desvanece hacia
// dentro, afinado en las dos puntas, con unas líneas de velocidad paralelas
// por dentro y chispas que salen despedidas por el final del corte. Después
// la media luna adelgaza hasta desaparecer. Carmesí intenso y naranja con el
// filo blanco; cada golpe corta con otro ángulo, otro tamaño y otro sentido.
// Sólo suma luz. Referente: los cortes de espada de luz de la animación.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo', 'Bombo y caja', 'Cada pulso']),
  // FORMA: tamaño del tajo.
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.4, value: 1),
  // MOVIMIENTO: cuánto dura.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.5, value: .9),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Gran Corte', {'tamano': 1.35, 'caida': 1.3}),
  CreatorVariation('Corte Rápido', {'tamano': .7, 'caida': .55}),
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
    const Color deep = f.colors[1], hot = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2654435761u + 53u;
      // Arco que pasa por un punto central de la pantalla.
      const float R = (0.45f < 0.5f ? 130.0f + 80.0f * rnd(s + 1u) : 170.0f + 130.0f * rnd(s + 1u)) * px1 * sz * g.tamano;
      const Vec2 mid = {W * (0.3f + 0.4f * rnd(s + 2u)), H * (0.3f + 0.4f * rnd(s + 3u))};
      const float th = 6.2832f * rnd(s + 4u);
      const Vec2 cen = {mid.x - std::cos(th) * R, mid.y - std::sin(th) * R};
      const float halfSpan = 0.85f + 0.3f * rnd(s + 5u);
      const float dirS = rnd(s + 6u) < 0.5f ? -1.0f : 1.0f;
      // Ya trazado al 60 % en el golpe, completo en tres cuadros; luego
      // adelgaza hasta desaparecer.
      const float sweep = std::min(1.0f, 0.6f + 0.4f * a * pace(f) / (0.05f * 0.45f));
      const float thin = 1.0f - easeInOut((q - 0.1f) / 0.9f);
      const float wm = 40.0f * sz * g.tamano;
      const float m = (wm + 50.0f) * px1 + R;
      const float x0 = std::max(0.0f, cen.x - m), x1 = std::min(W, cen.x + m);
      const float y0 = std::max(0.0f, cen.y - m), y1 = std::min(H, cen.y + m);
      if (x1 - x0 < 1.0f || y1 - y0 < 1.0f) continue;
      c.material("slash", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, cen.x, cen.y, px1, R / px1, th, halfSpan, dirS, sweep, thin, wm, lv,
                  deep.r, deep.g, deep.b, hot.r, hot.g, hot.b, white.r, white.g, white.b});
      // Chispas despedidas por el final del corte, en la dirección del tajo.
      const float ae = th + dirS * halfSpan;
      const Vec2 endP = {cen.x + std::cos(ae) * R, cen.y + std::sin(ae) * R};
      const Vec2 tg = {-std::sin(ae) * dirS, std::cos(ae) * dirS};
      const float ts = a * pace(f) - 0.05f * 0.45f;
      if (ts > 0.0f) {
        for (int i = 0; i < 14; i++) {
          const float spread = (rnd(s + 20u + uint32_t(i)) - 0.5f) * 0.9f;
          const Vec2 dv = {tg.x * std::cos(spread) - tg.y * std::sin(spread), tg.x * std::sin(spread) + tg.y * std::cos(spread)};
          const float v = (300.0f + 400.0f * rnd(s + 40u + uint32_t(i))) * px1 * sz;
          const float dd = v * (1.0f - std::exp(-ts * 4.0f)) / 4.0f;
          const Vec2 sp = {endP.x + dv.x * dd, endP.y + dv.y * dd + 90.0f * px1 * ts * ts};
          glow(c, sp, 9.0f * px1 * sz, tint(white, 1.0f), hot, 0.9f * lv * std::exp(-ts / (0.22f * 0.45f)));
        }
      }
    }
  }
};
''';

const shaderSources = <String, String>{
  'slash': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform vec2 uCenter;
uniform float uPx;
uniform float uRadius;
uniform float uMidAng;
uniform float uHalfSpan;
uniform float uDirS;
uniform float uSweep;
uniform float uThin;
uniform float uWidth;
uniform float uAmp;
uniform vec3 uDeep;
uniform vec3 uMid;
uniform vec3 uWhite;
out vec4 fragColor;

void main() {
  vec2 lp = FlutterFragCoord().xy;
  float inside = step(lp.x, uSize.x + 1.0) * step(lp.y, uSize.y + 1.0);
  vec2 d = (lp + uOffset - uCenter) / uPx;
  float r = length(d);
  float rel = atan(d.y, d.x) - uMidAng;
  rel = mod(rel + 3.14159265, 6.2831853) - 3.14159265;
  // Posición a lo largo del tajo: 0 al empezar, 1 al acabar.
  float t = (rel * uDirS / uHalfSpan + 1.0) * 0.5;
  float vis = smoothstep(uSweep + 0.02, uSweep - 0.04, t) * smoothstep(-0.02, 0.03, t);
  float prof = pow(clamp(sin(3.14159265 * clamp(t, 0.0, 1.0)), 0.0, 1.0), 0.8);
  float w = uWidth * prof * uThin + 0.6;
  // Media luna: filo exterior nítido y cuerpo que se desvanece hacia dentro.
  float x = (uRadius - r) / w;
  float body = x < 0.0 ? exp(-(x * w / 1.5) * (x * w / 1.5)) : exp(-x * 2.4);
  float edge = exp(-(x * w) * (x * w) / 1.8);
  // Líneas de velocidad paralelas por dentro, más cortas.
  float lines = 0.0;
  for (int i = 1; i <= 3; i++) {
    float ri = uRadius - w * (1.0 + 0.45 * float(i)) - 3.0 * float(i);
    float li = exp(-(r - ri) * (r - ri) / 1.2) * smoothstep(0.15 * float(i), 0.15 * float(i) + 0.1, t) * smoothstep(1.0 - 0.12 * float(i), 0.9 - 0.12 * float(i), t);
    lines += 0.35 * li * uThin;
  }
  float halo = 0.18 * exp(-abs(x * w) / 14.0) * prof;
  // La cabeza del trazo es lo más caliente mientras corta.
  float head = 1.0 + 0.4 * exp(-abs(t - uSweep) * 25.0) * step(uSweep, 0.999);
  float L = ((body * 0.75 + edge * 0.55) * prof * head + lines + halo) * vis * uAmp * inside;
  L = L < 0.85 ? L : 0.85 + 0.15 * (1.0 - exp(-(L - 0.85) / 0.15));
  vec3 dim = mix(vec3(1.0, 0.06, 0.22), uDeep / max(max(uDeep.r, max(uDeep.g, uDeep.b)), 0.01), 0.15);
  vec3 mid = mix(vec3(1.0, 0.36, 0.14), uMid / max(max(uMid.r, max(uMid.g, uMid.b)), 0.01), 0.15);
  vec3 col = mix(dim, mid, smoothstep(0.4, 0.7, L));
  col = mix(col, mix(uWhite, vec3(1.0), 0.5), smoothstep(0.92, 0.99, L));
  vec3 tone = min(col * L, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
