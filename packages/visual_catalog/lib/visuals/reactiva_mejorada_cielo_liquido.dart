// Reactiva Mejorada · Cielo Líquido — transparencia momentánea. Con el golpe se enciende por encima
// de la escena una lámina de láser rojo que corta el humo: vista desde abajo,
// en perspectiva hasta el horizonte, es un techo de olas de luz que ruedan
// hacia ti, cada cresta una línea roja intensa de grosor fino y constante y un
// velo suave de humo encendido entre ellas. Se abre barriendo y se apaga
// adelgazando. Rojo láser saturado; sólo el filo de las crestas cercanas se
// acerca al blanco. Sólo suma luz. Referente: el efecto «liquid sky» de los
// láseres de club.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo', 'Bombo y caja', 'Cada pulso']),
  // FORMA: dónde queda el horizonte del techo de luz.
  CreatorModifier.slider('altura', 'Horizonte', min: .3, max: .6, value: .44),
  // ATMÓSFERA: tamaño de las olas.
  CreatorModifier.slider('olas', 'Olas', min: .5, max: 1.5, value: 1),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Techo Bajo', {'altura': .58, 'olas': 1.3}),
  CreatorVariation('Mar Lejano', {'altura': .32, 'olas': .6}),
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
    const float T = 1.2f * 0.45f / pace(f);
    const Color red = f.colors[1], hot = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T) continue;
      const float q = a / T;
      // El volumen cambia el tamaño, no el brillo del color.
      const float lv = std::min(f.intensity, 1.2f);
      const float sz = std::clamp(0.6f + 0.5f * p.power, 0.6f, 1.15f);
      const float scan = 0.5f + 0.5f * easeOut(clamp01(a * pace(f) / 0.1f));
      // La Mejorada también sigue el horizonte elegido, con algo de variación.
      const float y = H * g.altura * (0.45f < 0.5f ? 0.75f + 0.5f * rnd(p.id * 9u + 2u) : 1.0f) * (0.45f < 0.5f ? sz / 1.15f + 0.13f : 1.0f);
      const float thin = 1.0f - easeInOut((q - 0.35f) / 0.65f);
      // Cada golpe las olas ruedan a otra velocidad.
      const float roll = float(now) * (0.8f + 0.5f * rnd(p.id * 7u + 1u));
      c.material("sky", {0.0f, 0.0f, W, y},
                 {y, scan, (p.id % 2u) == 1u ? 1.0f : 0.0f, thin, lv, g.olas, roll, rnd(p.id * 5u + 3u),
                  red.r, red.g, red.b, hot.r, hot.g, hot.b, white.r, white.g, white.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'sky': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uHorizon;
uniform float uScan;
uniform float uFlip;
uniform float uThin;
uniform float uAmp;
uniform float uWaves;
uniform float uTime;
uniform float uSeed;
uniform vec3 uRed;
uniform vec3 uHot;
uniform vec3 uWhite;
out vec4 fragColor;

// Profundidad del techo de humo bajo el píxel: 0,87 arriba (cerca) y 6,7 en
// el horizonte (lejos).
float depth(vec2 p) {
  float v = clamp((uHorizon - p.y) / max(uHorizon, 1.0), 0.0, 1.0);
  return 1.0 / (v + 0.15);
}

// Fase de las olas: unas 10 crestas de cerca al horizonte que ruedan hacia ti,
// onduladas a lo ancho por dos olas de 220 y 140 px.
float phase(vec2 p, float px1) {
  float z = depth(p);
  float xw = (p.x / px1 - 180.0) * z * 1.15;
  float t = uTime;
  // A lo lejos las ondas laterales se calman para que no se vuelvan dientes.
  float calm = 1.6 / (z * 1.15 + 0.6);
  return 10.8 * z + uWaves * calm * (1.2 * sin(xw / 35.0 + uSeed * 6.0 + t * 0.7) + 0.6 * sin(xw / 22.0 - uSeed * 4.0 - t * 1.1)) + (5.5 + 2.0 * uSeed) * t;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  float x = p.x / px1;
  // Barrido de apertura desde un lado.
  float sx = uFlip > 0.5 ? 360.0 - x : x;
  float reveal = smoothstep(uScan * 420.0, uScan * 420.0 - 60.0, sx);
  float dyp = (uHorizon - p.y) / px1;
  if (reveal < 0.002 || dyp < 0.5) {
    fragColor = vec4(0.0);
    return;
  }
  float ph = phase(p, px1);
  float gx = phase(p + vec2(1.0, 0.0), px1) - ph;
  float gy = phase(p + vec2(0.0, 1.0), px1) - ph;
  float grad = max(length(vec2(gx, gy)), 0.0005) * px1;
  // Distancia a la cresta más cercana y separación entre crestas, en px.
  float wr = ph / 6.2831853;
  float cyc = wr - floor(wr + 0.5);
  float dpx = abs(cyc) * 6.2831853 / grad;
  float spacing = 6.2831853 / grad;
  // Superficie continua: valles tenues y crestas brillantes.
  float cc = 0.5 + 0.5 * cos(ph);
  float surf = 0.25 + 0.75 * cc * cc;
  // Filo de la cresta de 2-3 px con su resplandor; sólo las cimas de algunos
  // tramos (menos del 15 %) llegan al blanco.
  float sgc = 1.1 * mix(0.6, 1.0, uThin);
  float core = exp(-dpx * dpx / (2.0 * sgc * sgc));
  float glw = exp(-dpx * dpx / 32.0);
  float z = depth(p);
  float xw = (x - 180.0) * z * 1.15;
  float top = smoothstep(0.8, 1.0, sin(xw / 41.0 + floor(wr + 0.5) * 1.7 + uSeed * 5.0));
  float crest = max(surf * 0.85, (0.82 * core + 0.3 * glw) * (1.0 + 0.32 * top));
  // Donde las crestas quedan a menos de 6 px se funden en una banda de
  // neblina que se apaga en los últimos 20 px antes del horizonte.
  float lineW = smoothstep(9.0, 24.0, spacing);
  float att = 1.0 / (1.0 + (z * 1.15 - 1.0) * 0.25);
  float L = mix(0.7, crest, lineW) * att * smoothstep(0.0, 20.0, dyp) * reveal * uThin * uAmp;
  // Rodilla suave: sólo la cima de la cresta se quema.
  L = L < 0.85 ? L : 0.85 + 0.15 * (1.0 - exp(-(L - 0.85) / 0.15));
  // Rojo láser puro (G y B por debajo del 12 % de R) y blanco sólo en las
  // cimas.
  vec3 red = mix(vec3(1.0, 0.1, 0.06), uRed / max(uRed.r, 0.01), 0.1);
  vec3 coreRed = mix(red, uHot / max(uHot.r, 0.01), 0.05);
  vec3 col = mix(red, coreRed, core);
  col = mix(col, mix(uWhite, vec3(1.0), 0.5), smoothstep(0.92, 0.99, L));
  vec3 tone = min(col * L, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
