// Reactiva Mejorada · Reflejo que Cruza — transparencia momentánea. Al empezar un compás o una
// frase, el reflejo de un vidrio que se mueve atraviesa la escena una sola
// vez: un brillo ancho y suave, una línea nítida en su centro y otra más tenue
// detrás (las dos caras del vidrio), con un filo irisado en los bordes y las
// huellas del cristal visibles dentro del brillo; la franja va un poco
// curvada, como un vidrio curvo. La luz se suma a la escena. Referente: el
// barrido de luz sobre el cristal de un reloj o de un móvil en un anuncio.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: cuándo cruza.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Cada tiempo', 'Cada dos tiempos', 'Golpes acentuados']),
  // FORMA: inclinación de la franja.
  CreatorModifier.slider('angulo', 'Ángulo', min: -60, max: 60, value: 25),
  // ATMÓSFERA: ancho de la franja de luz.
  CreatorModifier.slider('ancho', 'Ancho de la franja', min: .08, max: .45, value: .2),
  // MOVIMIENTO: cómo cruza.
  CreatorModifier.choice('paso', 'Paso', options: ['Una vez', 'Ida y vuelta', 'Doble']),
  // Cuánto tarda en cruzar.
  CreatorModifier.slider('cruce', 'Duración del cruce', min: .35, max: 1.4, value: .7),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Vitrina', {'angulo': -35, 'ancho': .12, 'paso': 'Doble'}),
  CreatorVariation('Faro', {'paso': 'Ida y vuelta', 'ancho': .35, 'disparo': 'Cada dos tiempos', 'cruce': 1.2}),
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
    if (d == 2) {
      fire(h.big, 1);  // el golpe grande lanza un reflejo mayor
      return;
    }
    const int every = d == 0 ? 1 : 2;
    for (int i = 0; i < h.beats; i++)
      if (h.tick[i] % every == 0) fire(std::max(h.beat, 0.5f), 0);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    const float T = g.cruce / pace(f) * (m.paso == 1 ? 1.6f : 1.0f);
    const Color warm = f.colors[2], white = f.colors[3];
    for (const Pulse& p : slots) {
      const float age = float(now - p.start);
      if (age < 0.0f || age > T) continue;
      const float k = std::min(amount(p.power) * f.intensity, 1.3f) * (p.kind == 1 ? 1.2f : 1.0f);
      const float q = age / T;
      // Una vez, ida y vuelta, o dos franjas seguidas.
      float s = easeInOut(q);
      if (m.paso == 1) s = q < 0.5f ? easeInOut(q * 2.0f) : 1.0f - easeInOut(q * 2.0f - 1.0f);
      const float e = std::sin(float(pi) * q) * k;
      if (e < kMin) continue;
      c.material("sheen", {0.0f, 0.0f, W, H},
                 {s, e, g.angulo * float(pi) / 180.0f, g.ancho * (p.kind == 1 ? 1.4f : 1.0f), m.paso == 2 ? 1.0f : 0.0f, float(p.id % 5u),
                  warm.r, warm.g, warm.b, white.r, white.g, white.b},
                 {"dirt"});
    }
  }
};
''';

const shaderSources = <String, String>{
  'sheen': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uS;
uniform float uAmp;
uniform float uAngle;
uniform float uWidth;
uniform float uDouble;
uniform float uSeed;
uniform vec3 uWarm;
uniform vec3 uWhite;
uniform sampler2D uTex;
out vec4 fragColor;

// Filo irisado sólo delante: 8-10 px, como mucho +50, azul, verde y rojo
// fundidos en 3 px sin huecos.
vec3 fringe(float t) {
  float env = smoothstep(2.0, 4.0, t) * (1.0 - smoothstep(11.0, 14.0, t)) * 0.196;
  vec3 c = mix(vec3(0.29, 0.36, 1.0), vec3(0.19, 1.0, 0.6), smoothstep(5.0, 8.0, t));
  // Del verde al rojo con un pequeño valle, sin pasar por gris.
  float wG = 1.0 - smoothstep(8.0, 10.0, t);
  float wR = smoothstep(10.0, 12.0, t);
  return (c * wG + vec3(1.0, 0.165, 0.227) * wR) * env;
}

// Un reflejo (px de 360; xp > 0 delante de la línea): línea de 2-3 px
// quemada, resplandor frío (+120 a 3 px, +40 a 8), cuerpo frío de +40 detrás
// que cae a +8 a 60 px, segunda línea fina 25 px detrás y huellas del
// cristal que sólo se ven donde pasa la luz.
vec3 sheen(float xp, float wpx, float smudge, float tramo) {
  float d = abs(xp);
  vec3 cool = vec3(0.45, 0.65, 1.0);
  float line = 1.15 * exp(-xp * xp / 1.7);
  float bloom = min(0.47 * exp(-(d - 3.0) / 4.55), 0.9);
  // Cuerpo frío detrás: +40 a 8 px, +25 a 30, +12 a 60, +5 a 100; y un
  // resplandor tenue de +13 en los 10 px de delante.
  float b = max(-xp, 0.0) * 80.0 / wpx;
  float body = b < 8.0 ? 0.157 : (b < 30.0 ? mix(0.157, 0.098, (b - 8.0) / 22.0) : (b < 60.0 ? mix(0.098, 0.047, (b - 30.0) / 30.0)
             : (b < 100.0 ? mix(0.047, 0.0196, (b - 60.0) / 40.0) : mix(0.0196, 0.0, clamp((b - 100.0) / 60.0, 0.0, 1.0)))));
  body = (xp < 0.0 ? body * mix(1.0, 1.7, smoothstep(8.0, 60.0, b)) : 0.05 * (1.0 - smoothstep(0.0, 10.0, xp))) * (0.7 + 0.6 * smudge);
  // Segunda línea de 2 px suave, rota en tramos del 50-100 % a lo largo.
  float l2 = 0.4 * exp(-(xp + 25.0) * (xp + 25.0) / 2.0) * tramo;
  float lit = clamp(exp(-xp * xp / 72.0) + (xp < 0.0 ? 0.6 * exp(xp / 30.0) : 0.0), 0.0, 1.0);
  float prints = smoothstep(0.3, 0.6, smudge) * 0.22 * lit;
  return vec3(line) + (bloom + body + prints) * cool + l2 * vec3(0.5, 0.72, 1.0) + fringe(xp);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  vec2 n = vec2(cos(uAngle), sin(uAngle));
  vec2 c = 0.5 * uSize;
  float span = 0.5 * (abs(uSize.x * n.x) + abs(uSize.y * n.y)) + uWidth * uSize.x;
  // Posición a lo largo de la normal, con la franja un poco curvada.
  float along = dot(p - c, vec2(-n.y, n.x)) / uSize.x;
  float x = dot(p - c, n) - mix(-span, span, uS) + 0.035 * uSize.x * along * along;
  float xp = x / px1;
  float wpx = uWidth * 360.0;
  float smudge = texture(uTex, fract(p / uSize.x * 0.9 + vec2(uSeed * 0.21, 0.0))).g;
  float al = along * uSize.x / px1;
  float tramo = 0.5 + 0.5 * smoothstep(0.35, 0.65, 0.5 + 0.5 * sin(al / 23.0 + 1.7 * sin(al / 41.0) + uSeed * 6.0));
  vec3 light = sheen(xp, wpx, smudge, tramo);
  if (uDouble > 0.5) light += 0.7 * sheen(xp + 1.6 * wpx, 0.7 * wpx, smudge, tramo);
  // La línea quemada lleva un toque cálido muy leve.
  light *= uAmp * mix(vec3(1.0), mix(uWhite, uWarm, 0.1), 0.15);
  vec3 tone = min(light, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
