// Reactiva · Salpicadura UV — transparencia momentánea. Con el golpe aparece una
// salpicadura de pintura fluorescente que brilla como bajo luz negra: una mancha
// central con espesor, gotas alrededor y regueros que salen disparados, en
// verde neón, naranja o violeta UV, más intensa donde la pintura es más gruesa y
// con un halo que se derrama. Se apaga encogiéndose (primero las gotas). Cada
// golpe salpica en otro sitio y otro color. Sólo suma luz. Referente: pintura
// neón en fiestas de luz negra.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: tamaño de la salpicadura.
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.5, value: 1),
  // MOVIMIENTO: cuánto dura.
  CreatorModifier.slider('caida', 'Duración', min: .4, max: 1.6, value: .9),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Lienzo UV', {'tamano': 1.45, 'caida': 1.5}),
  CreatorVariation('Gotitas', {'tamano': .65, 'caida': .5}),
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
    const float T = g.caida * 1.0f / pace(f);
    const Color green = f.colors[1], orange = f.colors[2], violet = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      // El volumen cambia el tamaño, no el brillo del color.
      const float k = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const float x = W * (0.2f + 0.6f * rnd(p.id * 7u + 1u));
      const float y = H * (0.2f + 0.6f * rnd(p.id * 9u + 2u));
      const float R = 0.55f * W * g.tamano * (1.0f < 0.5f ? 0.65f : 1.0f) * sz;
      const float reach = 1.3f * R;
      const float x0 = std::max(0.0f, x - reach), y0 = std::max(0.0f, y - reach);
      const float x1 = std::min(W, x + reach), y1 = std::min(H, y + reach);
      if (x1 <= x0 || y1 <= y0) continue;
      c.material("splat", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, W, x, y, R, a / T, k, float(p.id % 3u), rnd(p.id * 5u + 3u),
                  green.r, green.g, green.b, orange.r, orange.g, orange.b, violet.r, violet.g, violet.b},
                 {"noise"});
    }
  }
};
''';

const shaderSources = <String, String>{
  'splat': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform float uWidth;
uniform vec2 uCenter;
uniform float uR;
uniform float uAge;
uniform float uAmp;
uniform float uHue;
uniform float uSeed;
uniform vec3 uGreen;
uniform vec3 uOrange;
uniform vec3 uViolet;
uniform sampler2D uTex;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
  vec2 p = FlutterFragCoord().xy + uOffset;
  float px1 = uWidth / 360.0;
  vec2 v = (p - uCenter) / px1;
  float Rpx = uR / px1;
  float a = uAge;
  // Aparece de golpe (las gotas salen en dos cuadros) y se encoge al final:
  // primero las gotas, luego la mancha.
  float shoot = 0.6 + 0.4 * (1.0 - pow(1.0 - min(a / 0.08, 1.0), 2.0));
  float shrinkD = 1.0 - smoothstep(0.35, 0.8, a);
  float shrinkM = 1.0 - smoothstep(0.55, 1.0, a);
  float ang = atan(v.y, v.x);
  float r = length(v);
  float wob = texture(uTex, fract(vec2(ang * 0.6 + uSeed, uSeed * 0.3))).g;
  // Mancha central con borde irregular.
  float rm = Rpx * 0.26 * (0.75 + 0.6 * wob) * shrinkM;
  float sdf = r - rm;
  // Regueros: lenguas que salen disparadas y se afinan.
  for (int i = 0; i < 7; i++) {
    float fi = float(i);
    float aa = 6.2832 * hash(fi + uSeed * 9.0);
    float ln = Rpx * (0.3 + 0.45 * hash(fi + 3.0 + uSeed)) * shoot * shrinkD;
    vec2 dir = vec2(cos(aa), sin(aa));
    float t = clamp(dot(v, dir) / max(ln, 1.0), 0.0, 1.0);
    float wdt = mix(rm * 0.45, 1.5, t);
    float dd = length(v - dir * t * ln) - wdt;
    sdf = min(sdf, dd);
  }
  // Gotas sueltas alrededor.
  for (int i = 0; i < 18; i++) {
    float fi = float(i);
    float aa = 6.2832 * hash(fi * 1.7 + uSeed * 5.0);
    float rr = Rpx * (0.25 + 0.65 * hash(fi * 2.3 + uSeed)) * shoot;
    float sz = (2.0 + 6.0 * hash(fi * 3.1 + uSeed)) * shrinkD;
    sdf = min(sdf, length(v - vec2(cos(aa), sin(aa)) * rr) - sz);
  }
  // Brillo de la pintura: más intensa donde es gruesa, con textura, y un
  // halo que se derrama fuera.
  float inside = smoothstep(1.2, -1.2, sdf);
  float thick = clamp(-sdf / 14.0, 0.0, 1.0);
  float grain = texture(uTex, fract(v / 160.0 + uSeed)).r;
  float L = (inside * (0.55 + 0.35 * thick + 0.2 * (grain - 0.5)) + 0.35 * exp(-max(sdf, 0.0) / 7.0) * (1.0 - inside)) * uAmp;
  L *= 1.0 - smoothstep(0.9, 1.0, a);
  // Color fluorescente por el brillo final.
  vec3 dim = uHue < 0.5 ? vec3(0.15, 1.0, 0.08) : (uHue < 1.5 ? vec3(1.0, 0.3, 0.0) : vec3(0.42, 0.16, 1.0));
  vec3 bright = uHue < 0.5 ? mix(uGreen / max(uGreen.g, 0.01), vec3(0.7, 1.0, 0.6), 0.4)
              : (uHue < 1.5 ? mix(uOrange / max(uOrange.r, 0.01), vec3(1.0, 0.7, 0.35), 0.4)
              : mix(uViolet / max(uViolet.b, 0.01), vec3(0.78, 0.68, 1.0), 0.5));
  vec3 col = mix(dim, bright, smoothstep(0.7, 0.95, L));
  vec3 tone = min(col * min(L, 1.0), vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
