// Reactiva Mejorada · Cortina Svoboda — transparencia momentánea. Al empezar una frase se
// materializa desde arriba la «cortina de luz» de Josef Svoboda: entre 36 y 48
// haces finísimos (núcleo de 1-1,5 px casi blanco y halo de 2 px) a distancias
// irregulares, cada uno con su brillo y unos pocos con una vena más intensa,
// que se abren apenas hacia abajo y se apagan con la distancia; cada lámpara
// es un punto caliente en el borde superior y entre los haces sólo queda un
// humo muy tenue con polvo que flota. Se mantiene un instante y se recoge
// hacia arriba desde abajo. La luz se suma a la escena. Referente: la cortina
// de luz de Svoboda y los muros de haces de Nine Inch Nails.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento la enciende.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Cada dos tiempos', 'Platillos fuertes', 'Golpes acentuados']),
  // FORMA: cuántos rayos.
  CreatorModifier.steps('rayos', 'Rayos', min: 36, max: 48, value: 42),
  // MOVIMIENTO: inclinación de la lámina.
  CreatorModifier.slider('inclinacion', 'Inclinación', min: -15, max: 15, value: 3),
  // ATMÓSFERA: polvo dentro de la luz.
  CreatorModifier.slider('polvo', 'Polvo', min: 0, max: 1, value: .6),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Teatro', {'rayos': 48, 'inclinacion': 0, 'polvo': 1}),
  CreatorVariation('Contraluz', {'rayos': 36, 'inclinacion': -12, 'disparo': 'Golpes acentuados'}),
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
    fire(d == 0 ? every(h, 16) : d == 1 ? h.hatBig : h.big, d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height;
    // La cortina más reciente.
    float age = 100.0f, amp = 0.0f;
    uint32_t id = 0u;
    for (const Pulse& p : slots) {
      const float a = float(now - p.start) * pace(f);
      if (a < 0.0f || a > 1.0f || a >= age) continue;
      age = a;
      amp = std::min(amount(p.power) * f.intensity, 1.3f);
      id = p.id;
    }
    if (amp <= 0.0f) return;
    const Color orange = f.colors[1], amber = f.colors[2], white = f.colors[3];
    c.material("curtain", {0.0f, 0.0f, W, H},
               {age, amp, std::round(g.rayos), g.inclinacion * float(pi) / 180.0f, g.polvo, float(now), H / W, float(id % 13u),
                orange.r, orange.g, orange.b, amber.r, amber.g, amber.b, white.r, white.g, white.b},
               {"smoke"});
  }
};
''';

const shaderSources = <String, String>{
  'curtain': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uAge;
uniform float uAmp;
uniform float uRays;
uniform float uTilt;
uniform float uDust;
uniform float uTime;
uniform float uAspect;
uniform float uSeed;
uniform vec3 uOrange;
uniform vec3 uAmber;
uniform vec3 uWhite;
uniform sampler2D uTex;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 uv = px / uSize.x;
  float px1 = uSize.x / 360.0;
  float ypx = px.y / px1;
  float a = uAge;
  // Baja en cinco cuadros, se mantiene ocho y se recoge desde abajo a unos
  // 60 px por cuadro.
  float bottom = a < 0.15 ? a / 0.15 * (uAspect + 0.2) : (uAspect + 0.2) - max(0.0, a - 0.42) * 5.0;
  // Haces a distancias irregulares (6-14 px) que se abren unos 2° hacia abajo.
  float xs = 0.5 + (uv.x - 0.5 - uv.y * tan(uTilt)) / (1.0 + 0.035 * uv.y);
  float u = xs * uRays;
  float i0 = floor(u);
  float spacing = 360.0 / uRays;
  float B = 0.0;
  float lamp = 0.0;
  for (int k = -1; k <= 1; k++) {
    float idx = i0 + float(k);
    float cpos = idx + 0.5 + (hash(idx + uSeed) - 0.5) * 0.55;
    float dx = (u - cpos) * spacing;
    // Brillos mezclados: un cuarto tenues, la mitad medios, algunos a tope y
    // unas pocas venas con más resplandor; cada uno titila un poco.
    float hb = hash(idx + 7.3);
    float gain = hb < 0.25 ? 0.35 + 0.6 * hb : (hb < 0.75 ? 0.6 + 0.4 * (hb - 0.25) : (hb < 0.9 ? 1.0 : 1.15));
    float vein = step(0.9, hb);
    gain *= 1.0 + 0.15 * sin(uTime * 26.0 + idx * 2.3);
    // Cada haz varía ±15 % a lo largo, con manchas de 40-80 px que bajan.
    gain *= 0.85 + 0.3 * texture(uTex, fract(vec2(idx * 0.137, ypx / 300.0 - uTime * 0.15))).r;
    // Ritmo grande a lo ancho: el brillo de los haces sube y baja ±30 % en
    // ondas de 60-120 px que derivan despacio.
    float bx = cpos * spacing;
    gain *= 1.0 + 0.3 * (0.6 * sin(6.2832 * bx / 90.0 + uTime * 1.6) + 0.4 * sin(6.2832 * bx / 150.0 - uTime * 1.0));
    // Cada haz acaba a su altura (±50 px) y se desvanece en unos 35 px.
    float end = bottom + (hash(idx + 4.4) - 0.5) * 0.28;
    float tail = smoothstep(end, end - 0.1, uv.y);
    B += (exp(-dx * dx / 0.5) + 0.3 * exp(-dx * dx / 4.0) + vein * 0.35 * exp(-dx * dx / 9.0)) * gain * tail;
    // La lámpara: un punto quemado de 1,5 px con su resplandor de 6 px.
    float ly = ypx - 3.0;
    lamp += (4.0 * exp(-(dx * dx + ly * ly) / 2.25) + 0.65 * exp(-(dx * dx + ly * ly) / 36.0)) * (0.85 + 0.3 * hash(idx + 5.1)) * smoothstep(0.0, 0.03, a);
  }
  // Se apagan con la distancia: unos +100 a 700 px.
  float dim = 1.0 / (1.0 + ypx / 210.0);
  // Entre los haces sólo un humo muy tenue.
  float haze = texture(uTex, fract(vec2(u * 0.03 + 0.3, uv.y * 0.35 - uTime * 0.04))).r;
  // El humo entre los haces brilla un poco (+6..+12, más cerca de las
  // lámparas) y baja despacio.
  float hz = texture(uTex, fract(vec2(px.x / (100.0 * px1), (ypx - uTime * 45.0) / 200.0))).r;
  float sx = xs * 360.0;
  float rhythm = 1.0 + 0.3 * (0.6 * sin(6.2832 * sx / 90.0 + uTime * 1.6) + 0.4 * sin(6.2832 * sx / 150.0 - uTime * 1.0));
  float sheet = (mix(0.045, 0.024, smoothstep(0.25, 0.5, uv.y / uAspect)) * (0.7 + 0.6 * hz) + 0.05 * exp(-ypx / 40.0)) * rhythm * smoothstep(bottom, bottom - 0.1, uv.y);
  // Polvo que flota dentro de la luz.
  vec2 drift = vec2(uTime * 3.0, uTime * 9.0) * px1;
  vec2 cell = floor((px + drift) / (6.0 * px1));
  vec2 cp = (cell + vec2(hash2(cell), hash2(cell + 4.1))) * 6.0 * px1 - drift;
  float dust = step(0.965, hash2(cell + 2.7)) * exp(-dot(px - cp, px - cp) / (px1 * px1 * 1.2)) * 1.5 * uDust * min(B, 1.0);
  // El humo entre los haces es neutro, tirando a frío.
  vec3 light = (B * 2.4 * dim + dust) * mix(uWhite, uAmber, 0.12) + sheet * vec3(0.85, 0.92, 1.0) + lamp * uWhite;
  light *= uAmp * smoothstep(0.0, 0.04, a);
  vec3 tone = vec3(1.0) - exp(-light);
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
