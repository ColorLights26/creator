// Reactiva Mejorada · Latido Completo — transparencia momentánea. Una reacción por sonido: el bombo
// baja la luz de la escena a fondo en el mismo golpe y la devuelve suave,
// primero en el centro; la caja abre en el centro un destello cálido pequeño
// (blanco quemado, oro y rojo anaranjado) que se apaga encogiéndose en tres
// cuadros; y el golpe grande lanza el reflejo de un vidrio que cruza la
// escena (línea quemada con resplandor frío, cuerpo frío tenue, segunda
// línea suave y filo irisado). Si bombo y caja coinciden, suenan juntos.
// Referente: la luz de un club que responde a cada parte del ritmo.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué reacciones usa.
  CreatorModifier.choice('reacciones', 'Reacciones', options: ['Todo', 'Sombra y luz', 'Con reflejo', 'Sombra y reflejo']),
  // FORMA: de toda la pantalla (0) a sólo los bordes (1).
  CreatorModifier.slider('borde', 'Hacia los bordes', min: 0, max: 1, value: .3),
  // MOVIMIENTO: cuánto tarda en volver.
  CreatorModifier.slider('caida', 'Caída', min: .1, max: .5, value: .2),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Club', {'reacciones': 'Todo', 'caida': .16, 'borde': .15}),
  CreatorVariation('Respiro', {'reacciones': 'Sombra y reflejo', 'caida': .4, 'borde': .8}),
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
  float gapEma = 0.5f;
  double lastHit = -100.0;
  void noteHit() {
    const double gap = now - lastHit;
    if (gap > 0.2 && gap < 2.0) gapEma += (float(gap) - gapEma) * 0.3f;
    lastHit = now;
  }
  const Pulse* latest(int kind = -1) const {
    const Pulse* best = nullptr;
    for (const Pulse& p : slots)
      if (p.start <= now && (kind < 0 || p.kind == kind) && (best == nullptr || p.start > best->start)) best = &p;
    return best;
  }
  void resetOwn(uint32_t) {
    gapEma = 0.5f;
    lastHit = -100.0;
  }
  void update(const Frame& f) override {
    const Hits h = listen(f);
    const bool kick = fire(h.kick, 0);
    if (kick) noteHit();
    // Si la caja cae con el bombo, suenan juntos como un solo destello.
    if (h.snare > 0.0f) fire(h.snare, 1, 0.0, !kick);
    if (h.big > 0.0f) fire(h.big, 2, 0.0, false);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    const bool useDuck = m.reacciones != 2, useGlow = m.reacciones != 3, useSheen = m.reacciones != 1;
    const Color shadow = f.colors[1], warm = f.colors[2], white = f.colors[3];
    // Bombo: sombra al 83 % de Latido Oscuro.
    float dark = 0.0f, ageK = 0.0f, ox = 0.0f, oy = 0.0f, phi = 0.0f;
    const float rel = std::min((g.caida + 0.04f) / pace(f), 0.65f * gapEma);
    const Pulse* kp = latest(0);
    if (useDuck && kp != nullptr) {
      ageK = float(now - kp->start);
      if (ageK <= rel + 0.04f) {
        dark = 0.3f * std::min(amount(kp->power) * f.intensity, 1.2f);
        ox = (rnd(kp->id * 3u + 1u) - 0.5f) * 40.0f;
        oy = (rnd(kp->id * 5u + 2u) - 0.5f) * 72.0f;
        phi = rnd(kp->id * 7u + 3u) * 6.2832f;
      }
    }
    // Caja: destello pequeño que se encoge en tres cuadros.
    float glow = 0.0f, glowR = 0.0f;
    const Pulse* sp = latest(1);
    if (useGlow && sp != nullptr) {
      const float a = float(now - sp->start) * pace(f);
      if (a < 0.1f) {
        glow = std::min(amount(sp->power) * f.intensity, 1.2f);
        glowR = 0.53f * std::pow(1.0f - a / 0.1f, 0.8f);
      }
    }
    if (dark > kMin || glow > kMin)
      c.material("duck", {0.0f, 0.0f, W, H},
                 {dark, g.borde, ageK, rel, ox, oy, phi, glow, glowR,
                  shadow.r, shadow.g, shadow.b, warm.r, warm.g, warm.b, white.r, white.g, white.b});
    // Golpe grande: el reflejo de un vidrio que cruza.
    const Pulse* bp = latest(2);
    if (useSheen && bp != nullptr) {
      const float q = float(now - bp->start) * pace(f) / 0.8f;
      if (q < 1.0f) {
        const float amp = std::sin(float(pi) * q) * std::min(amount(bp->power) * f.intensity, 1.2f);
        if (amp > kMin)
          c.material("sheen", {0.0f, 0.0f, W, H}, {easeInOut(q), amp, 0.44f, 0.22f, warm.r, warm.g, warm.b, white.r, white.g, white.b}, {"dirt"});
      }
    }
  }
};
''';

const shaderSources = <String, String>{
  'duck': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uDark;
uniform float uEdge;
uniform float uAge;
uniform float uRel;
uniform vec2 uOff;
uniform float uPhi;
uniform float uLight;
uniform float uGlowR;
uniform vec3 uShadow;
uniform vec3 uWarm;
uniform vec3 uWhite;
out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  vec2 hs = 0.5 * uSize;
  vec2 c = p - hs - uOff * px1;
  vec2 d = c / hs;
  float rs = pow(pow(abs(d.x), 2.6) + pow(abs(d.y), 2.6), 1.0 / 2.6);
  // Sombra sin color: el centro baja un 65 % de lo que bajan las esquinas, o
  // sólo hacia los bordes; cada golpe con su propia forma (±10 %).
  float whole = mix(0.64, 1.0, smoothstep(0.0, 1.3, length(d)));
  float prof = mix(whole, smoothstep(0.25, 1.15, rs), uEdge) * (1.0 + 0.1 * cos(2.0 * atan(d.y, d.x) + uPhi));
  // A fondo en el mismo cuadro del golpe, un cuadro más, y la luz vuelve
  // primero en el centro y al final en las esquinas.
  float hold = 0.034;
  float Tr = uRel * (0.55 + 0.45 * smoothstep(0.0, 1.1, rs));
  float e = uAge < hold ? 1.0 : 1.0 - smoothstep(0.0, Tr, uAge - hold);
  float shade = uDark * prof * e;
  // Luz: un círculo en px (como mucho 1,2 veces más alto que ancho) por la
  // rampa cálida, que se apaga encogiéndose: quemado sólo en 16 px, +250 a
  // 24, +240 a 34, +228 a 44, de blanco a oro en 44-58 px y de oro a rojo en
  // 62-76 px, +153/+44 a 75, +102/+28 a 110, +51/+14 a 150 y nada a 230.
  float rp = length(c / px1 * vec2(1.0, 1.0 / 1.2)) / max(uGlowR, 0.001);
  // El brillo baja desde el mismo borde del quemado (16 px) sin mesetas:
  // +250 a 16, +228 a 30, +205 a 45, +178 a 62, +150 a 80, +120 a 105,
  // +85 a 135, +50 a 170, +20 a 210 y nada a 245.
  float I = rp < 16.0 ? mix(1.12, 0.98, rp / 16.0) : (rp < 30.0 ? mix(0.98, 0.894, (rp - 16.0) / 14.0) : (rp < 45.0 ? mix(0.894, 0.804, (rp - 30.0) / 15.0)
          : (rp < 62.0 ? mix(0.804, 0.698, (rp - 45.0) / 17.0) : (rp < 80.0 ? mix(0.698, 0.588, (rp - 62.0) / 18.0)
          : (rp < 105.0 ? mix(0.588, 0.47, (rp - 80.0) / 25.0) : (rp < 135.0 ? mix(0.47, 0.333, (rp - 105.0) / 30.0)
          : (rp < 170.0 ? mix(0.333, 0.196, (rp - 135.0) / 35.0) : (rp < 210.0 ? mix(0.196, 0.078, (rp - 170.0) / 40.0)
          : mix(0.078, 0.0, clamp((rp - 210.0) / 35.0, 0.0, 1.0))))))))));
  I *= step(0.001, uGlowR);
  // El tono cambia a la vez que baja el brillo (sin disco blanco ni anillo
  // de oro): G/R 0,95 -> 0,80 -> 0,64 -> 0,45 -> 0,30 y B/R 0,85 -> 0,45 ->
  // 0,15 -> 0,05.
  float L = I * uLight;
  float gr = L > 0.894 ? mix(0.8, 0.95, (L - 0.894) / 0.086) : (L > 0.804 ? mix(0.64, 0.8, (L - 0.804) / 0.09)
           : (L > 0.698 ? mix(0.45, 0.64, (L - 0.698) / 0.106) : (L > 0.588 ? mix(0.3, 0.45, (L - 0.588) / 0.11) : 0.3)));
  float br = L > 0.894 ? mix(0.45, 0.85, (L - 0.894) / 0.086) : (L > 0.804 ? mix(0.15, 0.45, (L - 0.804) / 0.09)
           : (L > 0.698 ? mix(0.05, 0.15, (L - 0.698) / 0.106) : mix(0.0, 0.05, clamp((L - 0.5) / 0.198, 0.0, 1.0))));
  vec3 col = vec3(1.0, min(gr, 1.0), min(br, 1.0)) * mix(vec3(1.0), uWarm / max(uWarm.r, 0.01), 0.04) * mix(vec3(1.0), uWhite, 0.04);
  vec3 light = col * min(L, 1.0);
  float m = max(light.r, max(light.g, light.b));
  fragColor = vec4(light + uShadow * shade, clamp(max(shade * (1.0 - m), 0.1 * m), 0.0, 1.0));
}
''',

  'sheen': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uS;
uniform float uAmp;
uniform float uAngle;
uniform float uWidth;
uniform vec3 uWarm;
uniform vec3 uWhite;
uniform sampler2D uTex;
out vec4 fragColor;

// Filo irisado sólo delante, de dos tonos: azul a 5,5 px y verde a 9,5 px,
// como mucho +50 cada uno.
vec3 fringe(float t) {
  float b = exp(-(t - 5.5) * (t - 5.5) / 3.4);
  float g = exp(-(t - 9.5) * (t - 9.5) / 3.4);
  return 0.196 * (b * vec3(0.29, 0.36, 1.0) + g * vec3(0.19, 1.0, 0.33));
}

// El reflejo de un vidrio (px de 360; xp > 0 delante de la línea): línea
// quemada de 2-3 px con resplandor frío, cuerpo frío tenue detrás, segunda
// línea suave rota por las huellas y huellas que se ven donde pasa la luz.
void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  vec2 n = vec2(cos(uAngle), sin(uAngle));
  vec2 c = 0.5 * uSize;
  float span = 0.5 * (abs(uSize.x * n.x) + abs(uSize.y * n.y)) + uWidth * uSize.x;
  float along = dot(p - c, vec2(-n.y, n.x)) / uSize.x;
  float x = dot(p - c, n) - mix(-span, span, uS) + 0.035 * uSize.x * along * along;
  float xp = x / px1;
  float wpx = uWidth * 360.0;
  float smudge = texture(uTex, fract(p / uSize.x * 0.9)).g;
  float dd = abs(xp);
  vec3 cool = vec3(0.3, 0.56, 1.0);
  float line = 1.15 * exp(-xp * xp / 1.7);
  float bloom = min(0.47 * exp(-(dd - 3.0) / 4.55), 0.9);
  float b = max(-xp, 0.0) * 80.0 / wpx;
  float body = b < 8.0 ? 0.157 : (b < 30.0 ? mix(0.157, 0.098, (b - 8.0) / 22.0) : (b < 60.0 ? mix(0.098, 0.047, (b - 30.0) / 30.0)
             : (b < 100.0 ? mix(0.047, 0.0196, (b - 60.0) / 40.0) : mix(0.0196, 0.0, clamp((b - 100.0) / 60.0, 0.0, 1.0)))));
  body = (xp < 0.0 ? body : 0.05 * (1.0 - smoothstep(0.0, 10.0, xp))) * (0.7 + 0.6 * smudge);
  float l2 = 0.4 * exp(-(xp + 25.0) * (xp + 25.0) / 2.0) * (0.5 + 0.5 * smoothstep(0.3, 0.7, smudge));
  float lit = clamp(exp(-xp * xp / 72.0) + (xp < 0.0 ? 0.6 * exp(xp / 30.0) : 0.0), 0.0, 1.0);
  float prints = smoothstep(0.35, 0.8, smudge) * 0.2 * lit;
  vec3 light = vec3(line) + (bloom + body + prints) * cool + l2 * vec3(0.5, 0.72, 1.0) + fringe(xp);
  light *= uAmp * mix(vec3(1.0), mix(uWhite, uWarm, 0.1), 0.15);
  vec3 tone = min(light, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
