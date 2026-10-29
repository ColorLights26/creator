// Reactiva Mejorada · Bioluminiscencia — transparencia momentánea. Con el golpe una ola cruza la
// escena y a su paso se enciende el plancton: una cresta de espuma de luz azul,
// rota en tramos y con salpicaduras por delante, y detrás miles de puntos
// redondos que destellan al pasar la cresta y se apagan en unos cuadros; sólo
// unos pocos siguen titilando. Blanco azulado en lo más fuerte y azul eléctrico
// en lo tenue. Cada golpe cruza en otra dirección. Sólo suma luz. Referente: las
// olas bioluminiscentes de Monterey Bay.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo', 'Bombo y caja', 'Cada pulso']),
  // FORMA: cuántos puntos de plancton.
  CreatorModifier.slider('plancton', 'Cantidad de plancton', min: .3, max: 1, value: .75),
  // MOVIMIENTO: cuánto tarda la ola en cruzar.
  CreatorModifier.slider('caida', 'Duración', min: .5, max: 1.4, value: .9),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Marea Viva', {'plancton': 1, 'caida': 1.3}),
  CreatorVariation('Chispas de Agua', {'plancton': .4, 'caida': .55}),
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
    // Cruza en 0,6-0,8 s (la Mejorada en 0,3 s o más) y el plancton se apaga
    // en 12-20 cuadros detrás de la cresta.
    const float cross = g.caida * (0.45f < 0.5f ? 0.38f : 0.8f);
    const float T = cross + 0.15f;
    const Color deep = f.colors[1], blue = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const float ang = 6.2832f * rnd(p.id * 3u + 7u);
      c.material("plankton", {0.0f, 0.0f, W, H},
                 {std::cos(ang), std::sin(ang), a, cross, sz, lv, g.plancton, rnd(p.id * 5u + 1u),
                  deep.r, deep.g, deep.b, blue.r, blue.g, blue.b, white.r, white.g, white.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'plankton': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uDir;
uniform float uAge;
uniform float uCross;
uniform float uScale;
uniform float uAmp;
uniform float uDensity;
uniform float uSeed;
uniform vec3 uDeep;
uniform vec3 uBlue;
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

// Desplazamiento del frente: dos olas largas que no se repiten juntas (170 y
// 290 px, de 22 y 20 px): pendiente menor que 2 y curvas de 25 px o más.
float bend(float perp) {
  return 22.0 * sin(perp / 27.06 + uSeed * 4.0) + 20.0 * sin(perp / 46.15 + uSeed * 6.0);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  vec2 q = p / px1;
  vec2 sz = uSize / px1;
  vec2 c = 0.5 * sz;
  vec2 nrm = vec2(-uDir.y, uDir.x);
  float span = 0.5 * (abs(sz.x * uDir.x) + abs(sz.y * uDir.y)) + 40.0;
  float perp = dot(q - c, nrm);
  float s = dot(q - c, uDir) + bend(perp);
  // El frente ya va un cuarto dentro en el golpe.
  float front = -span + 2.0 * span * (0.25 + 0.75 * clamp(uAge / uCross, 0.0, 1.0));
  float speed = 1.5 * span / max(uCross, 0.001);
  float b = front - s;
  float running = 1.0 - smoothstep(uCross, uCross + 0.05, uAge);
  // Cresta de espuma: borde delantero quemado en 3 px, blanco que pasa a azul
  // en 6 px, 8-12 px azul intenso detrás y una estela que se apaga en 40-60
  // px; el ancho de la banda (6-20 px) y la espuma (celdas de 6-14 px) cambian
  // a lo largo del frente.
  float n = 0.6 * vnoise2(q / 11.0 + vec2(uSeed * 9.0, uAge * 6.0)) + 0.4 * vnoise2(q / 6.5 + vec2(3.1, uSeed * 5.0 - uAge * 9.0));
  float foam = smoothstep(0.32, 0.56, n);
  float wband = 18.0 * (0.5 + 0.7 * vnoise(perp / 22.0 + uSeed * 3.0));
  // El borde delantero sube en unos 8 px sin saltos; el blanco ocupa como
  // mucho 3 px; detrás, una estela de +30 a 40-60 px.
  float prof = b < 0.0 ? 0.66 * exp(-(b / 12.0) * (b / 12.0)) : 0.15 * exp(-(b / 10.0) * (b / 10.0)) + 0.51 * exp(-b / wband);
  float wake = b < 0.0 ? 0.28 * exp(-(b / 12.0) * (b / 12.0)) : 0.28 * exp(-b / 45.0);
  float L = (prof * (0.3 + 0.7 * foam) + wake) * running;
  // Plancton: puntos redondos repartidos sin orden que destellan al pasar la
  // cresta y se apagan en 8-15 cuadros; salpicaduras por delante.
  float cs = 9.0;
  vec2 cell0 = floor(q / cs);
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 cell = cell0 + vec2(float(i), float(j));
      if (hash2(cell + uSeed) > uDensity) continue;
      vec2 pc = (cell + vec2(hash2(cell + 1.3), hash2(cell + 4.7))) * cs;
      float pp = dot(pc - c, nrm);
      float bh = front - (dot(pc - c, uDir) + bend(pp));
      float r2 = dot(q - pc, q - pc);
      float lv = 0.0;
      if (bh > 0.0) {
        lv = exp(-(bh / speed + max(uAge - uCross, 0.0)) / 0.1);
      } else if (bh > -24.0 && hash2(cell + 3.3) < 0.3) {
        lv = 0.7 * smoothstep(-24.0, -6.0, bh) * running;
      }
      float big = hash2(cell + 5.5) < 0.15 ? 1.0 : 0.6;
      L += lv * big * (exp(-r2 / (8.0 * uScale)) * 0.6 + 0.22 * exp(-r2 / (20.0 * uScale)));
    }
  }
  L *= uAmp;
  // Rodilla suave: sólo el borde delantero se quema.
  L = L < 0.85 ? L : 0.85 + 0.15 * (1.0 - exp(-(L - 0.85) / 0.15));
  vec3 deep = mix(vec3(0.12, 0.28, 1.0), uDeep / max(uDeep.b, 0.01), 0.2);
  vec3 mid = mix(vec3(0.28, 0.56, 1.0), uBlue / max(uBlue.b, 0.01), 0.2);
  vec3 col = mix(deep, mid, smoothstep(0.4, 0.7, L));
  col = mix(col, mix(uWhite, vec3(0.9, 0.95, 1.0), 0.5), smoothstep(0.66, 0.97, L) * smoothstep(0.35, 0.65, prof));
  vec3 tone = min(col * L, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
