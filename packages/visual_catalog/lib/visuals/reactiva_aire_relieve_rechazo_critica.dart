// Reactiva · Aire en Relieve — transparencia momentánea. Con el golpe se enciende una
// bocanada ancha de aire caliente vista en schlieren de color: el brillo es
// el relieve del índice de refracción y el color, hacia dónde se inclina
// (esmeralda a un lado, violeta al otro, ultramar de paso). Empieza con
// remolinos grandes y la rotura avanza de un extremo al otro partiéndolos en
// otros cada vez más pequeños; el relieve se apaga a medida que se afina. No
// entra por ningún lado ni sube. Sólo suma luz. Referente: el schlieren en
// color del laboratorio de G. Settles (Penn State).
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpe grande', 'Cada frase', 'Subida de energía']),
  // FORMA: tamaño de la bocanada.
  CreatorModifier.slider('tamano', 'Tamaño', min: .6, max: 1.3, value: 1),
  // MOVIMIENTO: rapidez con la que se parten los remolinos.
  CreatorModifier.slider('rotura', 'Rotura', min: .6, max: 1.4, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Gran Bocanada', {'tamano': 1.3, 'rotura': .8}),
  CreatorVariation('Soplo Rápido', {'tamano': .7, 'rotura': 1.4}),
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
    const float T = 1.1f * 1.0f / pace(f);
    const Color green = f.colors[1], violet = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const uint32_t s = p.id * 2654435761u + 131u;
      const Vec2 o = {W * (0.38f + 0.24f * rnd(s + 1u)), H * (0.34f + 0.32f * rnd(s + 2u))};
      const float ang = 6.2832f * rnd(s + 3u);
      const float size = g.tamano * (1.0f < 0.5f ? 0.6f + 0.4f * sz : 1.0f);
      // La rotura cruza la bocanada de un extremo al otro; luego se apaga.
      const float front = 170.0f * size * (1.0f - 2.0f * clamp01(q * g.rotura / 0.75f));
      const float fade = 1.0f - easeInOut((q - 0.6f) / 0.4f);
      // El aire caliente se expande, más deprisa al principio.
      const float grow = 0.96f + 0.14f * easeOut(clamp01(q / 0.8f));
      // y deriva a lo largo de su eje sin entrar por ningún borde.
      const float drift = 40.0f * size * easeOut(clamp01(q / 0.8f)) * px1;
      const Vec2 oc = {o.x + std::cos(ang) * drift, o.y + std::sin(ang) * drift};
      const float m = (190.0f * size * grow + 40.0f) * px1;
      const float x0 = std::max(0.0f, oc.x - m), x1 = std::min(W, oc.x + m);
      const float y0 = std::max(0.0f, oc.y - m), y1 = std::min(H, oc.y + m);
      if (x1 - x0 < 1.0f || y1 - y0 < 1.0f) continue;
      c.material("schlieren", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, oc.x, oc.y, std::cos(ang), std::sin(ang), px1, front, size * grow, a * pace(f) * (1.0f < 0.5f ? 4.0f : 3.4f), rnd(s + 5u), lv, fade,
                  green.r, green.g, green.b, violet.r, violet.g, violet.b, white.r, white.g, white.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'schlieren': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform vec2 uCenter;
uniform vec2 uAxis;
uniform float uPx;
uniform float uFront;
uniform float uScale;
uniform float uAge;
uniform float uSeed;
uniform float uAmp;
uniform float uFade;
uniform vec3 uGreen;
uniform vec3 uViolet;
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
// squash() deja las zonas densas pegadas a su tope (~+222): una franja plana.
// Tras squash, oscurece hasta `amt` sólo lo caliente con una textura n (0-1)
// que siga el flujo (estrías alargadas, escala >= 5 px). Así pasó Choque.
vec3 breakHot(vec3 tone, float n, float amt) {
  float mt = max(tone.r, max(tone.g, tone.b));
  return tone * (1.0 - amt * clamp((n - 0.25) / 0.5, 0.0, 1.0) * smoothstep(0.62, 0.82, mt));
}
// Línea suavizada por el gradiente de un campo (distancia en px): mide al
// menos ~3 px y se funde en velo donde se apilan más juntas que su ancho.
float fieldLine(float value, float grad, float widthPx, float haze) {
  float g = max(grad, 0.02);
  float d = value / g;
  float fold = smoothstep(2.5, 5.0, g);
  return mix(exp(-d * d / (widthPx * widthPx)) + 0.3 * exp(-d * d / (8.0 * widthPx * widthPx)), haze, fold);
}

// Densidad del aire: remolinos grandes que se mezclan con otros más pequeños
// donde ya pasó la rotura.
float density(vec2 p, float b) {
  return mix(fbm(p / 72.0), fbm(p / 36.0 + vec2(5.3, 1.7)), b);
}

void main() {
  vec2 lp = FlutterFragCoord().xy;
  float inside = step(lp.x, uSize.x + 1.0) * step(lp.y, uSize.y + 1.0);
  vec2 d = (lp + uOffset - uCenter) / uPx;
  vec2 ax = uAxis;
  vec2 nrm = vec2(-ax.y, ax.x);
  float u = dot(d, ax);
  float v = dot(d, nrm);
  // Bocanada alargada con borde irregular y muy suave (sin contorno).
  float e = length(vec2(u / (150.0 * uScale), v / (88.0 * uScale))) + 0.4 * (fbm(d / 60.0 + uSeed * 5.0) - 0.5);
  float mask = smoothstep(1.0, 0.5, e);
  // La rotura avanza a lo largo: detrás del frente los remolinos son pequeños.
  float b = smoothstep(uFront - 45.0 * uScale, uFront + 45.0 * uScale, u);
  vec2 p = d / uScale + (vec2(fbm(d / 90.0 + vec2(uAge * 4.0, uSeed * 2.0)), fbm(d / 90.0 + vec2(uSeed * 6.0, -uAge * 3.5))) - 0.5) * 60.0;
  // El aire caliente fluye a través de la bocanada.
  p += vec2(20.0, -12.0) * uAge;
  p += (vec2(fbm(p / 40.0 + vec2(uSeed * 4.0, uAge * 6.0)), fbm(p / 40.0 + vec2(-uAge * 5.0, uSeed * 8.0))) - 0.5) * 24.0 * b;
  float n0 = density(p, b);
  float nx = density(p + vec2(10.0, 0.0), b);
  float ny = density(p + vec2(0.0, 10.0), b);
  vec2 gr = vec2(nx - n0, ny - n0) / 10.0 * mix(72.0, 36.0, b);
  // Cuchilla de dos colores: el signo de la pendiente en una dirección fija
  // elige el tinte; sin pendiente queda violeta.
  vec2 kn = vec2(ax.x * 0.8 - ax.y * 0.6, ax.x * 0.6 + ax.y * 0.8);
  float gm = length(gr);
  float tc = 0.5 + 0.5 * dot(gr, kn) / sqrt(gm * gm + 0.9);
  // Relieve suave sobre el cuerpo del soplo: nada de contornos ni huecos.
  float rel = smoothstep(0.05, 1.1, gm);
  float Lb = knee(mask * (0.55 + 0.32 * rel * (1.0 - 0.4 * b)) * (1.0 - 0.15 * b) * uFade) * uAmp * inside;
  vec3 white = mix(uWhite, vec3(1.0), 0.5);
  vec3 cVi = ramp(Lb, vec3(0.42, 0.02, 1.0), vec3(0.55, 0.06, 1.0), vec3(0.78, 0.42, 1.0), white);
  vec3 cU = ramp(Lb, vec3(0.1, 0.05, 1.0), vec3(0.18, 0.13, 1.0), vec3(0.42, 0.38, 1.0), white);
  vec3 cE = ramp(Lb, vec3(0.0, 0.62, 0.22), vec3(0.02, 0.92, 0.36), vec3(0.35, 1.0, 0.6), white);
  cVi = mix(cVi, uViolet / max(uViolet.b, 0.01), 0.1);
  cE = mix(cE, uGreen / max(uGreen.g, 0.01), 0.1);
  vec3 c = mix(cVi, cU, smoothstep(0.38, 0.52, tc));
  c = mix(c, cE, smoothstep(0.49, 0.69, tc));
  vec3 tone = squash(c * Lb);
  tone = breakHot(tone, n0, 0.12);
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
