// Reactiva Mejorada · Onda en el Cristal — transparencia momentánea. Con el bombo se abren sobre la
// escena unas ondas rápidas como en una lámina de agua: cada anillo tiene una
// cresta de luz fina y, justo dentro, un valle de sombra sin color, así que se
// leen como refracción; la cresta tiene un filo de color apenas separado. Los
// anillos se amortiguan al crecer y se apagan en medio segundo. La luz y la
// sombra se suman a la escena. Referente: una gota sobre una lámina de agua
// filmada a alta velocidad.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué golpe lanza la onda.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Bombo', 'Caja', 'Graves fuertes']),
  // FORMA: cuántas ondas por golpe.
  CreatorModifier.steps('ondas', 'Ondas', min: 2, max: 5, value: 4),
  // ATMÓSFERA: contraste de la onda.
  CreatorModifier.slider('profundidad', 'Profundidad de la onda', min: .3, max: 1, value: .7),
  // MOVIMIENTO: de dónde nace.
  CreatorModifier.choice('origen', 'Origen', options: ['Al azar', 'Centro', 'Abajo']),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Gota', {'ondas': 2, 'profundidad': 1, 'origen': 'Centro'}),
  CreatorVariation('Lluvia de Graves', {'ondas': 5, 'profundidad': .5, 'disparo': 'Graves fuertes'}),
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
    fire(d == 0 ? h.kick : d == 1 ? h.snare : h.bassUp, d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    const float T = 0.6f / pace(f);
    const Color shadow = f.colors[1], warm = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float age = float(now - p.start);
      if (age < 0.0f || age > T) continue;
      const float k = std::min(amount(p.power) * f.intensity, 1.3f);
      const int at = m.origen == 0 ? 0 : m.origen;
      const float ox = at == 0 ? W * (0.2f + 0.6f * rnd(p.id * 7u + 1u)) : 0.5f * W;
      const float oy = at == 0 ? H * (0.2f + 0.6f * rnd(p.id * 9u + 2u)) : at == 1 ? 0.5f * H : 0.95f * H;
      // El paquete de ondas crece rápido; sólo se pinta su cuadrado.
      const float R = W * 0.08f + W * 1.1f * easeOut(age / T);
      const float reach = R + 0.12f * W;
      const float x0 = std::max(0.0f, ox - reach), y0 = std::max(0.0f, oy - reach);
      const float x1 = std::min(W, ox + reach), y1 = std::min(H, oy + reach);
      if (x1 <= x0 || y1 <= y0) continue;
      c.material("ripple", {x0, y0, x1 - x0, y1 - y0},
                 {x0, y0, W, ox, oy, R, age / T, k * g.profundidad, std::round(g.ondas),
                  shadow.r, shadow.g, shadow.b, warm.r, warm.g, warm.b, white.r, white.g, white.b});
    }
  }
};
''';

const shaderSources = <String, String>{
  'ripple': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uOffset;
uniform float uWidth;
uniform vec2 uOrigin;
uniform float uR;
uniform float uT;
uniform float uAmp;
uniform float uWaves;
uniform vec3 uShadow;
uniform vec3 uWarm;
uniform vec3 uWhite;
out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy + uOffset;
  float px1 = uWidth / 360.0;
  vec2 v = p - uOrigin;
  float r = length(v) / px1;
  float th = atan(v.y, v.x);
  float age = uT * 0.6;
  float Rf = uR / px1;
  // Las crestas se ensanchan de 3 a 7-8 px mientras bajan.
  float fw = clamp(3.0 + 19.0 * (age - 0.067), 2.5, 8.0);
  float sg = fw / 2.355;
  float damp = pow(1.0 - uT, 1.5);
  // Desde unos 0,3 s cada cresta se rompe en un 10-20 % de su contorno.
  float brk = 0.1 * smoothstep(0.28, 0.4, age);
  vec2 L = normalize(vec2(-0.6, -0.8));
  float lit = 0.8 + 0.2 * max(dot(v / max(length(v), 0.001), L), 0.0);
  float crest = 0.0;
  float redF = 0.0;
  float shade = 0.0;
  float off = 0.0;
  for (int k = 0; k < 5; k++) {
    float fk = float(k);
    if (fk >= uWaves) continue;
    // Separaciones de delante a atrás 30/24/19/16 px que crecen 2 px por cuadro.
    float gap = (k == 1 ? 30.0 : (k == 2 ? 24.0 : (k == 3 ? 19.0 : 16.0))) + 60.0 * (age - 0.067);
    if (k > 0) off += max(gap, 6.0);
    float rk = Rf - off;
    if (rk < 12.0) continue;
    float A = k == 0 ? 0.7 : (k == 1 ? 1.0 : (k == 2 ? 0.6 : (k == 3 ? 0.3 : 0.15)));
    // Borde orgánico: ±25 % de brillo en 3-5 lóbulos que giran y ±1,5 px de radio.
    float n = 1.0 + 0.25 * (0.6 * sin(3.0 * th + age * 2.2 + fk * 1.7) + 0.4 * sin(5.0 * th - age * 1.8 + fk * 2.9));
    float wob = 1.5 * min(1.0, rk / 60.0) * sin(4.0 * th + fk * 1.3 + age * 1.5);
    float on = smoothstep(brk - 0.05, brk + 0.05, 0.5 + 0.5 * sin(2.0 * th + fk * 2.3 + 0.7));
    float dr = r - rk - wob;
    float a = A * n * on;
    // Núcleo de 1-2 px quemado y flancos azules anchos.
    float sf = max(sg, 2.2);
    crest += a * (1.3 * exp(-dr * dr / 0.72) + 1.3 * exp(-dr * dr / (2.0 * sf * sf)));
    // Filo exterior rojo (0,8 del azul de su cresta) sólo en crestas fuertes.
    float pk = a * damp * uAmp * lit * 0.9;
    float ro = dr - (0.5 * fw + 2.0);
    redF += pk * 0.8 * exp(-ro * ro / 0.8) * smoothstep(0.45, 0.52, pk);
    // Valle de sombra estrecho justo dentro de la cresta.
    float ti = dr + 0.5 * fw + 2.0;
    shade += a * exp(-ti * ti / 1.4);
  }
  float I = crest * damp * uAmp * lit;
  // Color por intensidad: blanco sólo desde +200 (núcleo fino); por debajo,
  // azul saturado. Fuera, rojo vivo.
  vec3 blue = vec3(0.3, 0.5, 1.0);
  vec3 white = mix(uWhite, vec3(1.0), 0.5);
  vec3 col = mix(blue, white, smoothstep(0.78, 0.88, I));
  vec3 red = mix(vec3(1.0, 0.165, 0.063), uWarm / max(uWarm.r, 0.01), 0.1);
  vec3 light = col * min(I, 1.0) + red * min(redF, 1.0);
  vec3 tone = min(light, vec3(1.0));
  float sh = min(0.08 * shade * damp * uAmp, 0.08);
  float m = max(tone.r, max(tone.g, tone.b));
  fragColor = vec4(tone + uShadow * sh, clamp(max(sh * (1.0 - m), 0.1 * m), 0.0, 1.0));
}
''',

};
