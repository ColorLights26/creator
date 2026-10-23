// Reactiva Mejorada · Escisión — transparencia momentánea. Con el golpe aparece una lámina de luz
// amarilla que en seguida se parte a lo largo en dos capas, una bermellón y
// otra lima: se despegan despacio por caminos curvos opuestos, cada una con
// su propia forma, sus bordes irregulares y su densidad viva, y el amarillo
// de donde todavía se tapan se encoge hasta desaparecer mientras cada capa
// se adelgaza desde su borde lejano. Luz que se suma de verdad: rojo y verde
// dan amarillo. Cada golpe se parte en otra dirección. Referente: la
// separación de tintas de una risografía mal registrada.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo', 'Bombo y caja', 'Cada pulso']),
  // FORMA: tamaño de la lámina.
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.3, value: 1),
  // MOVIMIENTO: cuánto se separan las capas.
  CreatorModifier.slider('separacion', 'Separación', min: .5, max: 1.5, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Gran Escisión', {'tamano': 1.3, 'separacion': 1.4}),
  CreatorVariation('Desfase Corto', {'tamano': .7, 'separacion': .6}),
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
    const float T = 1.0f * 0.45f / pace(f);
    const Color red = f.colors[1], lime = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2654435761u + 109u;
      const Vec2 o = {W * (0.35f + 0.3f * rnd(s + 1u)), H * (0.3f + 0.4f * rnd(s + 2u))};
      const float ang = 6.2832f * rnd(s + 3u);
      const float size = g.tamano * (0.45f < 0.5f ? 0.6f + 0.4f * sz : 1.0f);
      // Ya algo separadas en el golpe; se despegan y adelgazan.
      // Despacio al principio (el amarillo dura) y cada vez más.
      const float split = (14.0f + 60.0f * clamp01(q / 0.9f) * clamp01(q / 0.9f) + 30.0f * easeOut(clamp01(q / 0.3f))) * g.separacion * size;
      const float thin = easeInOut((q - 0.35f) / 0.65f);
      const float m = (150.0f * size + split + 40.0f) * px1;
      const float x0 = std::max(0.0f, o.x - m), x1 = std::min(W, o.x + m);
      const float y0 = std::max(0.0f, o.y - m), y1 = std::min(H, o.y + m);
      if (x1 - x0 < 1.0f || y1 - y0 < 1.0f) continue;
      c.material("split", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, o.x, o.y, std::cos(ang), std::sin(ang), px1, split, thin, size, a * pace(f) * (0.45f < 0.5f ? 2.2f : 1.6f), rnd(s + 4u), lv,
                  red.r, red.g, red.b, lime.r, lime.g, lime.b, white.r, white.g, white.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'split': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform vec2 uCenter;
uniform vec2 uAxis;
uniform float uPx;
uniform float uSplit;
uniform float uThin;
uniform float uScale;
uniform float uAge;
uniform float uSeed;
uniform float uAmp;
uniform vec3 uRed;
uniform vec3 uLime;
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
// Tres octavas giradas (los contornos no siguen la rejilla), normalizado a 0-1.
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
// Rodilla: lineal hasta 0,8 y suave por encima; nunca un canal plano.
float knee(float L) {
  return L < 0.8 ? L : 0.8 + 0.2 * (1.0 - exp(-(L - 0.8) / 0.2));
}
// Rampa de un tinte por su brillo final (ya con rodilla): tenue -> medio en
// 0,30-0,60, medio -> caliente en 0,58-0,86 y blanco sólo en la cola de la
// rodilla (0,93-0,995). Bandas anchas: sin saltos de un píxel.
vec3 ramp(float L, vec3 dim, vec3 mid, vec3 hot, vec3 white) {
  vec3 c = mix(dim, mid, smoothstep(0.30, 0.60, L));
  c = mix(c, hot, smoothstep(0.66, 0.9, L));
  return mix(c, white, smoothstep(0.93, 0.995, L));
}
// El canal más alto se comprime con suavidad por encima de 0,7 y nunca pasa
// de 0,88 (+225): ningún canal se queda plano arriba.
vec3 squash(vec3 tone) {
  float m = max(tone.r, max(tone.g, tone.b));
  float m2 = m < 0.7 ? m : 0.7 + 0.18 * (1.0 - exp(-(m - 0.7) / 0.18));
  return tone * (m2 / max(m, 1e-4));
}
// Color final de dos tintes: cada uno con su rampa, sumados (sin normalizar).
vec4 emit2(vec3 cA, float LA, vec3 cB, float LB) {
  vec3 tone = squash(cA * LA + cB * LB);
  return vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
vec4 emit1(vec3 c, float L) {
  vec3 tone = squash(c * L);
  return vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
// Línea suavizada por el gradiente de un campo (distancia en px): mide al
// menos ~3 px y se funde en velo donde se apilan más juntas que su ancho.
float fieldLine(float value, float grad, float widthPx, float haze) {
  float g = max(grad, 0.02);
  float d = value / g;
  float fold = smoothstep(2.5, 5.0, g);
  return mix(exp(-d * d / (widthPx * widthPx)) + 0.3 * exp(-d * d / (8.0 * widthPx * widthPx)), haze, fold);
}

// Una capa con su propio contorno (proporción, giro y bordes propios) que se
// desliza y gira en sentido contrario a la otra; lleva una cresta caliente
// junto a su borde rasgado y se adelgaza desde su borde lejano.
float rotA(float side) {
  return side * (0.08 + 0.32 * uThin + 0.006 * uSplit);
}
float layer(vec2 d, float side, float k) {
  vec2 ax = uAxis;
  float ra = rotA(side);
  vec2 axr = vec2(ax.x * cos(ra) - ax.y * sin(ra), ax.x * sin(ra) + ax.y * cos(ra));
  vec2 nrm = vec2(-axr.y, axr.x);
  // Deslizamiento a lo largo (opuesto en cada capa) y separación pequeña.
  vec2 q = d - axr * side * uSplit * 0.9 - nrm * side * uSplit * 0.35;
  q += (vec2(fbm(q / 60.0 + vec2(k * 7.0, uAge * 3.0)), fbm(q / 60.0 + vec2(3.1, k * 3.0 - uAge * 2.6))) - 0.5) * 30.0 * uScale;
  float uu = dot(q, axr);
  float vv = dot(q, nrm);
  float rx = (side > 0.0 ? 158.0 : 118.0) * uScale;
  float ry = (side > 0.0 ? 58.0 : 82.0) * uScale;
  float e = length(vec2(uu / rx, vv / ry)) + 0.5 * (fbm(q / (side > 0.0 ? 46.0 : 64.0) + k * 5.0) - 0.5) + 0.16 * (fbm(q / 17.0 + k * 9.0) - 0.5);
  float mask = smoothstep(1.0, 0.68, e);
  float far = vv * side;
  mask *= smoothstep(ry * (1.0 - 0.85 * uThin) + 12.0, ry * (1.0 - 0.85 * uThin) - 24.0, far);
  float dens = 0.56 + 0.16 * (fbm(q / 28.0 + vec2(k * 4.0 + uAge * 2.0, uAge * 3.5)) - 0.5) * 2.0;
  // Cresta caliente junto al borde rasgado (el lado que mira a la otra capa).
  float crest = 0.34 * exp(-(vv + side * 0.45 * ry) * (vv + side * 0.45 * ry) / (14.0 * 14.0 * uScale * uScale)) * smoothstep(rx, 0.4 * rx, abs(uu));
  return mask * (dens + crest);
}

void main() {
  vec2 lp = FlutterFragCoord().xy;
  float inside = step(lp.x, uSize.x + 1.0) * step(lp.y, uSize.y + 1.0);
  vec2 d = (lp + uOffset - uCenter) / uPx;
  float k = uAmp * inside;
  float LA = layer(d, 1.0, uSeed * 13.0 + 1.0) * 0.92 * k;
  float LB = layer(d, -1.0, uSeed * 13.0 + 7.0) * 0.92 * k;
  // Donde se tapan con poca luz manda la más fuerte (nada de oliva); con
  // luz suficiente se suman en amarillo.
  float both = smoothstep(0.5, 1.1, LA + LB);
  float wa = LA * LA * LA * LA / max(LA * LA * LA * LA + LB * LB * LB * LB, 1e-6);
  LA = mix(LA * smoothstep(0.51, 0.57, wa), LA, both);
  LB = mix(LB * smoothstep(0.51, 0.57, 1.0 - wa), LB, both);
  vec3 white = mix(uWhite, vec3(1.0), 0.5);
  // Donde se suman en amarillo la luz superpuesta brilla más: el rojo no baja
  // de +180 y el amarillo nunca se apaga en caramelo.
  float kA = knee(LA);
  float kB = knee(LB);
  vec3 tA = ramp(kA, vec3(1.0, 0.1, 0.03), vec3(1.0, 0.24, 0.04), vec3(1.0, 0.42, 0.08), white) * kA + ramp(kB, vec3(0.22, 0.62, 0.0), vec3(0.45, 0.9, 0.04), vec3(0.72, 1.0, 0.16), white) * kB;
  float gr = tA.g / max(tA.r, 1e-3);
  float yel = smoothstep(0.14, 0.46, gr) * (1.0 - smoothstep(1.0, 1.45, gr));
  float lift = mix(1.0, max(1.0, 0.72 / max(tA.r, 1e-3)), yel * both);
  LA = knee(LA * lift);
  LB = knee(LB * lift);
  vec3 cA = ramp(LA, vec3(1.0, 0.1, 0.03), vec3(1.0, 0.24, 0.04), vec3(1.0, 0.42, 0.08), white);
  vec3 cB = ramp(LB, vec3(0.22, 0.62, 0.0), vec3(0.45, 0.9, 0.04), vec3(0.72, 1.0, 0.16), white);
  cA = mix(cA, uRed / max(uRed.r, 0.01), 0.1);
  cB = mix(cB, uLime / max(uLime.g, 0.01), 0.1);
  fragColor = emit2(cA, LA, cB, LB);
}
''',

};
