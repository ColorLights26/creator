// Reactiva · Ikebana Sonora — transparencia momentánea. Con el golpe, como si el sonido
// lanzara pintura desde un altavoz al pie de la escena, salen disparadas
// lenguas de pintura de luz roja, amarilla y violeta que suben en arco a
// cámara lenta, se ensanchan hacia la punta, se rizan y terminan en una gota
// gruesa, con un brillo húmedo a un lado que las hace parecer líquidas. Al
// caer, las lenguas se adelgazan y se recogen desde la base. Cada golpe
// lanza otro ramo. Sólo suma luz. Referente: «Sound of Ikebana» de Naoko
// Tosa, pintura lanzada por el sonido a alta velocidad.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: cuántas lenguas de pintura.
  CreatorModifier.slider('lenguas', 'Lenguas', min: .4, max: 1, value: .8),
  // MOVIMIENTO: cuánto dura.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.6, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Gran Ramo', {'lenguas': 1, 'caida': 1.4}),
  CreatorVariation('Salpicón', {'lenguas': .45, 'caida': .55}),
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
    const Color red = f.colors[1], yellow = f.colors[2], violet = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2246822519u + 107u;
      const Vec2 b = {W * (0.3f + 0.4f * rnd(s + 1u)), H + 6.0f * px1};
      const float size = 1.0f < 0.5f ? 0.55f + 0.45f * sz : 1.0f;
      // Vuelo normalizado: ya a media subida en el golpe.
      const float prog = std::min(1.0f, 0.45f + 0.55f * q * 1.25f);
      const float fade = easeInOut((q - 0.6f) / 0.4f);
      const float hmax = 330.0f * size;
      const float m = (hmax * 0.9f + 50.0f) * px1;
      const float x0 = std::max(0.0f, b.x - m), x1 = std::min(W, b.x + m);
      const float y0 = std::max(0.0f, b.y - (hmax + 60.0f) * px1), y1 = H;
      c.material("splash", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, b.x, b.y, px1, prog, fade, hmax, size, g.lenguas, rnd(s + 2u), lv,
                  red.r, red.g, red.b, yellow.r, yellow.g, yellow.b, violet.r, violet.g, violet.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'splash': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform vec2 uBase;
uniform float uPx;
uniform float uProg;
uniform float uFade;
uniform float uHeight;
uniform float uScale;
uniform float uCount;
uniform float uSeed;
uniform float uAmp;
uniform vec3 uRed;
uniform vec3 uYellow;
uniform vec3 uViolet;
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
// Tres octavas giradas: sin contornos que sigan la rejilla del ruido.
float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    s += a * vnoise2(p);
    p = mat2(0.8, 0.6, -0.6, 0.8) * p * 2.03 + vec2(1.7, 9.2);
    a *= 0.5;
  }
  return s / 0.875;
}

// Punto de la lengua i en el instante normalizado s: sube en arco y se riza.
vec2 path(float fi, float s) {
  float ang = mix(-1.05, 1.05, fract(fi * 0.618 + uSeed)) + (hash(fi * 3.7 + uSeed * 17.0) - 0.5) * 0.3;
  float hk = uHeight * (0.32 + 0.68 * hash(fi * 5.3 + uSeed * 7.0));
  float curl = (hash(fi * 7.9 + uSeed * 3.0) - 0.5) * 70.0 * uScale;
  float x = sin(ang) * hk * 0.95 * s + curl * s * s * s;
  float y = -hk * (2.0 * s - s * s) * cos(ang * 0.6);
  return vec2(x, y);
}

void main() {
  vec2 lp = FlutterFragCoord().xy;
  float inside = step(lp.x, uSize.x + 1.0) * step(lp.y, uSize.y + 1.0);
  vec2 d = (lp + uOffset - uBase) / uPx;
  float Lr = 0.0;
  float Ly = 0.0;
  float Lv = 0.0;
  float n = 3.0 + 5.0 * uCount;
  // Al caer, la lengua se recoge desde la base y adelgaza.
  float s0 = 0.75 * uFade * uProg;
  for (int i = 0; i < 8; i++) {
    float fi = float(i);
    if (fi >= n) break;
    float wi = (6.0 + 12.0 * hash(fi * 2.1 + uSeed * 11.0)) * uScale * (1.0 - 0.55 * uFade);
    // Distancia a la línea central (14 tramos) con su posición a lo largo.
    float best = 1e9;
    float side = 0.0;
    float along = 0.0;
    vec2 prev = path(fi, s0);
    for (int k = 1; k <= 14; k++) {
      float sk = mix(s0, uProg, float(k) / 14.0);
      vec2 cur = path(fi, sk);
      vec2 ab = cur - prev;
      float tt = clamp(dot(d - prev, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
      vec2 dv = d - prev - ab * tt;
      float dd = length(dv);
      if (dd < best) {
        best = dd;
        side = (ab.x * dv.y - ab.y * dv.x) / max(length(ab), 1e-4);
        along = (float(k - 1) + tt) / 14.0;
      }
      prev = cur;
    }
    // Más gruesa hacia la punta y una gota al final.
    float w = wi * (0.35 + 0.65 * pow(along, 0.6));
    float tipD = length(d - path(fi, uProg)) - wi * 0.85;
    float sd = min(best - w, tipD);
    float body = smoothstep(3.0, -5.0, sd);
    float rel = clamp(side / max(w, 1.0), -1.0, 1.0);
    // Brillo húmedo a un lado (reflejo alargado) sobre el cuerpo.
    float shade = 0.52 + 0.18 * (1.0 - rel * rel) + 0.2 * exp(-(rel - 0.4) * (rel - 0.4) / 0.04);
    float grain = 0.9 + 0.2 * vnoise2(d / 9.0 + fi * 3.0 + uSeed);
    float li = body * shade * grain;
    float ci = mod(fi, 3.0);
    if (ci < 0.5) {
      Lr = max(Lr, li);
    } else if (ci < 1.5) {
      Ly = max(Ly, li);
    } else {
      Lv = max(Lv, li);
    }
  }
  Lr *= uAmp * inside;
  Ly *= uAmp * inside;
  Lv *= uAmp * inside;
  // Color por el brillo final; donde se cruzan manda la más fuerte.
  vec3 cR = mix(vec3(1.0, 0.08, 0.06), uRed / max(uRed.r, 0.01), 0.15);
  vec3 cY = mix(vec3(1.0, 0.27, 0.03), mix(vec3(1.0, 0.78, 0.08), uYellow / max(uYellow.r, 0.01), 0.15), smoothstep(0.64, 0.78, Ly));
  vec3 cV = mix(vec3(0.45, 0.1, 1.0), uViolet / max(uViolet.b, 0.01), 0.15);
  // Cruce de colores suave (más de 6 px) donde dos lenguas se tocan.
  float wr = Lr * Lr;
  float wy = Ly * Ly;
  float wv = Lv * Lv;
  vec3 hue = (cR * wr + cY * wy + cV * wv) / max(wr + wy + wv, 1e-6);
  hue -= 0.8 * min(hue.r, min(hue.g, hue.b));
  hue /= max(max(hue.r, max(hue.g, hue.b)), 1e-4);
  float L = max(Lr, max(Ly, Lv));
  L = L < 0.85 ? L : 0.85 + 0.15 * (1.0 - exp(-(L - 0.85) / 0.15));
  hue = mix(hue, vec3(1.0, 0.96, 0.92), smoothstep(0.93, 0.99, L));
  vec3 tone = min(hue * L, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
