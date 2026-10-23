// Reactiva · Fisura Dimensional — transparencia momentánea. Con el golpe se rasga el aire de
// la escena: una grieta alargada se abre como un ojo, con los bordes dentados
// de luz blanca que tiemblan sin parar, dentro una energía violeta que corre a
// lo largo de la herida y fuera rayos que escapan perpendiculares a los
// bordes; unas motas de luz son absorbidas hacia ella. Al final la fisura se
// cierra encogiéndose hasta desaparecer. Violeta eléctrico con el filo
// blanco. Cada golpe se abre en otro sitio y con otra inclinación. Sólo suma
// luz. Referente: las fisuras dimensionales de los efectos visuales de cine.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: tamaño de la fisura.
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.4, value: 1),
  // MOVIMIENTO: cuánto dura abierta.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.5, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Gran Desgarro', {'tamano': 1.35, 'caida': 1.3}),
  CreatorVariation('Parpadeo', {'tamano': .7, 'caida': .55}),
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
    const float T = g.caida * 1.1f * 1.0f / pace(f);
    const Color deep = f.colors[1], lilac = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2246822519u + 47u;
      const Vec2 o = {W * (0.3f + 0.4f * rnd(s + 1u)), H * (0.3f + 0.4f * rnd(s + 2u))};
      const float ang = 0.5f * float(pi) + (rnd(s + 3u) - 0.5f) * 0.9f;
      const Vec2 ax = {std::cos(ang), std::sin(ang)};
      const float halfLen = (1.0f < 0.5f ? 90.0f : 140.0f) * sz * g.tamano;
      // Ya abierta al 60 % en el golpe; se abre del todo y al final se cierra
      // encogiéndose.
      const float open = (0.6f + 0.4f * easeOut(clamp01(a * pace(f) / 0.1f))) * (1.0f - easeInOut((q - 0.5f) / 0.5f));
      if (open < 0.02f) continue;
      const float wm = 34.0f * sz * g.tamano;
      const float m = (wm + 80.0f) * px1, ext = (halfLen + 60.0f) * px1;
      const float x0 = std::max(0.0f, o.x - std::fabs(ax.x) * ext - m), x1 = std::min(W, o.x + std::fabs(ax.x) * ext + m);
      const float y0 = std::max(0.0f, o.y - std::fabs(ax.y) * ext - m), y1 = std::min(H, o.y + std::fabs(ax.y) * ext + m);
      c.material("rift", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, o.x, o.y, ax.x, ax.y, px1, halfLen, wm * open, open, float(now), rnd(s + 5u), lv,
                  deep.r, deep.g, deep.b, lilac.r, lilac.g, lilac.b, white.r, white.g, white.b});
      // Motas de luz absorbidas hacia la fisura.
      const float pull = easeInOut(clamp01(0.15f + q * 1.1f));
      for (int i = 0; i < 16; i++) {
        const float u = (rnd(s + 100u + uint32_t(i)) * 2.0f - 1.0f) * halfLen * 0.9f * px1 * (0.55f + 0.45f * open);
        const float v = (rnd(s + 200u + uint32_t(i)) < 0.5f ? -1.0f : 1.0f) * (40.0f + 70.0f * rnd(s + 300u + uint32_t(i))) * px1 * sz * (1.0f - pull);
        const Vec2 mp = {o.x + ax.x * u - ax.y * v, o.y + ax.y * u + ax.x * v};
        glow(c, mp, 8.0f * px1 * sz, tint(white, 1.0f), lilac, 0.75f * lv * (1.0f - pull));
      }
    }
  }
};
''';

const shaderSources = <String, String>{
  'rift': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform vec2 uCenter;
uniform vec2 uAxis;
uniform float uPx;
uniform float uHalfLen;
uniform float uWidth;
uniform float uOpen;
uniform float uTime;
uniform float uSeed;
uniform float uAmp;
uniform vec3 uDeep;
uniform vec3 uMid;
uniform vec3 uWhite;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
float vnoise(float x) {
  float i = floor(x);
  float f = fract(x);
  return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}
float vnoise2(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void main() {
  vec2 lp = FlutterFragCoord().xy;
  float inside = step(lp.x, uSize.x + 1.0) * step(lp.y, uSize.y + 1.0);
  vec2 d = (lp + uOffset - uCenter) / uPx;
  float u = dot(d, uAxis);
  float v = dot(d, vec2(-uAxis.y, uAxis.x));
  // Forma de ojo que también se acorta al cerrarse.
  float hl = uHalfLen * (0.55 + 0.45 * uOpen);
  float s = u / max(hl, 1.0);
  float prof = uWidth * pow(max(1.0 - s * s, 0.0), 0.7);
  float t = uTime;
  // Bordes dentados que tiemblan.
  float j1 = (vnoise(s * 11.0 + uSeed * 20.0 + t * 2.0) - 0.5) * 7.0 + (vnoise(s * 37.0 + uSeed * 9.0 + t * 7.0) - 0.5) * 3.0;
  float j2 = (vnoise(s * 11.0 + uSeed * 31.0 - t * 2.0) - 0.5) * 7.0 + (vnoise(s * 37.0 + uSeed * 5.0 - t * 7.0) - 0.5) * 3.0;
  float jag = smoothstep(1.05, 0.8, abs(s)) * min(prof / 6.0 + 0.3, 1.0);
  float eL = -prof + j1 * jag;
  float eR = prof + j2 * jag;
  float de = min(abs(v - eL), abs(v - eR));
  float tip = step(abs(s), 1.02);
  float inn = step(eL, v) * step(v, eR) * step(abs(s), 1.0);
  // Filo blanco y fino.
  float edge = exp(-de * de / 1.6) * tip;
  // Dentro, energía que corre a lo largo de la fisura, más viva junto a los
  // bordes (nunca una mancha plana).
  float fil = pow(0.5 + 0.5 * sin(v / max(prof, 1.0) * 5.0 + vnoise(s * 6.0 - t * 5.0 + uSeed * 4.0) * 8.0), 6.0);
  float interior = inn * (0.22 + 0.42 * fil) * (0.5 + 0.5 * exp(-de / (0.4 * prof + 1.0)));
  // Fuera, rayos perpendiculares a los bordes y un resplandor corto.
  float rays = pow(0.5 + 0.5 * sin(s * 46.0 + vnoise(s * 5.0 + t) * 6.0), 4.0);
  float outer = (1.0 - inn) * (0.55 * exp(-de / 10.0) + 0.4 * rays * exp(-de / 45.0)) * smoothstep(1.3, 0.9, abs(s));
  float L = (edge * 1.05 + interior + outer) * uAmp * inside;
  vec3 dim = mix(vec3(0.36, 0.06, 1.0), uDeep / max(max(uDeep.r, max(uDeep.g, uDeep.b)), 0.01), 0.15);
  vec3 mid = mix(vec3(0.62, 0.42, 1.0), uMid / max(max(uMid.r, max(uMid.g, uMid.b)), 0.01), 0.15);
  vec3 col = mix(dim, mid, smoothstep(0.4, 0.7, L));
  col = mix(col, mix(uWhite, vec3(1.0), 0.5), smoothstep(0.95, 1.1, L));
  vec3 tone = min(col * min(L, 1.0), vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
