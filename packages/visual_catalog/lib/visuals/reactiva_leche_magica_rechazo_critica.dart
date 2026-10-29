// Reactiva · Leche Mágica — transparencia momentánea. Con el golpe cae una gota de jabón en
// el centro de unas gotas de tinte de colores y el tinte sale disparado hacia
// fuera en vetas, como en el experimento de la leche mágica: rojo, ámbar y
// azul eléctrico estirados en lenguas que corren más deprisa en unos sitios
// que en otros, girando un poco, dejando el centro limpio. Al final el tinte
// se adelgaza en hilos hasta desaparecer. Donde dos colores se montan manda
// el más fuerte. Cada golpe cae en otro sitio. Sólo suma luz. Referente: el
// experimento de la leche mágica a cámara lenta.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: hasta dónde se abre el tinte.
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.4, value: 1),
  // MOVIMIENTO: cuánto dura.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.6, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Gran Estallido', {'tamano': 1.35, 'caida': 1.4}),
  CreatorVariation('Gota Rápida', {'tamano': .7, 'caida': .55}),
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
    const float T = g.caida * 1.2f * 1.0f / pace(f);
    const Color red = f.colors[1], amber = f.colors[2], blue = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2654435761u + 59u;
      const Vec2 o = {W * (0.3f + 0.4f * rnd(s + 1u)), H * (0.3f + 0.4f * rnd(s + 2u))};
      // El jabón empuja el tinte hacia fuera: ya a medio abrir en el golpe y
      // frenando después.
      const float size = g.tamano * (1.0f < 0.5f ? sz : 1.0f);
      const float reach = 110.0f * size;
      const float spread = 0.45f + 1.5f * (1.0f - std::exp(-(a * pace(f) + 0.1f) / 0.35f));
      // Al final el tinte se adelgaza en hilos.
      const float thr = 0.6f * easeInOut((q - 0.35f) / 0.65f);
      // Margen para las vetas más largas (hasta unos 220 px del centro).
      const float m = (reach * 2.3f + 40.0f) * px1;
      const float x0 = std::max(0.0f, o.x - m), x1 = std::min(W, o.x + m);
      const float y0 = std::max(0.0f, o.y - m), y1 = std::min(H, o.y + m);
      if (x1 - x0 < 1.0f || y1 - y0 < 1.0f) continue;
      c.material("milk", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, o.x, o.y, px1, spread, thr, 1.2f * (1.0f - std::exp(-a * pace(f) / 0.3f)), size, rnd(s + 3u), lv,
                  red.r, red.g, red.b, amber.r, amber.g, amber.b, blue.r, blue.g, blue.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'milk': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform vec2 uCenter;
uniform float uPx;
uniform float uSpread;
uniform float uThr;
uniform float uSwirl;
uniform float uScale;
uniform float uSeed;
uniform float uAmp;
uniform vec3 uRed;
uniform vec3 uAmber;
uniform vec3 uBlue;
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
    p = p * 2.03 + vec2(1.7, 9.2);
    a *= 0.5;
  }
  return s;
}

void main() {
  vec2 lp = FlutterFragCoord().xy;
  float inside = step(lp.x, uSize.x + 1.0) * step(lp.y, uSize.y + 1.0);
  vec2 d = (lp + uOffset - uCenter) / uPx;
  float r = length(d);
  vec2 dv = d / max(r, 0.001);
  // La leche corre más deprisa en unos ángulos que en otros: vetas.
  float gn = 0.55 * vnoise2(dv * 3.0 + uSeed * 7.0) + 0.3 * vnoise2(dv * 8.0 + uSeed * 3.0) + 0.15 * vnoise2(dv * 19.0 + uSeed * 5.0);
  float g = 0.25 + 2.2 * gn * gn;
  // De dónde venía este punto: el jabón estira el tinte hacia fuera, más
  // en unos ángulos que en otros (vetas largas y cortas).
  float stretch = 1.0 + uSpread * g;
  float r0 = r / stretch;
  float r0sq = r0 * r0 - 64.0 * uScale * uScale;
  float th0 = atan(d.y, d.x) - uSwirl * exp(-r0 / (40.0 * uScale));
  vec2 p0 = vec2(cos(th0), sin(th0)) * r0;
  // Cinco gotas de tinte iniciales alrededor del jabón.
  float lr = 0.0;
  float la = 0.0;
  float lb = 0.0;
  for (int i = 0; i < 5; i++) {
    // Gotas de tamaños y sitios distintos, sin simetría.
    float hi = hash(float(i) * 7.1 + uSeed * 19.0);
    float ai = uSeed * 6.2832 + float(i) * 1.2566 + (hi - 0.5) * 1.1;
    vec2 pi = vec2(cos(ai), sin(ai)) * (10.0 + 18.0 * hash(float(i) * 3.3 + uSeed * 5.0)) * uScale;
    vec2 e = p0 - pi;
    float rad = (14.0 + 18.0 * hi) * uScale;
    float di = exp(-dot(e, e) / (rad * rad));
    if (i == 0 || i == 3) {
      lr += di;
    } else if (i == 1 || i == 4) {
      la += di;
    } else {
      lb += di;
    }
  }
  // Centro limpio y el tinte que se adelgaza en hilos al final.
  float clear = smoothstep(0.0, 120.0 * uScale * uScale, r0sq);
  lr = smoothstep(uThr, uThr + 0.25, lr) * min(lr, 1.0) * clear;
  la = smoothstep(uThr, uThr + 0.25, la) * min(la, 1.0) * clear;
  lb = smoothstep(uThr, uThr + 0.25, lb) * min(lb, 1.0) * clear;
  lr *= 0.82 * uAmp * inside;
  la *= 0.82 * uAmp * inside;
  lb *= 0.82 * uAmp * inside;
  // Color por el brillo final de cada tinte.
  vec3 cR = mix(vec3(1.0, 0.1, 0.06), uRed / max(uRed.r, 0.01), 0.15);
  vec3 cA = mix(vec3(1.0, 0.27, 0.04), vec3(1.0, 0.45, 0.05), smoothstep(0.62, 0.7, la));
  cA = mix(cA, mix(vec3(1.0, 0.64, 0.1), uAmber / max(uAmber.r, 0.01), 0.15), smoothstep(0.72, 0.8, la));
  vec3 cB = mix(vec3(0.1, 0.3, 1.0), mix(vec3(0.3, 0.55, 1.0), uBlue / max(uBlue.b, 0.01), 0.15), smoothstep(0.6, 0.8, lb));
  // Donde se montan manda el más fuerte y la luz se suma en parte.
  float wr = lr * lr * lr * lr;
  float wa = la * la * la * la;
  float wb = lb * lb * lb * lb;
  vec3 hue = (cR * wr + cA * wa + cB * wb) / max(wr + wa + wb, 1e-5);
  hue -= 0.8 * min(hue.r, min(hue.g, hue.b));
  hue /= max(max(hue.r, max(hue.g, hue.b)), 1e-4);
  float mx = max(lr, max(la, lb));
  float L = mx + 0.25 * (lr + la + lb - mx);
  L = L < 0.85 ? L : 0.85 + 0.15 * (1.0 - exp(-(L - 0.85) / 0.15));
  hue = mix(hue, vec3(1.0, 0.97, 0.92), smoothstep(0.93, 0.99, L));
  vec3 tone = min(hue * L, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
