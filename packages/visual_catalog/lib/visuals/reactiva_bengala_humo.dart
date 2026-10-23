// Reactiva · Bengala de Humo — transparencia momentánea. Con el golpe revienta desde un
// lado una bengala de humo de color: una columna espesa de humo verde
// esmeralda encendido que sale a borbotones, se hincha en volutas que ruedan y se
// abren al avanzar, más brillante cerca de la boca y deshilachándose en los
// bordes. Al cortarse, el humo se despega del borde y se aclara hasta
// desaparecer. Verde esmeralda profundo en lo tenue, verde intenso en el
// cuerpo y verde lima en lo más denso. Cada golpe sale de otro sitio y en otra dirección. Sólo suma luz.
// Referente: las bengalas de humo de colores a cámara lenta.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: largo de la columna de humo.
  CreatorModifier.slider('largo', 'Largo', min: .5, max: 1.2, value: .9),
  // MOVIMIENTO: cuánto dura.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.6, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Humareda', {'largo': 1.2, 'caida': 1.5}),
  CreatorVariation('Bocanada', {'largo': .55, 'caida': .55}),
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
    const float T = g.caida * 1.3f * 1.0f / pace(f);
    const Color deep = f.colors[1], mid = f.colors[2], hot = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2246822519u + 61u;
      // Sale de un lado (izquierda o derecha) hacia dentro, algo hacia arriba.
      const int side = 1 + int(rnd(s + 1u) * 1.999f);
      const float jit = (rnd(s + 2u) - 0.5f) * 0.7f;
      Vec2 o;
      float ang;
      if (side == 0) { o = {W * (0.2f + 0.6f * rnd(s + 3u)), H + 4.0f * px1}; ang = -0.5f * float(pi) + jit; }
      else if (side == 1) { o = {-4.0f * px1, H * (0.4f + 0.45f * rnd(s + 3u))}; ang = jit * 0.8f - 0.25f; }
      else { o = {W + 4.0f * px1, H * (0.4f + 0.45f * rnd(s + 3u))}; ang = float(pi) - jit * 0.8f + 0.25f; }
      // La columna se mece un poco mientras sale (nunca queda congelada).
      const float sway = (rnd(s + 5u) < 0.5f ? -1.0f : 1.0f) * 0.3f * clamp01(a * pace(f) / (0.6f * 1.0f));
      const Vec2 dir = {std::cos(ang + sway), std::sin(ang + sway)};
      // La columna ya va por la mitad en el golpe; al cortarse se despega.
      const float full = (1.0f < 0.5f ? 260.0f * sz : 420.0f) * g.largo;
      // Ya al 80 % en el golpe; crece poco después.
      const float len = full * (0.8f + 0.2f * easeOut(clamp01(a * pace(f) / (0.35f * 1.0f))));
      // Se recoge poco a poco: como mucho un 40 % menos cada dos cuadros.
      const float cut = full * 0.9f * clamp01((q - 0.35f) / 0.65f);
      const float thr = 0.25f * clamp01((q - 0.3f) / 0.7f);
      const float flash = std::exp(-a * pace(f) / (0.1f * 1.0f));
      // Los últimos cuadros se apagan del todo poco a poco.
      const float tail = 1.0f - easeInOut((q - 0.75f) / 0.25f);
      // Sólo la zona del humo, con margen para las volutas.
      const float half = (16.0f + 0.42f * len + 70.0f) * px1;
      const Vec2 e = {o.x + dir.x * (len + 80.0f) * px1, o.y + dir.y * (len + 80.0f) * px1};
      const float x0 = std::max(0.0f, std::min(o.x, e.x) - half), x1 = std::min(W, std::max(o.x, e.x) + half);
      const float y0 = std::max(0.0f, std::min(o.y, e.y) - half), y1 = std::min(H, std::max(o.y, e.y) + half);
      if (x1 - x0 < 1.0f || y1 - y0 < 1.0f) continue;
      c.material("smoke", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, o.x, o.y, dir.x, dir.y, px1, len, cut, thr, flash, float(now), rnd(s + 4u), lv * tail,
                  deep.r, deep.g, deep.b, mid.r, mid.g, mid.b, hot.r, hot.g, hot.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'smoke': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform vec2 uOrigin;
uniform vec2 uDir;
uniform float uPx;
uniform float uLen;
uniform float uCut;
uniform float uThr;
uniform float uFlash;
uniform float uTime;
uniform float uSeed;
uniform float uAmp;
uniform vec3 uDeep;
uniform vec3 uMid;
uniform vec3 uHot;
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
  vec2 d = (lp + uOffset - uOrigin) / uPx;
  float u = dot(d, uDir);
  float v = dot(d, vec2(-uDir.y, uDir.x));
  if (u < uCut - 50.0 || u > uLen + 90.0) {
    fragColor = vec4(0.0);
    return;
  }
  // Volutas que ruedan hacia fuera y se abren al avanzar.
  float w = 16.0 + 0.42 * max(u, 0.0);
  vec2 bq = vec2(u / 42.0 - uTime * 4.0, v / 42.0);
  vec2 warp = vec2(fbm(bq * 0.7 + vec2(uSeed * 5.0, uTime * 1.3)), fbm(bq * 0.7 + vec2(3.3, uSeed * 2.0 - uTime * 1.1))) - 0.5;
  float nb = fbm(bq + warp * 1.4 + uSeed * 9.0);
  // Bordes que ondulan 30 px o más a lo largo de la columna (nunca rectos).
  float vv = v + (nb - 0.5) * w * 1.2 + 34.0 * (fbm(vec2(u / 70.0 - uTime * 0.6, uSeed * 3.0)) - 0.5) * smoothstep(0.0, 80.0, u);
  float env = exp(-(vv / w) * (vv / w) * 1.6) * smoothstep(uLen + 70.0, uLen - 40.0, u + (nb - 0.5) * 90.0)
            * smoothstep(uCut - 30.0, uCut + 40.0, u + (nb - 0.5) * 60.0) * smoothstep(-24.0, 10.0, u);
  // Volutas grandes (40-90 px) que marcan el borde de abajo y el de arriba.
  float big = smoothstep(0.25, 0.8, fbm(bq * 0.55 + warp * 1.4 + vec2(uSeed * 3.0, 4.2 + uTime * 0.9)));
  float envB = exp(-(vv / (w * 1.25)) * (vv / (w * 1.25)) * 1.6) * smoothstep(uLen + 70.0, uLen - 40.0, u + (nb - 0.5) * 90.0)
             * smoothstep(uCut - 30.0, uCut + 40.0, u + (nb - 0.5) * 60.0) * smoothstep(-24.0, 10.0, u);
  float dens = clamp(envB * (0.12 + 0.6 * big + 0.45 * nb) - uThr, 0.0, 1.0);
  // El humo denso queda en 0,6-0,8 con su textura; sólo la boca (8 px) se
  // acerca al blanco, con un fogonazo pequeño al reventar.
  float lit = 0.72 + 0.18 * exp(-max(u, 0.0) / 60.0);
  // Grano fino (8 px) para que ningún tramo quede plano.
  float grain = 0.86 + 0.16 * vnoise2(vec2(u, v) / 8.0 + vec2(uTime * 0.5, uSeed * 7.0)) + 0.12 * vnoise2(vec2(u, v) / 4.5 + vec2(uSeed * 3.0, uTime));
  grain *= 0.66 + 0.68 * fbm(vec2(u, v) / 12.0 + vec2(uTime * 2.0, uSeed * 4.0));
  float L = (dens * lit * 1.2 * grain + uFlash * 0.55 * exp(-dot(d, d) / 110.0)) * uAmp * inside;
  L = L < 0.85 ? L : 0.85 + 0.15 * (1.0 - exp(-(L - 0.85) / 0.15));
  vec3 dim = mix(vec3(0.02, 0.6, 0.16), uDeep / max(uDeep.g, 0.01), 0.15);
  vec3 mid = mix(vec3(0.1, 1.0, 0.3), uMid / max(uMid.g, 0.01), 0.15);
  vec3 hot = mix(vec3(0.34, 1.0, 0.2), uHot / max(uHot.g, 0.01), 0.1);
  vec3 col = mix(dim, mid, smoothstep(0.35, 0.6, L));
  col = mix(col, hot, smoothstep(0.7, 0.85, L));
  col = mix(col, vec3(0.92, 1.0, 0.9), smoothstep(0.93, 0.99, L));
  vec3 tone = min(col * L, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
