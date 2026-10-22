// Reactiva Mejorada · Cegadoras en Cadena — transparencia momentánea. Las «blinders» de un concierto
// miran al público, es decir, a cámara: módulos grandes de cuatro lámparas, como
// un Chauvet STRIKE 4, en dos filas escalonadas (la de arriba cortada por el
// borde), se encienden en cadena. Cada lámpara quema a blanco sólo en su centro,
// con dos resplandores suaves (1,5 y 6 veces su radio), su propio desfase y
// brillo, y una estrella de seis puntas igual en todas, como vista por una sola
// cámara. En el golpe, un resplandor cálido sube un instante; el brillo cae en
// unos tres cuadros y queda sólo el filamento, que se enfría de ámbar a naranja
// y rojo brasa sobre negro. Un cono de bruma suave baja de cada módulo.
// Referentes: Chauvet STRIKE 4 y Molefay en un drop, filmados por una cámara.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento las enciende.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Golpes acentuados', 'Cada tiempo', 'Caja']),
  // FORMA: cuántos módulos.
  CreatorModifier.steps('lamparas', 'Módulos', min: 3, max: 6, value: 4),
  // MOVIMIENTO: cómo se encienden.
  CreatorModifier.choice('cadena', 'Encendido', options: ['Desde el centro', 'De lado a lado', 'Todas a la vez']),
  // ATMÓSFERA: bruma en el aire bajo los módulos.
  CreatorModifier.slider('humo', 'Humo en el aire', min: 0, max: 1, value: .6),
  // Cuánto tarda en enfriarse el filamento.
  CreatorModifier.slider('enfriado', 'Enfriado', min: .25, max: .9, value: .55),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Estadio', {'lamparas': 6, 'cadena': 'De lado a lado', 'enfriado': .8, 'humo': 1}),
  CreatorVariation('Golpe Seco', {'cadena': 'Todas a la vez', 'enfriado': .3, 'lamparas': 3, 'humo': .3}),
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
    fire(d == 0 ? h.big : d == 1 ? every(h, 4) : h.snare, d == 2 ? 1 : 0);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const float W = f.width, H = f.height;
    const int n = std::clamp(int(std::lround(g.lamparas)), 3, 6);
    const float cool = g.enfriado / pace(f), flash = 0.18f / pace(f);
    const float wc = g.cadena.weight(0), wl = g.cadena.weight(1);
    // Cada módulo sigue el último golpe que le llega: su edad y su fuerza. El
    // shader calcula cada lámpara con su propio desfase.
    std::array<float, 6> ages{}, amps{};
    ages.fill(100.0f);
    float wash = 0.0f, firstAge = 100.0f, firstDelay = 100.0f;
    int first = 0;
    bool alive = false;
    for (const Pulse& p : slots) {
      const double age0 = now - p.start;
      if (age0 < -0.05 || age0 > 0.8 + 1.3 * double(cool)) continue;
      const bool odd = (p.id & 1u) != 0u;
      const float k = std::min(amount(p.power) * f.intensity, 1.3f);
      if (float(age0) < firstAge) {
        firstAge = float(age0);
        firstDelay = 100.0f;
        wash = k;
      }
      for (int i = 0; i < n; i++) {
        if (p.kind == 1 && ((i < n / 2) == odd)) continue;  // con la caja, un lado cada vez
        const float centerOrder = std::fabs(float(i) - 0.5f * float(n - 1));
        const float sideOrder = float(odd ? n - 1 - i : i);
        // En cadena: dos o tres cuadros entre módulos, con un poco de desorden.
        const float age = float(age0) - (wc * centerOrder + wl * sideOrder) * 0.08f - 0.015f * rnd(p.id * 17u + uint32_t(i));
        if (age < -0.05f || age > 0.3f + 1.3f * cool) continue;
        if (age < ages[size_t(i)]) {
          ages[size_t(i)] = age;
          amps[size_t(i)] = k;
        }
        // El primer módulo de la cadena del golpe más reciente.
        if (float(age0) == firstAge && float(age0) - age < firstDelay) {
          firstDelay = float(age0) - age;
          first = i;
        }
        alive = true;
      }
    }
    if (!alive) return;
    const Color ember = f.colors[1], orange = f.colors[2], white = f.colors[3];
    // Lámparas y bruma: sólo la parte de arriba.
    const float band = std::min(H, 1.3f * W);
    c.material("blinders", {0.0f, 0.0f, W, band},
               {float(now), float(n), g.humo,
                ages[0], ages[1], ages[2], ages[3], ages[4], ages[5],
                amps[0], amps[1], amps[2], amps[3], amps[4], amps[5], cool, flash,
                ember.r, ember.g, ember.b, orange.r, orange.g, orange.b, white.r, white.g, white.b},
               {"smoke"});
    // En el golpe, sobre todo lo demás, el resplandor del primer módulo: un
    // cuadro entero y el siguiente a la mitad de radio; luego nada.
    const float tFirst = firstAge - firstDelay;
    if (wash > kMin && tFirst >= 0.0f && tFirst < 0.067f) {
      const float spacing = 0.72f / float(std::max(n - 1, 1));
      const float unit = std::min(1.0f, (2.0f * spacing - 0.025f) / 0.424f);
      const float halfSize = (0.11f + 0.102f) * unit;
      const float fx = (0.14f + float(first) * spacing) * W;
      const float fy = (first % 2 == 0 ? 0.06f : 0.06f + 2.0f * halfSize + 0.03f) * W;
      // Escala de la curva: el segundo cuadro, a la mitad de radio.
      const float scale = (tFirst < 0.034f ? 1.0f : 0.5f) * W / 360.0f;
      c.material("lift", {0.0f, 0.0f, W, std::min(H, fy + 262.0f * scale)}, {std::min(wash, 1.0f), fx, fy, scale});
    }
  }
};
''';

const shaderSources = <String, String>{
  'lift': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uAmount;
uniform vec2 uCenter;
uniform float uScale;
out vec4 fragColor;

// Resplandor del golpe sobre el primer módulo, circular y sin meseta: blanco
// hasta 30 px y luego cae suave por ámbar y naranja hasta 260 px (en píxeles
// de una pantalla de 360).
vec3 glare(float r) {
  vec3 c1 = vec3(0.92, 0.86, 0.59);
  vec3 c2 = vec3(0.78, 0.59, 0.24);
  vec3 c3 = vec3(0.51, 0.27, 0.04);
  vec3 c4 = vec3(0.24, 0.1, 0.0);
  if (r < 60.0) return mix(vec3(1.0), c1, smoothstep(30.0, 60.0, r));
  if (r < 100.0) return mix(c1, c2, (r - 60.0) / 40.0);
  if (r < 150.0) return mix(c2, c3, (r - 100.0) / 50.0);
  if (r < 200.0) return mix(c3, c4, (r - 150.0) / 50.0);
  return mix(c4, vec3(0.0), clamp((r - 200.0) / 60.0, 0.0, 1.0));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec3 c = glare(length(p - uCenter) / uScale) * uAmount * smoothstep(uSize.y, uSize.y * 0.9, p.y);
  fragColor = vec4(c, 0.1 * max(c.r, max(c.g, c.b)));
}
''',

  'blinders': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uCount;
uniform float uSmoke;
uniform vec4 uAgeA;
uniform vec2 uAgeB;
uniform vec4 uAmpA;
uniform vec2 uAmpB;
uniform float uCool;
uniform float uFlash;
uniform vec3 uEmber;
uniform vec3 uOrange;
uniform vec3 uWhite;
uniform sampler2D uTex;
out vec4 fragColor;

// Entra en attack segundos y se apaga en dur (caída cuadrática), como en C++.
float env(float age, float attack, float dur) {
  if (age < 0.0) return 0.0;
  if (age < attack) return age / attack;
  float k = 1.0 - clamp((age - attack) / dur, 0.0, 1.0);
  return k * k;
}

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 uv = px / uSize.x;
  float ages[6];
  float amps[6];
  ages[0] = uAgeA.x; ages[1] = uAgeA.y; ages[2] = uAgeA.z; ages[3] = uAgeA.w; ages[4] = uAgeB.x; ages[5] = uAgeB.y;
  amps[0] = uAmpA.x; amps[1] = uAmpA.y; amps[2] = uAmpA.z; amps[3] = uAmpA.w; amps[4] = uAmpB.x; amps[5] = uAmpB.y;
  // Módulos 2x2 muy grandes en dos filas escalonadas que se salen del cuadro,
  // sin tocarse nunca (al menos 8 px entre carcasas); más pequeños si hay muchos.
  float spacing = 0.72 / max(uCount - 1.0, 1.0);
  float unit = min(1.0, (2.0 * spacing - 0.025) / 0.424);
  float off = 0.11 * unit;   // del centro del módulo a cada lámpara
  float Rc = 0.085 * unit;   // radio de cada lámpara
  float halfSize = off + Rc * 1.2;
  float aa = 1.0 / uSize.x;
  // Sensor según la temperatura del filamento: caliente, ámbar que quema a
  // blanco; frío, rojo brasa saturado.
  vec3 m = mix(uOrange, uWhite, 0.3);
  vec3 kHot = vec3(1.0, m.g / max(m.r, 0.01), 0.25 * m.b / max(m.r, 0.01));
  vec3 kCold = vec3(2.0, 2.0 * uEmber.g / max(uEmber.r, 0.01), 0.02);
  // El reflector cambia de color con su brillo: ámbar claro, naranja y rojo
  // vivo, sin pasar por bronce.
  vec3 hi3 = mix(uOrange, uWhite, 0.7) * vec3(1.0, 1.0, 0.7);
  vec3 mid3 = vec3(1.0, min(uOrange.g / max(uOrange.r, 0.01), 0.3), 0.06);
  vec3 lo3 = mix(uEmber, uOrange, 0.35);
  lo3 /= max(lo3.r, 0.01);
  vec3 light = vec3(0.0);
  float shade = 0.0;
  for (int i = 0; i < 6; i++) {
    float age = ages[i];
    float amp = amps[i];
    if (float(i) >= uCount || amp <= 0.0) continue;
    float eM = env(age, 0.02, uCool) * amp;
    float hM = env(age, 0.015, uFlash) * amp;
    if (eM < 0.003 && hM < 0.003 && age > 0.1) continue;
    vec3 k = mix(kCold, kHot, smoothstep(0.15, 0.7, max(eM, hM)));
    // Fuera del pico ningún brillo intermedio tira a cobre: el verde nunca pasa
    // del 30 % del rojo (sólo el núcleo del filamento llega a amarillo).
    k.g = min(k.g, mix(0.3, 1.0, smoothstep(0.6, 0.9, hM)) * k.r);
    float y = mod(float(i), 2.0) < 0.5 ? 0.06 : 0.06 + 2.0 * halfSize + 0.03;
    vec2 d = vec2(uv.x - (0.14 + float(i) * spacing), uv.y - y);
    float r2 = dot(d, d);
    float L = 0.0;
    // Las cuatro lámparas, cada una con su desfase (±40 ms) y su brillo (±15 %).
    float hottest = 0.0;
    if (r2 < 0.2) {
      for (int c = 0; c < 4; c++) {
        vec2 o = vec2(c == 0 || c == 2 ? -off : off, c < 2 ? -off : off);
        float jit = hash(float(i * 4 + c) + 1.7);
        float a = age - (jit - 0.5) * 0.08;
        float gain = amp * (0.85 + 0.3 * hash(float(i * 4 + c) + 9.1));
        float e = env(a, 0.02, uCool * (0.7 + 0.6 * jit)) * gain;
        float h = env(a, 0.015, uFlash) * gain;
        hottest = max(hottest, max(e, h));
        vec2 dc = d - o;
        float q2 = dot(dc, dc) / (Rc * Rc);
        float q = sqrt(q2);
        // Reflector parabólico caliente: doce facetas (±12 %), dos escalones a
        // 0,45R y 0,75R y un labio exterior nítido de 1,5 px.
        float cs = dc.x / max(q * Rc, 1e-4);
        float c4 = 2.0 * (2.0 * cs * cs - 1.0) * (2.0 * cs * cs - 1.0) - 1.0;
        float facets = 1.0 + 0.06 * (4.0 * c4 * c4 * c4 - 3.0 * c4);
        float lipW = 0.025 / unit;
        float s1 = (q - 0.45) / 0.033;
        float s2 = (q - 0.75) / 0.033;
        float lip = (q - 1.0) / lipW;
        // Núcleo quemado a blanco de unos 24 px dentro del reflector de 54 px.
        float h3 = h * h * h;
        L += 60.0 * h * h * exp(-q2 / 0.18);
        L += h3 * (2.2 * smoothstep(0.3, 0.9, q) * smoothstep(1.02, 0.97, q) * facets
                   + 0.25 * exp(-s1 * s1) + 0.25 * exp(-s2 * s2) + 0.9 * exp(-lip * lip));
        // Halo ámbar ajustado (sigma de unos 14 px).
        L += 1.0 * h * exp(-q2 / (0.42 / (unit * unit)));
        // Destello horizontal corto en cada lámpara, que se va con el brillo.
        L += 1.2 * h * exp(-abs(dc.y) / 0.004) * exp(-abs(dc.x) / 0.12);
        // Al enfriarse: el filamento, un punto caliente de 10-14 px a su
        // alrededor y el borde del reflector sólo mientras queda calor.
        vec2 fl = dc / (vec2(0.0085, 0.003) * unit);
        L += 9.0 * e * exp(-dot(fl, fl));
        // Reflector y punto caliente al enfriarse: su brillo cae como el
        // filamento^2,5 y su color sigue a ese brillo.
        // Al enfriarse el reflector brilla radial desde el filamento,
        // (1 - r/R)², y el aro sólo queda mientras el filamento está casi a
        // tope: más allá de 0,6R no queda casi nada.
        float lvl = e * e * e * e;
        float fillR = max(1.0 - q, 0.0);
        float e6 = lvl * e * e;
        float lr = 0.75 * lvl * fillR * fillR + 0.6 * e6 * smoothstep(0.83, 0.9, e) * smoothstep(0.62, 0.95, q) * smoothstep(1.06, 0.96, q);
        // El color sigue al brillo que se ve: por debajo del 60 %, rojo vivo.
        vec3 rc = mix(mix(lo3, mid3, smoothstep(0.25, 0.35, lr)), hi3, smoothstep(0.58, 0.68, lr));
        light += rc * lr;
      }
    }
    // Carcasa del módulo: rectángulo de esquinas de 6 px y borde de 1 px que
    // oscurece un 40 % sin color; se va cuando su filamento más caliente baja
    // del 30 %.
    vec2 bq = abs(d) - vec2(halfSize - 0.0167);
    float box = length(max(bq, 0.0)) + min(max(bq.x, bq.y), 0.0) - 0.0167;
    shade = max(shade, 0.4 * smoothstep(aa, -aa, box) * hottest * hottest * hottest * hottest * smoothstep(0.48, 0.52, hottest));
    // Cono de bruma suave hacia abajo, sólo en el destello.
    if (d.y > 0.0 && uSmoke > 0.0) {
      float cone = clamp(1.0 - abs(d.x) / (d.y * 0.8 + 0.06), 0.0, 1.0);
      if (cone > 0.0) {
        float sm = texture(uTex, fract(vec2(d.x * 0.6 + float(i) * 0.23, d.y * 0.35 - uTime * 0.04))).r;
        L += uSmoke * hM * cone * cone * (0.75 + 0.5 * sm) * 0.3 / (1.0 + d.y * d.y * 8.0);
      }
    }
    light += L * k;
  }
  light *= smoothstep(uSize.y, uSize.y * 0.6, px.y);  // nada llega al borde de la zona pintada
  vec3 tone = vec3(1.0) - exp(-light);
  shade *= smoothstep(uSize.y, uSize.y * 0.6, px.y);
  fragColor = vec4(tone, max(shade, 0.1 * max(tone.r, max(tone.g, tone.b))));
}
''',

};
