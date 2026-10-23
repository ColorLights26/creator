// Reactiva Mejorada · Halo de Hielo — transparencia momentánea. Al empezar una frase se enciende
// alrededor de una luz alta el halo de 22° que forman los cristales de hielo:
// dentro el cielo queda limpio; el borde interior sube en 2 px a rojo vivo,
// pasa por naranja y sólo es dorado donde más brilla, y hacia fuera se abre
// una cola blanca fría que se apaga en 45 px. Más intenso a los lados y
// arriba, con manchas que derivan. Arriba toca el arco tangente en ala de
// gaviota (un vértice en V con alas que suben y se aplanan); a los lados, los
// parhelios con su cara roja y su cola blanca azulada; un círculo parhélico
// tenue y polvo de diamante que titila. Se enciende en cuatro cuadros, se
// mantiene y se rompe en pedazos. La luz se suma a la escena. Referente:
// fotografías de halos y parhelios en el Ártico.
// Versión mejorada: sigue el ritmo (cada golpe o cada tiempo) y su fuerza
// depende del volumen de la música.
// Funciona encima de cualquier escena sin conocerla: sólo luz, sin objetos que
// se queden. Sin música no dibuja nada. Nunca más de tres destellos por segundo.
// Su detalle sale de una textura propia de alta calidad que el shader anima.
import 'package:scene_compositor/authoring.dart';

// Ajustes propios de este visual. Studio los muestra en Ajustes.
const modifiers = [
  // MÚSICA: qué momento lo enciende.
  CreatorModifier.choice('disparo', 'Lo dispara', options: ['Cada dos tiempos', 'Cada tiempo', 'Golpes acentuados']),
  // FORMA: tamaño del halo.
  CreatorModifier.slider('tamano', 'Tamaño del halo', min: .7, max: 1.3, value: 1),
  // MODO: soles laterales.
  CreatorModifier.toggle('parhelios', 'Parhelios', value: true),
  // ATMÓSFERA: polvo de diamante que titila.
  CreatorModifier.slider('polvo', 'Polvo de diamante', min: 0, max: 1, value: .6),
];

// Combinaciones con nombre que parecen otro visual.
const variations = [
  CreatorVariation('Ártico', {'tamano': 1.3, 'polvo': 1}),
  CreatorVariation('Anillo Solo', {'parhelios': false, 'polvo': .2, 'tamano': .8}),
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
    fire(d == 0 ? every(h, 16) : d == 1 ? every(h, 4) : h.big, d);
  }
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    const auto m = modifiers(f);
    const float W = f.width, H = f.height;
    // Vida: cuatro cuadros para encenderse, hasta 0,8 s de pie y se rompe
    // en pedazos hasta 1,15 s.
    float age = 100.0f, amp = 0.0f;
    for (const Pulse& p : slots) {
      const float a = float(now - p.start) * pace(f);
      if (a < 0.0f || a > 1.15f || a >= age) continue;
      age = a;
      amp = std::min(amount(p.power) * f.intensity, 1.2f);
    }
    if (amp <= 0.0f) return;
    const float R = g.tamano * 0.3f * W;
    const float cx = 0.5f * W, cy = 0.24f * H;
    const float y1 = std::min(H, cy + R * 1.6f);
    const Color red = f.colors[1], orange = f.colors[2], ice = f.colors[3];
    c.material("halo", {0.0f, 0.0f, W, y1},
               {cx, cy, R, age, amp, m.parhelios ? 1.0f : 0.0f, g.polvo, float(now),
                red.r, red.g, red.b, orange.r, orange.g, orange.b, ice.r, ice.g, ice.b},
               {"noise"});
  }
};
''';

const shaderSources = <String, String>{
  'halo': r'''
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uSun;
uniform float uR;
uniform float uAge;
uniform float uAmp;
uniform float uDogs;
uniform float uDust;
uniform float uTime;
uniform vec3 uRed;
uniform vec3 uOrange;
uniform vec3 uIce;
uniform sampler2D uTex;
out vec4 fragColor;

float hash(float n) {
  return fract(sin(n * 12.9898) * 43758.5453);
}
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Halo por distancia al radio (px): nada dentro hasta R-3, sube en 2 px,
// cola fría de +150 a R+12, +80 a R+20, +35 a R+30 y nada a R+45.
float haloI(float x) {
  if (x < -3.0) return 0.0;
  if (x < -1.0) return smoothstep(-3.0, -1.0, x) * 0.85;
  if (x < 2.0) return mix(0.85, 0.9, (x + 1.0) / 3.0);
  if (x < 12.0) return mix(0.9, 0.59, (x - 2.0) / 10.0);
  if (x < 20.0) return mix(0.59, 0.31, (x - 12.0) / 8.0);
  if (x < 30.0) return mix(0.31, 0.14, (x - 20.0) / 10.0);
  return mix(0.14, 0.0, clamp((x - 30.0) / 15.0, 0.0, 1.0));
}

// Color del halo: rojo dentro y rojo anaranjado (#FF4A10); dorado sólo donde
// el anillo pasa del 80 % y en 2 px; el cálido acaba en R+5 y desde ahí sube
// el blanco frío de la cola, sin mezclarse en beige.
vec3 haloC(float x, float I, vec3 red, vec3 ice) {
  vec3 orRed = vec3(1.0, 0.29, 0.063);
  vec3 warm = mix(red, orRed, smoothstep(-1.0, 2.0, x));
  float gold = smoothstep(0.72, 0.8, I) * exp(-(x - 1.0) * (x - 1.0) / 0.8);
  warm = mix(warm, vec3(1.0, 0.82, 0.38), gold);
  // Donde el anillo es más brillante, blanco cálido quemado en R+2..R+3.
  float hot = smoothstep(0.82, 0.92, I) * exp(-(x - 2.5) * (x - 2.5) / 0.8);
  warm = mix(warm, vec3(1.0, 0.97, 0.88) * 1.18, hot);
  return warm * (1.0 - smoothstep(3.0, 5.0, x)) + ice * smoothstep(3.5, 6.0, x);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float px1 = uSize.x / 360.0;
  vec2 q = p - uSun;
  float r = length(q);
  float Rp = uR / px1;
  float x = (r - uR) / px1;
  float th = atan(q.y, q.x);
  // Vida: se enciende en cuatro cuadros, se mantiene y se rompe en pedazos.
  float build = smoothstep(0.0, 0.13, uAge);
  float breakT = smoothstep(0.8, 1.08, uAge);
  float breakA = smoothstep(0.74, 0.98, uAge);
  float breakS = smoothstep(0.92, 1.13, uAge);
  float xt = clamp(x, 0.0, 45.0) / 45.0;
  float piece = 0.5 + 0.3 * sin(4.0 * th + 0.03 * x + 1.7) + 0.2 * sin(7.0 * th - 0.05 * x + 3.4);
  float kill = mix(-0.4, 1.45, breakT) + 0.25 * xt;
  float dim = 1.0 - 0.5 * smoothstep(0.95, 1.08, uAge);
  float alive = build * smoothstep(kill - 0.35, kill + 0.05, piece) * dim;
  float ux = q.x / px1;
  float pieceA = 0.5 + 0.3 * sin(ux / 22.0 + 1.7) + 0.2 * sin(ux / 13.0 - 0.07 * q.y / px1 + 3.4);
  float killA = mix(-0.4, 1.45, breakA);
  float aliveA = build * smoothstep(killA - 0.35, killA + 0.05, pieceA);
  float aliveS = build * (1.0 - breakS);
  // Más intenso a los lados y arriba, con manchas que derivan.
  float around = (0.6 + 0.4 * abs(cos(2.0 * th))) * (1.0 + 0.12 * sin(3.0 * th + uTime * 3.9) + 0.08 * sin(5.0 * th - uTime * 6.5));
  float hI = haloI(x) * around;
  vec3 iceC = vec3(0.4, 0.64, 1.0) * mix(vec3(1.0), uIce / max(uIce.b, 0.01), 0.15);
  vec3 light = hI * haloC(x, hI, uRed, iceC) * alive;
  // Arco tangente en ala de gaviota: vértice en V sobre el halo y alas que
  // suben unos 35° y se aplanan, de 80-100 px; el borde de abajo, rojo.
  float u = abs(q.x) / px1;
  float yTop = -Rp;
  float yArc = yTop - 40.0 * (1.0 - exp(-u / 50.0));
  float dyA = (q.y / px1) - yArc;
  float tA = clamp(u / 95.0, 0.0, 1.0);
  float wingB = 0.7 * pow(1.0 - tA, 1.5) * 0.9;
  float arcI = wingB * 1.4 * (dyA > 0.0 ? exp(-dyA * dyA / 2.0) : exp(dyA / 5.0));
  vec3 arcC = mix(iceC, uRed, smoothstep(0.0, 1.0, dyA));
  arcC = mix(arcC, vec3(1.0), (1.0 - smoothstep(0.0, 0.15, tA)) * smoothstep(0.5, 0.6, arcI));
  light += arcI * arcC * aliveA;
  // Parhelios: 3-6 px fuera del halo, cara roja hacia el sol, núcleo quemado
  // pequeño y cola blanca azulada de 40-70 px hacia fuera; respiran un poco.
  vec3 dogs = vec3(0.0);
  for (int i = 0; i < 2; i++) {
    float side = i == 0 ? -1.0 : 1.0;
    vec2 v = (q - vec2(side * (uR + 9.0 * px1), 0.0)) / px1;
    float ax = side * v.x;
    float body = exp(-ax * ax / 25.0 - v.y * v.y / 169.0);
    float core = exp(-ax * ax / 4.0 - v.y * v.y / 25.0) * 1.4;
    // Cara roja sólo hacia el sol; hacia fuera y arriba/abajo, de blanco a frío.
    vec3 sideCol = mix(uRed, mix(uOrange, vec3(1.0, 0.29, 0.063), 0.6), smoothstep(-6.0, -2.0, ax));
    sideCol = mix(sideCol, iceC, smoothstep(-2.0, 2.0, ax));
    float tail = exp(-abs(v.y) / 3.0) * exp(-max(ax, 0.0) / 25.0) * smoothstep(5.0, 11.0, ax) * (1.0 - smoothstep(55.0, 70.0, ax)) * 0.45;
    dogs += (body * sideCol * 0.9 + core * vec3(1.0) + tail * iceC) * (1.0 + 0.1 * sin(uTime * 9.0 + side * 1.7));
  }
  light += dogs * uDogs * aliveS;
  // Círculo parhélico tenue y azulado (más tenue dentro del halo) y el
  // brillo frío del sol, que se apaga a 50 px.
  float pl = exp(-abs(q.y) / (px1 * 1.0)) * 0.14 * (r < uR ? 0.4 : 1.0) * exp(-abs(q.x) / (uR * 1.6));
  light += pl * vec3(0.55, 0.65, 1.0) * aliveA;
  float rp = r / px1;
  float sun = (rp < 4.0 ? 1.1 : 0.0) + pow(1.0 - smoothstep(0.0, 50.0, rp), 2.0) * 0.45;
  light += sun * mix(vec3(0.55, 0.7, 1.0), vec3(1.0), smoothstep(0.7, 0.9, sun)) * build * (1.0 - breakS);
  // Polvo de diamante: un punto de 1 px con brillo radial, mirando las
  // celdas vecinas; titila cada pocos cuadros.
  vec2 cell0 = floor(p / (9.0 * px1));
  float dust = 0.0;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 cell = cell0 + vec2(float(i), float(j));
      if (hash2(cell) < 0.975) continue;
      vec2 cp = (cell + vec2(hash2(cell + 2.3), hash2(cell + 5.9))) * 9.0 * px1;
      float tw = step(0.4, hash2(cell + floor(uTime * (6.0 + 4.0 * hash2(cell + 1.1)))));
      float dd = length(p - cp) / px1;
      dust += tw * (exp(-dd * dd / 0.5) + 0.4 * exp(-dd * dd / 2.9));
    }
  }
  light += dust * uDust * 1.6 * iceC * build * (1.0 - breakT);
  light *= uAmp * smoothstep(uSize.y, uSize.y * 0.8, p.y);
  vec3 tone = min(light, vec3(1.0));
  fragColor = vec4(tone, 0.1 * max(tone.r, max(tone.g, tone.b)));
}
''',

};
