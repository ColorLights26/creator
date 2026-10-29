// Reactiva Mejorada · Cadena de Iris — transparencia momentánea. Con el bombo, una luz fuerte que
// entra por el borde del cuadro (un resplandor quemado medio fuera de la
// pantalla) hace que la lente proyecte su cadena de fantasmas: polígonos del
// diafragma sobre la línea que va de la luz al centro, de tamaños muy
// distintos, casi transparentes por dentro, con un aro de 2-3 px de borde
// suave, el filo de color y el polvo de la lente dentro, teñidos de rojo,
// verde y violeta por los recubrimientos, y dos fantasmas diminutos y
// brillantes cerca del centro. La luz se desliza y los fantasmas con ella;
// los pequeños se apagan antes. La luz se suma a la escena. Referente: los
// fantasmas de Optical Flares y de los objetivos anamórficos.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué golpe enciende la luz.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo', 'Cada tiempo', 'Golpes acentuados']),
  // FORMA: cuántos fantasmas.
  CreatorModifier.steps('fantasmas', 'Fantasmas', min: 4, max: 8, value: 7),
  // MODO: forma del diafragma.
  CreatorModifier.choice('lamina', 'Diafragma', options: ['Siete láminas', 'Seis láminas', 'Redondo']),
  // MOVIMIENTO: cuánto tarda en apagarse.
  CreatorModifier.slider('caida', 'Caída', min: .15, max: .6, value: .35),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Vintage', {'fantasmas': 8, 'lamina': 'Seis láminas', 'caida': .5}),
  CreatorVariation('Limpio', {'fantasmas': 4, 'lamina': 'Redondo', 'caida': .2}),
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
    fire(d == 0 ? h.kick : d == 1 ? every(h, 4) : h.big, d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    const float px1 = W / 360.0f;
    const float T = (0.05f + 0.7f * g.caida) / pace(f);
    // La luz más reciente manda.
    float age = 100.0f, amp = 0.0f;
    uint32_t id = 0u;
    for (const Pulse& p : slots) {
      const float a = float(now - p.start);
      if (a < 0.0f || a > T || a >= age) continue;
      age = a;
      amp = std::min(amount(p.power) * f.intensity, 1.3f);
      id = p.id;
    }
    if (amp <= 0.0f) return;
    // La luz entra por el borde, en un sitio distinto cada vez, y se desliza
    // unos 5 px por cuadro a lo largo de él.
    const float sx[4] = {-0.02f, 1.02f, 0.18f, 0.85f}, sy[4] = {0.15f, 0.22f, -0.01f, -0.01f};
    const float dx[4] = {0.0f, 0.0f, 1.0f, -1.0f}, dy[4] = {1.0f, 1.0f, 0.0f, 0.0f};
    const int at = int(id % 4u);
    const float slide = 150.0f * px1 * age;
    const Color red = f.colors[1], green = f.colors[2], violet = f.colors[3];
    c.material("iris", {0.0f, 0.0f, W, H},
               {sx[at] * W + dx[at] * slide, sy[at] * H + dy[at] * slide, age, T, amp, std::round(g.fantasmas), float(m.lamina), float(id % 7u),
                red.r, red.g, red.b, green.r, green.g, green.b, violet.r, violet.g, violet.b},
               {"dirt"});
  }
};
''';

const shaderSources = <String, String>{
  'iris': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uSource;
uniform float uAge;
uniform float uT;
uniform float uAmp;
uniform float uCount;
uniform float uBlades;
uniform float uSeed;
uniform vec3 uRed;
uniform vec3 uGreen;
uniform vec3 uViolet;
uniform sampler2D uTex;
out vec4 fragColor;

// Distancia normalizada al borde del diafragma (1 en el borde).
float iris(vec2 q, float rad, float blades) {
  float r = length(q) / rad;
  if (blades < 3.0) return r;
  float seg = 6.28318 / blades;
  float a = atan(q.y, q.x) + 0.3;
  return r * cos(mod(a, seg) - seg * 0.5) / cos(seg * 0.5);
}

// Fantasma en px: relleno que sube del 75 % en el centro al 100 % cerca del
// borde, aro suave (sigma 2,5 px) 3 px dentro que como mucho dobla 1,6 veces
// el relleno, y borde exterior que se apaga en max(3 px, 6 % del radio).
float ghost(float d, float radPx, float fill) {
  float dpx = (d - 1.0) * radPx;
  float fw = max(3.0, 0.06 * radPx);
  float outer = smoothstep(0.5 * fw + 0.5, -0.5 * fw - 0.5, dpx);
  float rn = clamp(d, 0.0, 1.0);
  float body = 0.75 + 0.25 * rn * rn;
  float rim = 0.45 * exp(-(dpx + 3.0) * (dpx + 3.0) / 12.5);
  return outer * fill * (body + rim);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  float blades = uBlades < 0.5 ? 7.0 : (uBlades < 1.5 ? 6.0 : 0.0);
  vec2 C = 0.5 * uSize;
  vec2 axis = C - uSource;
  float dust = texture(uTex, fract(p / uSize.x * 0.9 + vec2(uSeed * 0.13))).r;
  vec3 light = vec3(0.0);
  for (int i = 0; i < 10; i++) {
    float fi = float(i);
    // Ocho fantasmas como mucho y dos diminutos cerca del centro.
    bool tiny = i >= 8;
    if (!tiny && fi >= uCount) continue;
    float s = i == 0 ? 0.22 : (i == 1 ? 0.48 : (i == 2 ? 0.7 : (i == 3 ? 0.95 : (i == 4 ? 1.22 : (i == 5 ? 1.5 : (i == 6 ? 1.85 : (i == 7 ? 2.3 : (i == 8 ? 0.58 : 1.08))))))));
    float radPx = i == 0 ? 16.0 : (i == 1 ? 40.0 : (i == 2 ? 11.0 : (i == 3 ? 64.0 : (i == 4 ? 24.0 : (i == 5 ? 100.0 : (i == 6 ? 30.0 : (i == 7 ? 52.0 : (i == 8 ? 4.5 : 3.5))))))));
    float rad = radPx * px1;
    vec2 q = p - (uSource + axis * s);
    if (dot(q, q) > rad * rad * 1.5 + 16.0 * px1 * px1) continue;
    // Los pequeños se apagan antes.
    float life = uT * (0.45 + 0.55 * clamp(radPx / 100.0, 0.0, 1.0));
    float fade = 1.0 - smoothstep(life * 0.5, life, uAge);
    // Colores alternos a lo largo de la cadena: nunca dos vecinos iguales,
    // los dos más grandes uno rojo y otro verde y el azul sólo en los de
    // hasta 60 px.
    float m = (i == 0 || i == 2 || i == 4) ? 2.0 : ((i == 1 || i == 5 || i == 7 || i == 9) ? 0.0 : 1.0);
    if (m < 2.0 && mod(uSeed, 2.0) >= 1.0) m = 1.0 - m;
    vec3 tint = m < 1.0 ? uRed : (m < 2.0 ? uGreen : uViolet);
    tint = pow(tint / max(max(tint.r, tint.g), max(tint.b, 0.01)), vec3(1.4));
    if (tiny) {
      // Los diminutos, macizos: centro casi blanco de 3 px y borde de color
      // suave de 2 px.
      float dpx = (iris(q, rad, blades) - 1.0) * radPx;
      float body = smoothstep(1.0, -1.0, dpx);
      float rq = length(q) / px1;
      light += (body * tint * 0.55 + exp(-rq * rq / 2.2) * 0.78) * fade;
      continue;
    }
    // Relleno en el centro según el ancho: +80 hasta 40 px, +55 a 40-60 px
    // y +36 desde 100 px (el borde, un tercio más).
    float wpx = 2.0 * radPx;
    float centre = wpx <= 40.0 ? 0.31 : (wpx <= 60.0 ? mix(0.31, 0.215, (wpx - 40.0) / 20.0) : mix(0.215, 0.14, smoothstep(60.0, 100.0, wpx)));
    float fill = centre / 0.75;
    // Filo de color: el polígono del rojo 1,5 px más grande que el del azul.
    vec3 shape = vec3(ghost(iris(q, rad + 1.5 * px1, blades), radPx + 1.5, fill),
                      ghost(iris(q, rad + 0.75 * px1, blades), radPx + 0.75, fill),
                      ghost(iris(q, rad, blades), radPx, fill));
    light += shape * tint * (0.85 + 0.3 * dust) * fade;
  }
  // La luz que entra: quemada hasta 20 px (medio fuera de la pantalla), +200
  // a 30, +90 a 60, +30 a 110 y nada a 160; blanca en lo intenso y fría en
  // la cola. Dos cuadros enteros, uno a la mitad de radio y luego nada.
  float rs = length(p - uSource) / px1 / (uAge < 0.067 ? 1.0 : 0.5);
  float gl = rs < 20.0 ? 1.1 : (rs < 30.0 ? mix(1.1, 0.78, (rs - 20.0) / 10.0) : (rs < 60.0 ? mix(0.78, 0.35, (rs - 30.0) / 30.0)
           : (rs < 110.0 ? mix(0.35, 0.12, (rs - 60.0) / 50.0) : mix(0.12, 0.0, clamp((rs - 110.0) / 50.0, 0.0, 1.0)))));
  float rg = rs < 12.0 ? 1.1 : (rs < 20.0 ? mix(1.1, 0.667, (rs - 12.0) / 8.0) : (rs < 28.0 ? mix(0.667, 0.431, (rs - 20.0) / 8.0)
           : (rs < 40.0 ? mix(0.431, 0.235, (rs - 28.0) / 12.0) : (rs < 60.0 ? mix(0.235, 0.098, (rs - 40.0) / 20.0) : mix(0.098, 0.0, clamp((rs - 60.0) / 30.0, 0.0, 1.0))))));
  float on = 1.0 - step(0.1, uAge);
  light += vec3(rg, rg, gl) * on;
  light *= uAmp;
  vec3 tone = min(light, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
