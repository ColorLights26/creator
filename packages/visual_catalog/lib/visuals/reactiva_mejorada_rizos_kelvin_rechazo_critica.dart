// Reactiva Mejorada · Rizos de Kelvin — transparencia momentánea. Con el golpe se enciende a lo
// ancho de la escena la frontera entre dos corrientes de luz, turquesa por
// arriba y rosa intenso por abajo, que se deslizan una sobre otra y se
// enrollan en una fila de rizos de tamaños muy distintos, como las olas de
// Kelvin-Helmholtz: cada rizo es una espiral en la que se alternan los dos
// colores y la frontera brilla donde se tocan. Los rizos crecen, avanzan y
// se rompen en remolinos más pequeños hasta deshacerse. Cada golpe cruza
// con otra inclinación y otros rizos. Sólo suma luz. Referente: la
// inestabilidad de Kelvin-Helmholtz en nubes y en tanques de laboratorio.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo', 'Bombo y caja', 'Cada pulso']),
  // FORMA: tamaño de los rizos.
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.4, value: 1),
  // MOVIMIENTO: cuánto dura.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.6, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Olas Grandes', {'tamano': 1.35, 'caida': 1.4}),
  CreatorVariation('Rizo Rápido', {'tamano': .7, 'caida': .55}),
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
    const Color teal = f.colors[1], pink = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2654435761u + 97u;
      const Vec2 o = {W * (0.35f + 0.3f * rnd(s + 1u)), H * (0.3f + 0.4f * rnd(s + 2u))};
      const float tilt = (rnd(s + 3u) - 0.5f) * 0.7f;
      const Vec2 dir = {std::cos(tilt), std::sin(tilt)};
      const float size = g.tamano * (0.45f < 0.5f ? sz : 1.0f);
      // Los rizos ya empiezan a enrollarse en el golpe; al final se rompen y
      // la luz se recoge hacia la frontera.
      const float age = a * pace(f);
      const float grow = 0.4f + 0.6f * easeOut(clamp01(age / (0.5f * 0.45f)));
      const float fade = easeInOut((q - 0.5f) / 0.5f);
      const float half = (75.0f * size + 40.0f) * px1;
      const float ext = std::hypot(W, H) * 0.6f;
      const Vec2 e0 = {o.x - dir.x * ext, o.y - dir.y * ext}, e1 = {o.x + dir.x * ext, o.y + dir.y * ext};
      const float x0 = std::max(0.0f, std::min(e0.x, e1.x) - half), x1 = std::min(W, std::max(e0.x, e1.x) + half);
      const float y0 = std::max(0.0f, std::min(e0.y, e1.y) - half), y1 = std::min(H, std::max(e0.y, e1.y) + half);
      if (x1 - x0 < 1.0f || y1 - y0 < 1.0f) continue;
      c.material("billow", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, o.x, o.y, dir.x, dir.y, px1, age, grow, fade, size, rnd(s + 4u), lv,
                  teal.r, teal.g, teal.b, pink.r, pink.g, pink.b, white.r, white.g, white.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'billow': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform vec2 uOrigin;
uniform vec2 uDir;
uniform float uPx;
uniform float uAge;
uniform float uGrow;
uniform float uFade;
uniform float uScale;
uniform float uSeed;
uniform float uAmp;
uniform vec3 uTeal;
uniform vec3 uPink;
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

// Enrolla la frontera (y = 0) alrededor de una fila de rizos de tamaños muy
// distintos y separación sin ritmo que avanzan con la corriente; al romperse
// aparecen remolinos pequeños.
float roll(vec2 q) {
  float x = -240.0 * uScale;
  for (int k = 0; k < 9; k++) {
    float fk = float(k);
    x += (48.0 + 62.0 * hash(fk * 3.3 + uSeed * 17.0)) * uScale;
    float xk = x + uAge * 70.0 * uScale;
    float rc = (11.0 + 27.0 * hash(fk * 7.1 + uSeed * 5.0)) * uScale;
    vec2 vk = vec2(xk, 0.0);
    vec2 dv = q - vk;
    float an = -(2.4 + 2.0 * hash(fk * 1.9 + uSeed * 9.0)) * uGrow * exp(-dot(dv, dv) / (rc * rc));
    q = vk + rot(dv, an);
  }
  q += (vec2(fbm(q / 26.0 + vec2(uSeed * 7.0, uAge * 0.8)), fbm(q / 26.0 + vec2(3.1, uSeed * 3.0 - uAge * 0.6))) - 0.5) * 22.0 * uFade * uScale;
  return q.y;
}

void main() {
  vec2 lp = FlutterFragCoord().xy;
  float inside = step(lp.x, uSize.x + 1.0) * step(lp.y, uSize.y + 1.0);
  vec2 d = (lp + uOffset - uOrigin) / uPx;
  vec2 q = vec2(dot(d, uDir), dot(d, vec2(-uDir.y, uDir.x)));
  if (abs(q.y) > 110.0 * uScale + 30.0) {
    fragColor = vec4(0.0);
    return;
  }
  // Distancia a la frontera en píxeles (diferencias centrales de 2 px): la
  // línea mide 3 px o más aunque el rizo la apriete, y donde se apila más
  // fina que eso se funde en un velo.
  float A = roll(q);
  float g = max(0.25 * length(vec2(roll(q + vec2(2.0, 0.0)) - roll(q - vec2(2.0, 0.0)), roll(q + vec2(0.0, 2.0)) - roll(q - vec2(0.0, 2.0)))), 0.3);
  float dist = A / g;
  float ww = mix(4.4, 3.0, uFade);
  float fold = smoothstep(2.5, 5.0, g);
  float line = mix(0.48 * exp(-dist * dist / (ww * ww)) + 0.16 * exp(-dist * dist / (7.0 * ww * ww)), 0.3, fold);
  // Cada corriente brilla junto a la frontera y se apaga hacia fuera; al
  // final la luz se recoge hacia la frontera.
  float reach = mix(36.0, 10.0, uFade) * uScale;
  float tealF = 0.4 * exp(-max(A, 0.0) / reach) * smoothstep(-3.0, 3.0, A);
  float pinkF = 0.4 * exp(min(A, 0.0) / reach) * smoothstep(3.0, -3.0, A);
  float grain = 0.86 + 0.28 * fbm(q / 10.0 + vec2(uAge * 1.5, uSeed * 4.0));
  float k = uAmp * inside * (1.0 - 0.35 * uFade);
  float Lt = (tealF * grain + line * smoothstep(-6.0, 6.0, dist)) * k;
  float Lp = (pinkF * grain + line * smoothstep(6.0, -6.0, dist)) * k;
  // Color por el brillo final; donde se tocan manda el más fuerte y la mezcla
  // se resatura (la frontera queda violeta).
  vec3 cT = mix(vec3(0.0, 0.75, 0.68), uTeal / max(uTeal.g, 0.01), 0.15);
  vec3 cP = mix(vec3(1.0, 0.06, 0.5), uPink / max(uPink.r, 0.01), 0.15);
  float wt = Lt * Lt * Lt * Lt;
  float wp = Lp * Lp * Lp * Lp;
  vec3 hue = (cT * wt + cP * wp) / max(wt + wp, 1e-6);
  hue -= 0.8 * min(hue.r, min(hue.g, hue.b));
  hue /= max(max(hue.r, max(hue.g, hue.b)), 1e-4);
  float L = Lt + Lp;
  L = L < 0.85 ? L : 0.85 + 0.15 * (1.0 - exp(-(L - 0.85) / 0.15));
  hue = mix(hue, mix(uWhite, vec3(1.0), 0.5), smoothstep(0.93, 0.99, L));
  vec3 tone = min(hue * L, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
